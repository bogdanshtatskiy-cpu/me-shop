-- /obmen/me_logic.lua
local component = require("component")
local sides = require("sides")

local me = {}
local transposer, inv_ctrl, db, me_bus

-- =========================================================
-- ЖЕСТКИЕ НАСТРОЙКИ СТОРОН
-- =========================================================
local T_INPUT  = sides.up     -- Сундук с рудой СВЕРХУ от Транспоузера
local T_DUMP   = sides.down   -- МЭ Интерфейс СНИЗУ от Транспоузера
local A_OUTPUT  = sides.up    -- Сундук со слитками СВЕРХУ от Адаптера 1
local ME_EXPORT = sides.up    -- МЭ Интерфейс выплевывает слитки ВВЕРХ в сундук
-- =========================================================

function me.init()
    if not component.isAvailable("transposer") then return false, "Транспоузер не подключен!" end
    transposer = component.transposer
    
    if not component.isAvailable("inventory_controller") then return false, "Адаптер 1 (Контроллер инв.) не подключен!" end
    inv_ctrl = component.inventory_controller
    
    if not component.isAvailable("database") then return false, "Адаптер 2 (База Данных) не подключен!" end
    db = component.database
    
    if component.isAvailable("me_interface") then me_bus = component.me_interface
    elseif component.isAvailable("me_controller") then me_bus = component.me_controller
    else return false, "МЭ Интерфейс (для выдачи) не подключен!" end
    
    return true, "OK"
end

function me.getScanItems()
    local in_stack = transposer.getStackInSlot(T_INPUT, 1)
    local out_stack = inv_ctrl.getStackInSlot(A_OUTPUT, 1)
    return in_stack, out_stack
end

function me.storeToDB(db_slot)
    return inv_ctrl.store(A_OUTPUT, 1, db.address, db_slot)
end

function me.getInputInventory()
    local inv = {}
    local size = transposer.getInventorySize(T_INPUT)
    if not size then return inv end
    for i = 1, size do
        local stack = transposer.getStackInSlot(T_INPUT, i)
        if stack then inv[i] = stack end
    end
    return inv
end

function me.getFreeSpace(target_name, target_dmg)
    local free = 0
    local size = inv_ctrl.getInventorySize(A_OUTPUT)
    if not size then return 0 end
    for i = 1, size do
        local stack = inv_ctrl.getStackInSlot(A_OUTPUT, i)
        if not stack then free = free + 64
        elseif stack.name == target_name and math.floor(stack.damage or 0) == math.floor(target_dmg or 0) then
            free = free + (stack.maxSize - stack.size)
        end
    end
    return free
end

function me.updateStock(trades)
    -- СУПЕР-ОПТИМИЗАЦИЯ: СПРАШИВАЕМ У МЭ ТОЛЬКО НУЖНЫЕ ПРЕДМЕТЫ
    for _, t in ipairs(trades) do
        t.stock = 0
        local ok, items = pcall(me_bus.getItemsInNetwork, {name = t.output.name, damage = t.output.damage})
        if ok and items then
            for _, item in pairs(items) do
                if type(item) == "table" and item.name == t.output.name then
                    t.stock = t.stock + (item.size or 0)
                end
            end
        end
    end
end

function me.processExchange(slot, input_qty, db_slot, output_qty)
    local pushed = transposer.transferItem(T_INPUT, T_DUMP, input_qty, slot)
    
    -- ФИКС ОШИБКИ "BOOLEAN WITH NUMBER" И ЗАЩИТА ОТ КРАШЕЙ
    if type(pushed) == "boolean" and pushed == false then
        return false, "МЭ интерфейс занят или переполнен"
    elseif type(pushed) == "number" and pushed < input_qty then
        return false, "МЭ интерфейс не принял всю руду"
    elseif type(pushed) == "nil" then
        return false, "Сбой транспоузера"
    end
    
    local exported = 0
    local try_count = 0
    while exported < output_qty and try_count < 5 do
        local chunk = math.min(output_qty - exported, 64)
        local ok, err = pcall(function()
            me_bus.exportItem(db.address, db_slot, chunk, ME_EXPORT)
        end)
        if ok then exported = exported + chunk else break end
        try_count = try_count + 1
    end
    return true, "OK"
end

return me
