-- /obmen/me_logic.lua
local component = require("component")
local sides = require("sides")

local me = {}
local transposer, inv_ctrl, db, me_bus
local a_out

-- =========================================================
-- ЖЕСТКИЕ НАСТРОЙКИ СТОРОН
-- =========================================================
local T_INPUT  = 1 -- ВВЕРХ (Сундук над транспоузером)
local T_DUMP   = 0 -- ВНИЗ (МЭ Интерфейс под транспоузером)
local ME_EXPORT = 1 -- ВВЕРХ (МЭ Интерфейс выдает слитки вверх в сундук)
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
    
    -- Ищем сундук со слитками вокруг Адаптера
    for s = 0, 5 do
        local ok, sz = pcall(inv_ctrl.getInventorySize, s)
        if ok and sz and sz >= 27 then 
            a_out = s
            break 
        end
    end

    if not a_out then return false, "Адаптер 1 не видит выходной сундук!" end
    
    return true, "OK"
end

function me.getScanItems()
    local in_stack = transposer.getStackInSlot(T_INPUT, 1)
    local out_stack = inv_ctrl.getStackInSlot(a_out, 1)
    return in_stack, out_stack
end

function me.storeToDB(db_slot)
    return inv_ctrl.store(a_out, 1, db.address, db_slot)
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
    local size = inv_ctrl.getInventorySize(a_out)
    if not size then return 0 end
    for i = 1, size do
        local stack = inv_ctrl.getStackInSlot(a_out, i)
        if not stack then free = free + 64
        elseif stack.name == target_name and math.floor(stack.damage or 0) == math.floor(target_dmg or 0) then
            free = free + (stack.maxSize - stack.size)
        end
    end
    return free
end

function me.updateStock(trades)
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
    
    -- Бронебойная защита от багов Транспоузера
    if type(pushed) == "boolean" and not pushed then
        return false, "МЭ интерфейс занят"
    elseif type(pushed) == "number" and pushed < input_qty then
        return false, "МЭ не приняло всю руду"
    elseif not pushed then
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
