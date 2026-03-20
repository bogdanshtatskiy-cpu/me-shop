-- /obmen/me_logic.lua
local component = require("component")
local sides = require("sides")

local me = {}
local transposer, inv_ctrl, db, me_bus

-- =========================================================
-- НАСТРОЙКИ СТОРОН (ПОМЕНЯЙ, ЕСЛИ СУНДУКИ СТОЯТ ИНАЧЕ)
-- =========================================================
-- ЛЕВАЯ ЧАСТЬ (ТРАНСПОУЗЕР)
local T_INPUT  = sides.up     -- Где стоит сундук с рудой относительно Транспоузера
local T_DUMP   = sides.down   -- Где стоит МЭ Интерфейс (для сброса) относительно Транспоузера

-- ПРАВАЯ ЧАСТЬ (АДАПТЕРЫ И ВЫДАЧА)
local A_OUTPUT  = sides.up    -- Где стоит сундук со слитками относительно Адаптера 1
local ME_EXPORT = sides.up    -- Куда МЭ Интерфейс должен выплевывать слитки (в сундук)
-- =========================================================

function me.init()
    if not component.isAvailable("transposer") then return false, "Транспоузер не подключен кабелем!" end
    transposer = component.transposer
    
    if not component.isAvailable("inventory_controller") then return false, "Адаптер 1 (с Контроллером инвентаря) не подключен!" end
    inv_ctrl = component.inventory_controller
    
    if not component.isAvailable("database") then return false, "Адаптер 2 (с Базой Данных) не подключен!" end
    db = component.database
    
    if component.isAvailable("me_interface") then me_bus = component.me_interface
    elseif component.isAvailable("me_controller") then me_bus = component.me_controller
    else return false, "МЭ Интерфейс не подключен кабелем к Адаптеру 2!" end
    
    return true, "OK"
end

function me.getScanItems()
    local in_stack = transposer.getStackInSlot(T_INPUT, 1)
    local out_stack = inv_ctrl.getStackInSlot(A_OUTPUT, 1)
    return in_stack, out_stack
end

function me.storeToDB(db_slot)
    -- Берем слепок слитка Контроллером Инвентаря и кладем в Базу Данных
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
    local items = me_bus.getItemsInNetwork()
    local stock_map = {}
    for _, item in ipairs(items) do
        local key = item.name .. ":" .. math.floor(item.damage or 0)
        stock_map[key] = (stock_map[key] or 0) + item.size
    end
    for _, t in ipairs(trades) do
        local key = t.output.name .. ":" .. math.floor(t.output.damage or 0)
        t.stock = stock_map[key] or 0
    end
end

function me.processExchange(slot, input_qty, db_slot, output_qty)
    -- 1. Скидываем руду в МЭ через Транспоузер
    local pushed = transposer.transferItem(T_INPUT, T_DUMP, input_qty, slot)
    if pushed < input_qty then return false, "Ошибка сброса руды" end
    
    -- 2. Выдаем слитки через МЭ Интерфейс
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
