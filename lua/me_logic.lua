-- /lua/me_logic.lua
local component = require("component")
local sides = require("sides")

local me = {}
me.t = nil      
me.db = nil     

me.config = { 
    chest_side = sides.up,    
    me_side = sides.down      
}

function me.init()
    if component.isAvailable("transposer") then me.t = component.transposer end
    if component.isAvailable("database") then me.db = component.database end

    if not me.t then return false, "Транспоузер не найден!" end
    if not component.isAvailable("me_interface") then return false, "МЭ Интерфейс не найден!" end
    return true, "МЭ компоненты готовы."
end

-- === ИСПРАВЛЕННЫЙ ПОДСЧЕТ ТОВАРОВ В МЭ (Учет метадаты) ===
function me.updateStock(shop_items)
    local lookup = {}
    for addr in component.list("me_interface") do
        local me_proxy = component.proxy(addr)
        local ok, net_items = pcall(me_proxy.getItemsInNetwork)
        if ok and net_items then
            for _, n_item in ipairs(net_items) do
                -- Создаем уникальный ключ: "minecraft:planks:2"
                local dmg = math.floor(n_item.damage or 0)
                local key = (n_item.name or "unknown") .. ":" .. dmg
                lookup[key] = (lookup[key] or 0) + n_item.size
            end
            break 
        end
    end

    for _, s_item in ipairs(shop_items) do
        -- Ищем по такому же ключу в магазине
        local dmg = math.floor(s_item.damage or 0)
        local key = (s_item.id or "unknown") .. ":" .. dmg
        s_item.stock = lookup[key] or 0
    end
end

-- === ИСПРАВЛЕННАЯ СКУПКА (Жесткая проверка ID + Damage) ===
function me.sellAll(buyback_list)
    if not me.t then return false, "Транспоузер не подключен!", 0 end

    local inv_size = me.t.getInventorySize(me.config.chest_side)
    if not inv_size or inv_size == 0 then return false, "Сундук не найден!", 0 end

    local total_earned = 0; local sold_stats = {}; local err_msg = nil

    for slot = 1, inv_size do
        local stack = me.t.getStackInSlot(me.config.chest_side, slot)
        if stack and stack.size > 0 then
            local matched_item = nil
            for _, b_item in ipairs(buyback_list) do
                -- Сверяем и текстовый ID, и УРОН (damage)
                local stack_dmg = math.floor(stack.damage or 0)
                local b_dmg = math.floor(b_item.damage or 0)
                
                if stack.name == b_item.id and stack_dmg == b_dmg then
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

function me.buyItem(item, qty)
    if not me.db then return false, "БД не подключена!" end
    if not item.db_slot then return false, "Товар не привязан к БД! Передобавьте его." end
    
    local db_data = me.db.get(item.db_slot)
    if type(db_data) ~= "table" or not db_data.name then return false, "Слот БД пуст! Передобавьте товар." end
    
    local perfect_fingerprint = { id = db_data.name, damage = db_data.damage or 0 }
    if db_data.hasTag then perfect_fingerprint.hasTag = true end
    
    local success = false
    local last_err = "Сундук не найден ни с одной стороны!"

    for addr in component.list("me_interface") do
        local me_proxy = component.proxy(addr)
        for side = 0, 5 do
            local ok, result, reason = pcall(function()
                return me_proxy.exportItem(perfect_fingerprint, side, qty)
            end)
            
            if ok and (result == true or (type(result) == "table" and result.size and result.size > 0) or (type(result) == "number" and result > 0)) then
                success = true
                break
            elseif not ok then
                last_err = tostring(result) 
            end
        end
        if success then break end
    end
    
    if success then return true, "Выдано"
    else return false, "Ошибка: " .. last_err end
end

return me
