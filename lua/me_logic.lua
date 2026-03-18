-- /lua/me_logic.lua
local component = require("component")
local sides = require("sides")

local me = {}

me.db = nil
me.transposers = {}

-- Стороны сундуков и интерфейсов (настроим позже через админку)
me.config = {
    buyback_transposer = nil,
    buyback_chest_side = sides.top,
    buyback_me_side = sides.bottom
}

-- Инициализация компонентов
function me.init()
    if component.isAvailable("database") then
        me.db = component.database
    else
        return false, "Нет Улучшения 'База данных'!"
    end

    -- Собираем все транспоузеры
    for address in component.list("transposer") do
        table.insert(me.transposers, component.proxy(address))
    end

    if #me.transposers < 2 then
        return false, "Нужно минимум 2 Транспоузера (на ввод и на вывод)!"
    end

    -- Для старта считаем первый транспоузер скупщиком
    me.config.buyback_transposer = me.transposers[1]

    return true, "МЭ компоненты подключены!"
end

-- Функция скупки (Продать всё)
function me.sellAll(buyback_list)
    local t = me.config.buyback_transposer
    local chest_side = me.config.buyback_chest_side
    local me_side = me.config.buyback_me_side
    
    local total_earned = 0
    local sold_details = ""
    local items_sold_count = 0

    -- Проверяем размер сундука
    local inv_size = t.getInventorySize(chest_side)
    if not inv_size or inv_size == 0 then
        return false, "Сундук скупки не найден!", 0
    end

    -- Сканируем каждый слот сундука
    for slot = 1, inv_size do
        local stack = t.getStackInSlot(chest_side, slot)
        if stack and stack.size > 0 then
            
            -- Проверяем, есть ли этот предмет в списке скупки
            local matched_item = nil
            for _, b_item in ipairs(buyback_list) do
                if stack.label == b_item.name or stack.name == b_item.name then
                    matched_item = b_item
                    break
                end
            end

            -- Если предмет принимается магазином, перекидываем его в МЭ Интерфейс
            if matched_item then
                local amount = stack.size
                local moved = t.transferItem(chest_side, me_side, amount, slot)
                
                if moved > 0 then
                    local earned = moved * matched_item.price
                    total_earned = total_earned + earned
                    items_sold_count = items_sold_count + moved
                end
            end
        end
    end

    if total_earned > 0 then
        return true, "Сдано: " .. items_sold_count .. " шт.", total_earned
    else
        return false, "В сундуке нет подходящих для скупки товаров.", 0
    end
end

return me
