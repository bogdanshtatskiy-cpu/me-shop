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

function me.givePrize(item_id, item_damage, qty)
    if not item_id or item_id == "" then
        return false, "У предмета не указан Системный ID!", 0
    end

    local item_damage_num = math.floor(item_damage or 0)
    
    -- Ищем Сундук выдачи на свободных сторонах Транспоузера
    local prize_chest_side = nil
    if me.t then
        for s = 0, 5 do
            if s ~= me.config.chest_side and s ~= me.config.me_side then
                local ok, size = pcall(me.t.getInventorySize, s)
                if ok and size and size > 0 then
                    prize_chest_side = s
                    break
                end
            end
        end
    end

    -- 1. БАЗА ДАННЫХ + ТРАНСПОУЗЕР (Обход бага NBT)
    local db = component.isAvailable("database") and component.database or nil
    local target_db_slot = nil
    
    if db then
        for i = 1, 81 do
            local ok, db_item = pcall(db.get, i)
            if ok and db_item then
                local db_name = db_item.name or db_item.id or ""
                if string.lower(db_name) == string.lower(item_id) then
                    target_db_slot = i
                    break
                end
            end
        end
    end

    if target_db_slot and prize_chest_side and me.t then
        for addr in component.list("me_interface") do
            local me_proxy = component.proxy(addr)
            
            pcall(me_proxy.setInterfaceConfiguration, 1, db.address, target_db_slot, qty)
            os.sleep(0.5)
            
            local moved = 0
            local ok_size, int_size = pcall(me.t.getInventorySize, me.config.me_side)
            if ok_size and int_size then
                for slot = 1, int_size do
                    local stack = me.t.getStackInSlot(me.config.me_side, slot)
                    if stack then
                        local st_name = stack.name or stack.id or ""
                        if string.lower(st_name) == string.lower(item_id) then
                            local m = me.t.transferItem(me.config.me_side, prize_chest_side, qty - moved, slot)
                            if type(m) == "number" then moved = moved + m
                            elseif type(m) == "boolean" and m then moved = moved + stack.size end
                            if moved >= qty then break end
                        end
                    end
                end
            end
            
            pcall(me_proxy.setInterfaceConfiguration, 1)
            
            if moved > 0 then
                return true, "Успешно выдано!", moved
            end
        end
    end

    -- 2. РЕЗЕРВНЫЙ МЕТОД (exportItem)
    local total_moved = 0
    local last_err = "Предмета нет в МЭ или Сундук выдачи не найден."
    local no_chest_found = true
    local directions = {"DOWN", "UP", "NORTH", "SOUTH", "WEST", "EAST"}
    
    -- ИСПРАВЛЕНО: Во всех таблицах теперь жестко есть поле id
    local fingerprints_to_try = {
        { id = item_id, name = item_id, damage = item_damage_num },
        { id = item_id, name = item_id, damage = 32767 },
        { id = item_id, name = item_id }
    }

    for addr in component.list("me_interface") do
        local me_proxy = component.proxy(addr)
        local success_dir = nil
        local success_fp = nil

        for _, dir in ipairs(directions) do
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
                    if not err_str:match("No neighbour attached") then
                        last_err = err_str
                        no_chest_found = false
                    end
                end
            end
            
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
                break
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
