-- /obmen/me_logic.lua
local component = require("component")
local sides = require("sides")

local me = {}
local transposer, inv_ctrl, db, me_bus
local a_out

-- ЖЕСТКИЕ НАСТРОЙКИ СТОРОН
local T_INPUT  = 1 -- ВВЕРХ (Сундук над транспоузером)
local T_DUMP   = 0 -- ВНИЗ (МЭ Интерфейс под транспоузером)
local ME_EXPORT = 1 -- ВВЕРХ (МЭ выдает слитки вверх в сундук)

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

function me.getInputInventory()
    local inv = {}
    local size = transposer.getInventorySize(T_INPUT)
    if not size then return inv end
    
    -- СУПЕР-БЫСТРОЕ СКАНИРОВАНИЕ (Убираем лаг в 5-10 секунд)
    local ok, stacks = pcall(transposer.getAllStacks, T_INPUT)
    if ok and stacks then
        if type(stacks) == "table" and stacks.getAll then
            local arr = stacks.getAll()
            for i, stack in pairs(arr) do
                if stack and stack.name then inv[i] = stack end
            end
            return inv
        elseif type(stacks) == "function" then
            local i = 1
            for stack in stacks do
                if stack and stack.name then inv[i] = stack end
                i = i + 1
            end
            return inv
        end
    end
    
    -- Если супер-метод отключен на сервере, сканируем по старинке (медленно)
    for i = 1, size do
        local stack = transposer.getStackInSlot(T_INPUT, i)
        if stack and stack.name then inv[i] = stack end
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

function me.processExchange(slot, input_qty, t_data, output_qty)
    local pushed = transposer.transferItem(T_INPUT, T_DUMP, input_qty, slot)
    
    if type(pushed) == "boolean" and not pushed then return false, "МЭ занята", 0
    elseif type(pushed) == "number" and pushed < input_qty then return false, "МЭ не приняло руду", 0
    elseif not pushed then return false, "Сбой транспоузера", 0 end
    
    local exported = 0
    local try_count = 0
    local last_err = ""
    
    while exported < output_qty and try_count < 5 do
        local chunk = math.min(output_qty - exported, 64)
        
        -- ПОПЫТКА 1: Выдача по ID (Стандарт)
        local ok, res = pcall(me_bus.exportItem, {name = t_data.output.name, damage = t_data.output.damage}, ME_EXPORT, chunk)
        
        -- ПОПЫТКА 2: Выдача по Базе Данных (Резерв)
        if not ok then
            ok, res = pcall(me_bus.exportItem, db.address, t_data.db_slot, chunk, ME_EXPORT)
        end
        
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
        return true, "МЭ выдало ошибку: " .. last_err, exported
    end
    
    return true, "OK", exported
end

return me
