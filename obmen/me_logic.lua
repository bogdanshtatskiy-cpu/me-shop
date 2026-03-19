-- /obmen/me_logic.lua
local component = require("component")
local sides = require("sides")

local me = {}
local transposer
local me_bus

-- НАСТРОЙКИ СТОРОН ТРАНСПОУЗЕРА (Относительно самого Транспоузера)
local SIDE_INPUT  = sides.west  -- Слева сундук входа
local SIDE_OUTPUT = sides.east  -- Справа сундук выхода
local SIDE_DUMP   = sides.down  -- Снизу МЭ Интерфейс (для сброса руды)

-- НАСТРОЙКА СТОРОНЫ МЭ ИНТЕРФЕЙСА (Где стоит сундук относительно МЭ Интерфейса с Адаптером)
-- Предполагаем, что МЭ интерфейс стоит позади правого сундука, значит сундук спереди (north/south). 
-- Если не работает выдача, поменяй на sides.up или sides.south
local ME_EXPORT_SIDE = sides.north 

function me.init()
    if component.isAvailable("transposer") then transposer = component.transposer else return false, "Транспоузер не найден!" end
    if component.isAvailable("me_interface") then me_bus = component.me_interface
    elseif component.isAvailable("me_controller") then me_bus = component.me_controller
    else return false, "МЭ Интерфейс с Адаптером не найден!" end
    return true, "OK"
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

function me.getScanItems()
    local in_stack = transposer.getStackInSlot(SIDE_INPUT, 1)
    local out_stack = transposer.getStackInSlot(SIDE_OUTPUT, 1)
    return in_stack, out_stack
end

function me.getInputInventory()
    local inv = {}
    local size = transposer.getInventorySize(SIDE_INPUT)
    if not size then return inv end
    for i = 1, size do
        local stack = transposer.getStackInSlot(SIDE_INPUT, i)
        if stack then inv[i] = stack end
    end
    return inv
end

function me.getFreeSpace(target_name, target_dmg)
    local free = 0
    local size = transposer.getInventorySize(SIDE_OUTPUT)
    if not size then return 0 end
    for i = 1, size do
        local stack = transposer.getStackInSlot(SIDE_OUTPUT, i)
        if not stack then free = free + 64
        elseif stack.name == target_name and math.floor(stack.damage or 0) == math.floor(target_dmg or 0) then
            free = free + (stack.maxSize - stack.size)
        end
    end
    return free
end

function me.processExchange(slot, input_qty, output_item, output_qty)
    -- 1. Скидываем руду в МЭ
    local pushed = transposer.transferItem(SIDE_INPUT, SIDE_DUMP, input_qty, slot)
    if pushed < input_qty then return false, "Не удалось сбросить руду в МЭ" end
    
    -- 2. Выдаем слитки из МЭ в правый сундук
    local db_address = me_bus.address -- В AE2 OC адаптер использует свой адрес как фейковую ДБ
    local exported = 0
    local try_count = 0
    while exported < output_qty and try_count < 5 do
        local chunk = math.min(output_qty - exported, 64)
        -- Экспортируем в сундук. Если ME_EXPORT_SIDE не совпадает с реальностью, предметы не выпадут.
        local ok, err = pcall(function() 
            -- Если у тебя me_interface, функция exportItem требует (fingerprint, dir, maxAmount)
            me_bus.exportItem({name=output_item.name, damage=output_item.damage}, ME_EXPORT_SIDE, chunk)
        end)
        if ok then exported = exported + chunk else break end
        try_count = try_count + 1
    end
    
    return true, "OK"
end

return me
