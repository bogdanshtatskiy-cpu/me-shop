-- /obmen/me_logic.lua
local component = require("component")
local sides = require("sides")

local me = {}
local transposer, inv_ctrl, db, me_bus
local a_out

local T_INPUT  = 1 -- ВВЕРХ
local T_DUMP   = 0 -- ВНИЗ
local ME_EXPORT = 1 -- ВВЕРХ

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
    
    for s = 0, 5 do
        local ok, sz = pcall(inv_ctrl.getInventorySize, s)
        if ok and sz and sz >= 27 then a_out = s; break end
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

-- НОВАЯ ЛОГИКА: ЧИТАЕМ СЛОТ ЗА СЛОТОМ И СРАЗУ ВЫДАЕМ
function me.processOneExchange(trades)
    local size = transposer.getInventorySize(T_INPUT)
    if not size then return false end
    
    for slot = 1, size do
        local item = transposer.getStackInSlot(T_INPUT, slot)
        if item and item.name then
            for _, t in ipairs(trades) do
                if item.name == t.input.name and math.floor(item.damage or 0) == math.floor(t.input.damage or 0) then
                    
                    local max_out_from_me = math.floor(t.stock / t.ratio)
                    local free_space = me.getFreeSpace(t.output.name, t.output.damage)
                    local max_out_space = math.floor(free_space / t.ratio)
                    local can_process = math.min(item.size, max_out_from_me, max_out_space)
                    
                    if can_process > 0 then
                        local out_qty = can_process * t.ratio
                        local ok, msg, actual_out = me.executeExchange(slot, can_process, t, out_qty)
                        return true, ok, msg, actual_out, t, can_process
                    end
                end
            end
        end
    end
    return false -- Ничего не нашли/не обработали
end

function me.executeExchange(slot, input_qty, t_data, output_qty)
    local pushed = transposer.transferItem(T_INPUT, T_DUMP, input_qty, slot)
    
    if type(pushed) == "boolean" and not pushed then return false, "МЭ приема занята", 0
    elseif type(pushed) == "number" and pushed < input_qty then return false, "МЭ не приняло всю руду", 0
    elseif not pushed then return false, "Сбой транспоузера приема", 0 end
    
    -- БЕРЕМ ИДЕАЛЬНЫЙ СЛЕПОК ИЗ БАЗЫ ДАННЫХ
    local fp = db.get(t_data.db_slot)
    if not fp then return true, "Пустой слепок в БД! Пересоздайте обмен.", 0 end
    
    local exported = 0
    local try_count = 0
    local last_err = ""
    
    while exported < output_qty and try_count < 5 do
        local chunk = math.min(output_qty - exported, 64)
        
        -- Скармливаем МЭ интерфейсу идеальный слепок (fp)
        local ok, res = pcall(me_bus.exportItem, fp, ME_EXPORT, chunk)
        
        if ok then
            if type(res) == "table" and res.size then exported = exported + res.size
            elseif type(res) == "number" then exported = exported + res
            elseif res == true then exported = exported + chunk
            else last_err = tostring(res) end
        else
            last_err = tostring(res)
            break
        end
        try_count = try_count + 1
    end
    
    if exported < output_qty then
        return true, last_err, exported
    end
    
    return true, "OK", exported
end

return me
