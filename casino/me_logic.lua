-- /home/casino_me_logic.lua
local component = require("component")
local sides = require("sides")
local json = require("casino_json")

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
-- ФИНАЛЬНЫЙ АБСОЛЮТ: ЛОГИКА МАГАЗИНА + ЖИВОЙ КЛОН NBT
-- =========================================================
function me.givePrize(item_id, item_damage, qty)
    if not item_id or item_id == "" then
        return false, "У предмета не указан Системный ID!", 0
    end

    item_id = item_id:match("^%s*(.-)%s*$") -- Чистим пробелы
    local dmg_num = math.floor(item_damage or 0)
    local total_moved = 0
    local real_err = "Сундук выдачи не найден ни над одним интерфейсом!"

    for addr in component.list("me_interface") do
        local me_proxy = component.proxy(addr)
        
        -- ШАГ 1: Создаем массив вариантов для выдачи
        local fingerprints = {}
        
        -- Вариант А: Точно как в твоем магазине (для панелей, блоков, руды)
        table.insert(fingerprints, { id = item_id, dmg = dmg_num })
        
        -- Вариант Б: "Живой клон". Запрашиваем предмет у МЭ сети и воруем его NBT-хэш
        local ok_net, net_items = pcall(me_proxy.getItemsInNetwork, { name = item_id })
        if not ok_net or type(net_items) ~= "table" or #net_items == 0 then
            ok_net, net_items = pcall(me_proxy.getItemsInNetwork, { id = item_id })
        end
        
        if ok_net and type(net_items) == "table" then
            for _, n_item in pairs(net_items) do
                if type(n_item) == "table" then
                    local n_name = n_item.name or n_item.id or ""
                    -- Если нашли наш Драконик, копируем его живой слепок
                    if n_name == item_id then
                        local live_fp = {}
                        for k, v in pairs(n_item) do live_fp[k] = v end
                        live_fp.id = n_name
                        live_fp.dmg = dmg_num -- Принудительно ставим нужный урон
                        table.insert(fingerprints, live_fp)
                    end
                end
            end
        end

        local sides_to_try = {0, 1, 2, 3, 4, 5, "DOWN", "UP", "NORTH", "SOUTH", "WEST", "EAST"}
        
        -- ШАГ 2: Пытаемся выдать
        for _, fp in ipairs(fingerprints) do
            for _, side in ipairs(sides_to_try) do
                local ok, result = pcall(me_proxy.exportItem, fp, side, qty - total_moved)
                local moved_now = 0
                
                if ok and type(result) == "table" and result.size then moved_now = result.size
                elseif ok and type(result) == "number" then moved_now = result end
                
                if moved_now > 0 then
                    total_moved = total_moved + moved_now
                    
                    -- Насос для остатка
                    local attempts = 0
                    while total_moved < qty and attempts < 150 do
                        local batch = qty - total_moved
                        local ok2, res2 = pcall(me_proxy.exportItem, fp, side, batch)
                        local m2 = 0
                        
                        if ok2 and type(res2) == "table" and res2.size then m2 = res2.size
                        elseif ok2 and type(res2) == "number" then m2 = res2 end
                        
                        if m2 > 0 then total_moved = total_moved + m2 else break end
                        attempts = attempts + 1
                    end
                    
                    return true, "Успешно", total_moved
                elseif not ok then
                    local err_str = tostring(result)
                    -- Сохраняем ТОЛЬКО настоящую ошибку
                    if not err_str:match("No neighbour attached") and not err_str:match("not valid enum") then
                        real_err = err_str
                    end
                end
            end
            if total_moved >= qty then break end
        end
        if total_moved >= qty then break end
    end
    
    if total_moved > 0 then 
        return true, "Частично", total_moved
    else 
        return false, "Ошибка мода: " .. real_err, 0 
    end
end

return me
