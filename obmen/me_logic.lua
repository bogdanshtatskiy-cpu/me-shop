-- /obmen/me_logic.lua
local component = require("component")
local sides = require("sides")

local me = {}
local transposer, inv_ctrl, db, me_bus
local t_in, t_dump, a_out

-- Куда МЭ интерфейс должен выплевывать слитки (1 = вверх, прямо в сундук над ним)
local ME_EXPORT = sides.up

function me.init()
    if not component.isAvailable("transposer") then return false, "Транспоузер не подключен!" end
    transposer = component.transposer
    
    if not component.isAvailable("inventory_controller") then return false, "Адаптер 1 (с Контроллером инв.) не подключен!" end
    inv_ctrl = component.inventory_controller
    
    if not component.isAvailable("database") then return false, "Адаптер 2 (с Базой Данных) не подключен!" end
    db = component.database
    
    if component.isAvailable("me_interface") then me_bus = component.me_interface
    elseif component.isAvailable("me_controller") then me_bus = component.me_controller
    else return false, "МЭ Интерфейс (для выдачи) не подключен!" end
    
    -- УМНЫЙ АВТОПОИСК ДЛЯ ТРАНСПОУЗЕРА (ЛЕВАЯ ЧАСТЬ)
    for s = 0, 5 do
        local ok, sz = pcall(transposer.getInventorySize, s)
        if ok and sz then
            if sz >= 27 then t_in = s          -- Нашел огромный сундук руды
            elseif sz > 0 then t_dump = s end  -- Нашел маленький инвентарь (МЭ Интерфейс)
        end
    end
    
    -- УМНЫЙ АВТОПОИСК ДЛЯ АДАПТЕРА 1 (ПРАВАЯ ЧАСТЬ)
    for s = 0, 5 do
        local ok, sz = pcall(inv_ctrl.getInventorySize, s)
        -- Адаптер сам ищет, с какой стороны от него стоит сундук!
        if ok and sz and sz >= 27 then a_out = s; break end 
    end

    if not t_in then return false, "Транспоузер не видит входной сундук!" end
    if not t_dump then return false, "Транспоузер не видит МЭ для сброса!" end
    if not a_out then return false, "Контроллер инвентаря не видит выходной сундук!" end
    
    return true, "OK"
end

function me.getScanItems()
    local in_stack = transposer.getStackInSlot(t_in, 1)
    local out_stack = inv_ctrl.getStackInSlot(a_out, 1)
    return in_stack, out_stack
end

function me.storeToDB(db_slot)
    return inv_ctrl.store(a_out, 1, db.address, db_slot)
end

function me.getInputInventory()
    local inv = {}
    local size = transposer.getInventorySize(t_in)
    if not size then return inv end
    for i = 1, size do
        local stack = transposer.getStackInSlot(t_in, i)
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
    -- 1. Скидываем руду
    local pushed, err = transposer.transferItem(t_in, t_dump, input_qty, slot)
    
    -- ЖЕЛЕЗОБЕТОННЫЙ ФИКС ОШИБКИ "BOOLEAN WITH NUMBER"
    if type(pushed) == "boolean" and not pushed then
        return false, "МЭ интерфейс занят или переполнен"
    elseif type(pushed) == "number" and pushed < input_qty then
        return false, "МЭ интерфейс не принял всю руду"
    elseif not pushed then
        return false, "Сбой транспоузера"
    end
    
    -- 2. Выдаем слитки
    local exported = 0
    local try_count = 0
    while exported < output_qty and try_count < 5 do
        local chunk = math.min(output_qty - exported, 64)
        local ok, err_msg = pcall(function()
            me_bus.exportItem(db.address, db_slot, chunk, ME_EXPORT)
        end)
        if ok then exported = exported + chunk else break end
        try_count = try_count + 1
    end
    return true, "OK"
end

return me
