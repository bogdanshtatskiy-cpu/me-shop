-- /home/casino_me_logic.lua
local component = require("component")
local sides = require("sides")
local json = require("casino_json")
local fs = require("filesystem")

local me = {}
me.t = nil      

me.config = { chest_side = sides.up, me_side = sides.down }

local deposit_prices = {}
local DEPOSIT_DB_PATH = "/home/casino_deposit_prices.json"

local function loadDepositPrices()
    local f = io.open(DEPOSIT_DB_PATH, "r")
    if f then
        local data = f:read("*a")
        f:close()
        if data and data ~= "" then
            local ok, decoded = pcall(json.decode, data)
            if ok and type(decoded) == "table" then
                deposit_prices = decoded
            end
        end
    end
end

function me.saveDepositPrices(new_prices)
    if type(new_prices) ~= "table" then return false, "Неверный формат данных" end
    deposit_prices = new_prices
    local f = io.open(DEPOSIT_DB_PATH, "w")
    if f then
        f:write(json.encode(deposit_prices))
        f:close()
        return true
    else
        return false, "Не удалось записать файл цен"
    end
end

function me.getDepositPrices()
    return deposit_prices
end

function me.init()
    if component.isAvailable("transposer") then me.t = component.transposer end
    if not me.t then return false, "Транспоузер не найден!" end
    if not component.isAvailable("me_interface") then return false, "МЭ Интерфейс не найден!" end
    
    loadDepositPrices()
    return true, "МЭ компоненты готовы."
end

function me.sellAllToBalance()
    if not me.t then return false, "Транспоузер не подключен!", 0 end
    local inv_size = me.t.getInventorySize(me.config.chest_side)
    if not inv_size or inv_size == 0 then return false, "Сундук для пополнения не найден!", 0 end

    local total_earned = 0; local sold_stats = {}; local err_msg = nil

    for slot = 1, inv_size do
        local stack = me.t.getStackInSlot(me.config.chest_side, slot)
        if stack and stack.size > 0 then
            local item_key = stack.name .. (stack.damage > 0 and (":"..stack.damage) or "")
            local dep_info = deposit_prices[item_key]

            if dep_info then
                local price = type(dep_info) == "table" and dep_info.price or dep_info
                if tonumber(price) then
                    local moved, reason = me.t.transferItem(me.config.chest_side, me.config.me_side, stack.size, slot)
                    local actual_moved = 0
                    if type(moved) == "number" then actual_moved = moved
                    elseif type(moved) == "boolean" and moved == true then actual_moved = stack.size
                    elseif type(moved) == "boolean" and moved == false then err_msg = reason end

                    if actual_moved > 0 then
                        total_earned = total_earned + (actual_moved * tonumber(price))
                        local display_name = type(dep_info) == "table" and dep_info.name or (stack.label or stack.name)
                        sold_stats[display_name] = (sold_stats[display_name] or 0) + actual_moved
                    end
                end
            end
        end
    end

    if total_earned > 0 then
        local receipt = ""
        for name, qty in pairs(sold_stats) do receipt = receipt .. name .. "(x" .. qty .. ") " end
        return true, "Сдано: " .. receipt, total_earned
    else return false, "Не продано. Причина: " .. tostring(err_msg or "Нет подходящих предметов или не заданы цены"), 0 end
end

function me.peekInput()
    if not me.t then return nil, "Транспоузер не подключен!" end
    local inv_size = me.t.getInventorySize(me.config.chest_side)
    for slot = 1, inv_size do
        local stack = me.t.getStackInSlot(me.config.chest_side, slot)
        if stack and stack.size > 0 then return stack end
    end
    return nil, "Положите предмет в сундук!"
end

-- =========================================================
-- БЕЗОПАСНАЯ ВЫДАЧА (СТРОГО УЧИТЫВАЕТ DAMAGE/ТИРЫ)
-- =========================================================
function me.givePrize(item_id, item_damage, qty)
    if not item_id or item_id == "" then
        return false, "У предмета не указан Системный ID в настройках кейса!", 0
    end

    local item_damage_num = math.floor(item_damage or 0)
    local total_moved = 0
    local last_err = "Сундук выдачи не найден или предмета нет в МЭ!"
    local no_chest_found = true

    local directions = {"DOWN", "UP", "NORTH", "SOUTH", "WEST", "EAST"}

    for addr in component.list("me_interface") do
        local me_proxy = component.proxy(addr)
        
        -- Базовый чистый отпечаток (с ЖЕСТКОЙ привязкой к Damage)
        local fingerprints_to_try = {
            { id = item_id, name = item_id, damage = item_damage_num, dmg = item_damage_num }
        }
        
        -- УМНЫЙ ПОИСК В МЭ: Ищем этот же ID, фильтруем по Damage и берем их NBT-теги
        local ok_search, items = pcall(me_proxy.getItemsInNetwork, { name = item_id })
        if not ok_search or not items or #items == 0 then
            ok_search, items = pcall(me_proxy.getItemsInNetwork, { id = item_id })
        end
        
        if ok_search and type(items) == "table" then
            for _, item in pairs(items) do
                -- СТРОГАЯ ПРОВЕРКА: Совпадает и ID, и Damage (урон/тир панели)
                if type(item) == "table" and (item.name == item_id or item.id == item_id) and math.floor(item.damage or item.dmg or 0) == item_damage_num then
                    -- Копируем этот предмет, чтобы сохранить его NBT
                    local fp = {}
                    for k, v in pairs(item) do fp[k] = v end
                    fp.id = fp.id or fp.name or item_id
                    fp.damage = item_damage_num
                    table.insert(fingerprints_to_try, fp)
                end
            end
        end

        local success_dir = nil
        local success_fp = nil

        for _, dir in ipairs(directions) do
            -- Перебираем наши отпечатки (все они строго с нужным Damage!)
            for _, fp in ipairs(fingerprints_to_try) do
                local ok, result = pcall(me_proxy.exportItem, fp, dir, qty)
                local moved_now = 0
                
                if ok and type(result) == "table" and result.size then moved_now = result.size
                elseif ok and type(result) == "number" then moved_now = result end
                
                if moved_now > 0 then
                    total_moved = total_moved + moved_now
                    success_dir = dir
                    success_fp = fp
                    no_chest_found = false
                    break
                elseif not ok then
                    local err_str = tostring(result)
                    if err_str:match("No neighbour attached") then
                        -- Просто пустая сторона, идем дальше
                    else
                        last_err = err_str
                        no_chest_found = false
                    end
                end
            end
            
            -- Если выдача началась, добиваем остаток (если стак большой)
            if total_moved > 0 and total_moved < qty then
                local attempts = 0
                while total_moved < qty and attempts < 150 do
                    local batch = qty - total_moved
                    local ok2, res2 = pcall(me_proxy.exportItem, success_fp, success_dir, batch)
                    local m2 = 0
                    if ok2 and type(res2) == "table" and res2.size then m2 = res2.size
                    elseif ok2 and type(res2) == "number" then m2 = res2 end
                    
                    if m2 > 0 then total_moved = total_moved + m2 else break end
                    attempts = attempts + 1
                end
                break -- Выходим из цикла сторон
            end
            
            if total_moved >= qty then break end
        end
        if total_moved > 0 then break end
    end
    
    if total_moved > 0 then 
        return true, "Успешно", total_moved
    else 
        if no_chest_found then
            last_err = "К МЭ Интерфейсу вплотную не приставлен сундук!"
        end
        return false, "Ошибка: " .. last_err, 0 
    end
end

return me
