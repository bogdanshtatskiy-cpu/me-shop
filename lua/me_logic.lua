-- /lua/me_logic.lua
local component = require("component")
local sides = require("sides")

local me = {}

me.t = nil      -- Транспоузер (для скупки)
me.me_net = nil -- МЭ Интерфейс (для выдачи)
me.db = nil     -- База данных

-- Настройки сторон для Транспоузера (Скупка)
me.config = {
    chest_side = sides.up,   -- Сундук стоит СВЕРХУ от транспоузера
    me_side = sides.down     -- МЭ Интерфейс стоит СНИЗУ от транспоузера
}

function me.init()
    if component.isAvailable("transposer") then
        me.t = component.transposer
    end
    
    if component.isAvailable("me_interface") then
        me.me_net = component.me_interface
    end
    
    if component.isAvailable("database") then
        me.db = component.database
    end

    if not me.t then
        return false, "ВНИМАНИЕ: Транспоузер не найден! Скупка не будет работать."
    end

    return true, "МЭ компоненты успешно инициализированы."
end

-- ФУНКЦИЯ СКУПКИ (ПРОДАТЬ ВСЁ)
function me.sellAll(buyback_list)
    if not me.t then return false, "Транспоузер не подключен!", 0 end

    -- Проверяем, есть ли сундук сверху
    local inv_size = me.t.getInventorySize(me.config.chest_side)
    if not inv_size or inv_size == 0 then
        return false, "Сундук для скупки не найден (должен быть сверху Транспоузера)!", 0
    end

    local total_earned = 0
    local items_sold = 0

    -- Сканируем сундук
    for slot = 1, inv_size do
        local stack = me.t.getStackInSlot(me.config.chest_side, slot)
        if stack and stack.size > 0 then
            
            -- Ищем предмет в списке скупки
            local matched_item = nil
            for _, b_item in ipairs(buyback_list) do
                -- Сравниваем по системному имени (например, IC2:itemUran) или по видимому (Uranium)
                if stack.label == b_item.name or stack.name == b_item.name then
                    matched_item = b_item
                    break
                end
            end

            -- Если предмет подходит, перекидываем его вниз (в МЭ сеть)
            if matched_item then
                -- transferItem(откуда, куда, сколько, из_какого_слота)
                local moved = me.t.transferItem(me.config.chest_side, me.config.me_side, stack.size, slot)
                if moved > 0 then
                    total_earned = total_earned + (moved * matched_item.price)
                    items_sold = items_sold + moved
                end
            end
        end
    end

    if total_earned > 0 then
        return true, "Успешно сдано: " .. items_sold .. " шт.", total_earned
    else
        return false, "В сундуке нет подходящих для скупки товаров.", 0
    end
end

-- ЗАГЛУШКА ДЛЯ ВЫДАЧИ ТОВАРОВ (Покупка)
-- В будущем здесь будет логика exportItem через Адаптер и Базу Данных
function me.buyItem(item_db_id, qty)
    if not me.me_net or not me.db then
        return false, "МЭ Интерфейс или База Данных не подключены!"
    end
    -- Логика выдачи будет написана после калибровки базы данных админом
    return true, "Предмет выдан (симуляция)"
end

return me
