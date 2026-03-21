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
-- УМНАЯ ВЫДАЧА ПРИЗОВ И ДЕБАГГЕР
-- =========================================================
function me.givePrize(item_id, item_damage, qty)
    if not item_id or item_id == "" then
        return false, "У предмета не указан Системный ID!", 0
    end

    local item_damage_num = math.floor(item_damage or 0)
    local total_moved = 0
    
    local debug_log = "--- ДЕБАГ ВЫДАЧИ: " .. item_id .. ":" .. item_damage_num .. " (Кол-во: " .. qty .. ") ---\n"
    local last_real_error = "Сундук не найден или предмет отсутствует в МЭ."

    for addr in component.list("me_interface") do
        local me_proxy = component.proxy(addr)
        debug_log = debug_log .. "-> Проверка МЭ Интерфейса: " .. addr:sub(1,8) .. "\n"

        -- 1. ИЩЕМ ПРЕДМЕТ В СЕТИ (чтобы скопировать NBT-теги энергии)
        local found_items = nil
        local ok_s, res_s = pcall(me_proxy.getItemsInNetwork, { name = item_id, damage = item_damage_num })
        if not ok_s or type(res_s) ~= "table" or #res_s == 0 then
            ok_s, res_s = pcall(me_proxy.getItemsInNetwork, { id = item_id, damage = item_damage_num })
        end

        if ok_s and type(res_s) == "table" and #res_s > 0 then
            found_items = res_s
            local total_in_me = 0
            for _, it in ipairs(res_s) do total_in_me = total_in_me + (it.size or 0) end
            debug_log = debug_log .. "[V] В МЭ сети найдено: " .. total_in_me .. " шт. (Вариантов NBT: " .. #res_s .. ")\n"
        else
            debug_log = debug_log .. "[X] Предмет не найден в МЭ сети по этому ID и Урону!\n"
            last_real_error = "В МЭ сети нет предмета с ID: " .. item_id .. ":" .. item_damage_num
        end

        -- 2. ПОДГОТОВКА ОТПЕЧАТКОВ (Сначала чистый, потом с NBT)
        local fp_clean = { id = item_id, name = item_id, damage = item_damage_num, dmg = item_damage_num }
        local fingerprints_to_try = { fp_clean }

        if found_items then
            for i = 1, math.min(3, #found_items) do -- Берем до 3 вариантов предмета с разной энергией
                local fp_full = found_items[i]
                fp_full.id = fp_full.id or fp_full.name or item_id
                fp_full.damage = fp_full.damage or fp_full.dmg or item_damage_num
                table.insert(fingerprints_to_try, fp_full)
            end
        end

        -- 3. ПОПЫТКА ВЫДАЧИ
        local success_side = -1
        for side = 0, 5 do
            for fp_idx, fp in ipairs(fingerprints_to_try) do
                local ok, result = pcall(me_proxy.exportItem, fp, side, qty)
                local moved_now = 0
                
                if ok and type(result) == "table" and result.size then moved_now = result.size
                elseif ok and type(result) == "number" then moved_now = result end
                
                if moved_now > 0 then
                    debug_log = debug_log .. "[V] УСПЕХ: Сторона " .. side .. ", Отпечаток #" .. fp_idx .. ", Выдано: " .. moved_now .. "\n"
                    total_moved = total_moved + moved_now
                    success_side = side
                    break -- Выходим из перебора отпечатков, мы нашли нужный!
                elseif not ok then
                    local err_str = tostring(result)
                    -- ИГНОРИРУЕМ ФАНТОМНУЮ ОШИБКУ ПУСТЫХ СТОРОН
                    if not err_str:match("No neighbour attached") then
                        last_real_error = err_str
                        debug_log = debug_log .. "[X] Ошибка (Сторона " .. side .. "): " .. err_str .. "\n"
                    end
                end
            end
            
            -- Если начали выдавать, но нужно довыдать стак
            if total_moved > 0 and total_moved < qty then
                local attempts = 0
                while total_moved < qty and attempts < 20 do
                    local batch = qty - total_moved
                    local ok_b, res_b = pcall(me_proxy.exportItem, fingerprints_to_try[1], success_side, batch)
                    local m2 = 0
                    if ok_b and type(res_b) == "table" and res_b.size then m2 = res_b.size
                    elseif ok_b and type(res_b) == "number" then m2 = res_b end
                    
                    if m2 > 0 then total_moved = total_moved + m2 else break end
                    attempts = attempts + 1
                end
                break -- Выходим из перебора сторон
            end
            
            if total_moved >= qty then break end
        end
        
        if total_moved > 0 then break end
    end
    
    if total_moved > 0 then 
        return true, "Успешно", total_moved
    else 
        -- ЗАПИСЫВАЕМ ПОДРОБНЫЙ ОТЧЕТ В ФАЙЛ
        local f = io.open("/home/casino_debug_prize.txt", "w")
        if f then f:write(debug_log); f:close() end
        
        return false, last_real_error .. " (Детали лога: /home/casino_debug_prize.txt)", 0 
    end
end

return me
