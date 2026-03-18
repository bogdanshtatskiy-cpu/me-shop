-- /lua/me_logic.lua
local component = require("component")
local sides = require("sides")

local me = {}

me.t = nil      
me.me_net = nil 
me.db = nil     

me.config = { chest_side = sides.up, me_side = sides.down }

function me.init()
    if component.isAvailable("transposer") then me.t = component.transposer end
    if component.isAvailable("me_interface") then me.me_net = component.me_interface end
    if component.isAvailable("database") then me.db = component.database end

    if not me.t then return false, "Транспоузер не найден!" end
    return true, "МЭ компоненты готовы."
end

-- Обновление количества товаров из МЭ сети
function me.updateStock(shop_items)
    if not me.me_net then return end
    local ok, net_items = pcall(me.me_net.getItemsInNetwork)
    if not ok or not net_items then return end

    -- Создаем быстрый справочник того, что есть в МЭ
    local lookup = {}
    for _, n_item in ipairs(net_items) do
        local key = n_item.name .. "_" .. (n_item.label or "")
        lookup[key] = (lookup[key] or 0) + n_item.size
    end

    -- Обновляем счетчики в магазине
    for _, s_item in ipairs(shop_items) do
        local key = s_item.id .. "_" .. (s_item.orig_label or "")
        s_item.stock = lookup[key] or 0
    end
end

-- Скупка товаров
function me.sellAll(buyback_list)
    if not me.t then return false, "Транспоузер не подключен!", 0 end
    local inv_size = me.t.getInventorySize(me.config.chest_side)
    if not inv_size or inv_size == 0 then return false, "Сундук не найден!", 0 end

    local total_earned = 0; local items_sold = 0; local err_msg = nil

    for slot = 1, inv_size do
        local stack = me.t.getStackInSlot(me.config.chest_side, slot)
        if stack and stack.size > 0 then
            local matched_item = nil
            for _, b_item in ipairs(buyback_list) do
                -- ТЕПЕРЬ СВЕРЯЕМ ПО ОРИГИНАЛЬНОМУ ID ИЛИ LABEL!
                if stack.name == b_item.id or stack.label == b_item.orig_label then
                    matched_item = b_item; break
                end
            end
            if matched_item then
                local moved, reason = me.t.transferItem(me.config.chest_side, me.config.me_side, stack.size, slot)
                local actual_moved = 0
                if type(moved) == "number" then actual_moved = moved
                elseif type(moved) == "boolean" and moved == true then actual_moved = stack.size
                elseif type(moved) == "boolean" and moved == false then err_msg = reason end

                if actual_moved > 0 then
                    total_earned = total_earned + (actual_moved * matched_item.price)
                    items_sold = items_sold + actual_moved
                end
            end
        end
    end
    if total_earned > 0 then return true, "Сдано: " .. items_sold .. " шт.", total_earned
    else return false, "Не продано. Причина: " .. tostring(err_msg or "Нет подходящих предметов"), 0 end
end

function me.peekInput()
    if not me.t then return nil, nil, "Транспоузер не подключен!" end
    local inv_size = me.t.getInventorySize(me.config.chest_side)
    if not inv_size or inv_size == 0 then return nil, nil, "Сундук не найден!" end
    
    for slot = 1, inv_size do
        local stack = me.t.getStackInSlot(me.config.chest_side, slot)
        if stack and stack.size > 0 then return stack, slot end
    end
    return nil, nil, "Положите предмет в сундук!"
end

-- Сохранение слепка предмета в Базу Данных
function me.storeToDB(chest_slot, db_slot)
    if not me.t or not me.db then return false end
    return me.t.store(me.config.chest_side, chest_slot, me.db.address, db_slot)
end

return me
