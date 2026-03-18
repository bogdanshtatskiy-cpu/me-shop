-- /lua/me_logic.lua
local component = require("component")
local sides = require("sides")

local me = {}

me.t = nil      
me.me_net = nil 
me.db = nil     

me.config = { 
    chest_side = sides.up,    
    me_side = sides.down,     
    out_chest_side = sides.up 
}

function me.init()
    if component.isAvailable("transposer") then me.t = component.transposer end
    if component.isAvailable("me_interface") then me.me_net = component.me_interface end
    if component.isAvailable("database") then me.db = component.database end

    if not me.t then return false, "Транспоузер не найден!" end
    if not me.me_net then return false, "МЭ Интерфейс не найден!" end
    return true, "МЭ компоненты готовы."
end

function me.updateStock(shop_items)
    if not me.me_net then return end
    local ok, net_items = pcall(me.me_net.getItemsInNetwork)
    if not ok or not net_items then return end

    local lookup = {}
    for _, n_item in ipairs(net_items) do
        -- Пытаемся зацепиться за любое доступное имя
        local key_name = n_item.name or n_item.label or "unknown"
        local key = key_name .. "_" .. (n_item.label or "")
        lookup[key] = (lookup[key] or 0) + n_item.size
    end

    for _, s_item in ipairs(shop_items) do
        local key = s_item.id .. "_" .. (s_item.orig_label or "")
        s_item.stock = lookup[key] or 0
    end
end

function me.sellAll(buyback_list)
    if not me.t then return false, "Транспоузер не подключен!", 0 end

    local inv_size = me.t.getInventorySize(me.config.chest_side)
    if not inv_size or inv_size == 0 then return false, "Сундук не найден!", 0 end

    local total_earned = 0
    local sold_stats = {}
    local err_msg = nil

    for slot = 1, inv_size do
        local stack = me.t.getStackInSlot(me.config.chest_side, slot)
        if stack and stack.size > 0 then
            local matched_item = nil
            for _, b_item in ipairs(buyback_list) do
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
                    sold_stats[matched_item.name] = (sold_stats[matched_item.name] or 0) + actual_moved
                end
            end
        end
    end

    if total_earned > 0 then
        local receipt = ""
        for name, qty in pairs(sold_stats) do receipt = receipt .. name .. "(x" .. qty .. ") " end
        return true, "Сдано: " .. receipt, total_earned
    else
        return false, "Не продано. Причина: " .. tostring(err_msg or "Нет подходящих предметов"), 0
    end
end

function me.peekInput()
    if not me.t then return nil, nil, "Транспоузер не подключен!" end
    local inv_size = me.t.getInventorySize(me.config.chest_side)
    for slot = 1, inv_size do
        local stack = me.t.getStackInSlot(me.config.chest_side, slot)
        if stack and stack.size > 0 then return stack, slot end
    end
    return nil, nil, "Положите предмет в сундук!"
end

function me.storeToDB(chest_slot, db_slot)
    if not me.t or not me.db then return false end
    return me.t.store(me.config.chest_side, chest_slot, me.db.address, db_slot)
end

-- === ФИНАЛЬНАЯ ВЫДАЧА ЧЕРЕЗ БАЗУ ДАННЫХ ===
function me.buyItem(item, qty)
    if not me.me_net or not me.db then return false, "МЭ или БД не подключены!" end
    if not item.db_slot then return false, "Ошибка: Товар не привязан к БД! Передобавьте его в админке." end
    
    -- Берем информацию о предмете напрямую из Улучшения "База Данных"
    local db_data = me.db.get(item.db_slot)
    if type(db_data) ~= "table" or not db_data.name then
        return false, "Слот БД пуст! Передобавьте товар в админке."
    end
    
    -- Собираем идеальную таблицу-слепок (AE2 требует id, БД выдает name)
    local perfect_fingerprint = {
        id = db_data.name,
        damage = db_data.damage or 0
    }
    
    -- Если предмет с NBT (чар, заряд), обязательно передаем это тоже
    if db_data.hasTag then
        perfect_fingerprint.hasTag = true
    end
    
    local result, reason
    local ok, err = pcall(function()
        result, reason = me.me_net.exportItem(perfect_fingerprint, me.config.out_chest_side, qty)
    end)
    
    if not ok then return false, "Сбой МЭ: " .. tostring(err) end
    
    if type(result) == "table" and result.size and result.size > 0 then return true, "Выдано"
    elseif type(result) == "number" and result > 0 then return true, "Выдано"
    elseif result == true then return true, "Выдано"
    else return false, tostring(reason or "Нет места в сундуке или товара в сети!") end
end

return me
