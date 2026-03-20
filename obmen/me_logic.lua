-- /obmen/me_logic.lua
local component = require("component")
local sides = require("sides")

local me = {}
local transposer, inv_ctrl, db, me_bus
local t_in, t_dump, a_out

function me.init()
    if not component.isAvailable("transposer") then return false, "Транспоузер не подключен кабелем!" end
    transposer = component.transposer
    
    if not component.isAvailable("inventory_controller") then return false, "Адаптер (Контроллер инв.) не подключен!" end
    inv_ctrl = component.inventory_controller
    
    if not component.isAvailable("database") then return false, "Адаптер (База Данных) не подключен!" end
    db = component.database
    
    if component.isAvailable("me_interface") then me_bus = component.me_interface
    elseif component.isAvailable("me_controller") then me_bus = component.me_controller
    else return false, "МЭ Интерфейс не подключен кабелем!" end
    
    -- Ищем сундуки Транспоузера
    for s=0,5 do
        local sz = transposer.getInventorySize(s)
        if sz then
            if sz > 9 then t_in = s else t_dump = s end
        end
    end
    
    -- Ищем сундук у Адаптера 1
    for s=0,5 do
        local sz = inv_ctrl.getInventorySize(s)
        if sz and sz > 9 then a_out = s; break end
    end

    if not t_in then return false, "Транспоузер не видит входной сундук!" end
    if not t_dump then return false, "Транспоузер не видит МЭ для сброса!" end
    if not a_out then return false, "Адаптер не видит выходной сундук!" end
    
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
    local pushed = transposer.transferItem(t_in, t_dump, input_qty, slot)
    if pushed < input_qty then return false, "Ошибка сброса руды" end
    
    local exported = 0
    local try_count = 0
    while exported < output_qty and try_count < 5 do
        local chunk = math.min(output_qty - exported, 64)
        local ok, err = pcall(function()
            -- Жестко кидаем вверх из МЭ в сундук
            me_bus.exportItem(db.address, db_slot, chunk, sides.up)
        end)
        if ok then exported = exported + chunk else break end
        try_count = try_count + 1
    end
    return true, "OK"
end

return me
