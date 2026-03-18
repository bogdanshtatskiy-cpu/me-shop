-- /lua/me_logic.lua
local component = require("component")
local sides = require("sides")
local json = require("json")
local os = require("os")

local me = {}
me.t_in = nil      
me.t_out = nil
me.me_net = nil 
me.db = nil     

me.config = { chest_side = sides.up, me_side = sides.down }

function me.init()
    if component.isAvailable("me_interface") then me.me_net = component.me_interface end
    if component.isAvailable("database") then me.db = component.database end

    local f = io.open("/home/calibration.json", "r")
    if f then
        local content = f:read("*a")
        f:close()
        if content and content ~= "" then
            local ok, data = pcall(json.decode, content)
            if ok and type(data) == "table" and data.in_t and data.out_t then
                for addr in component.list("transposer") do
                    if addr == data.in_t then me.t_in = component.proxy(addr) end
                    if addr == data.out_t then me.t_out = component.proxy(addr) end
                end
            end
        end
    end

    if not me.me_net then return false, "МЭ Интерфейс не найден!" end
    if not me.t_in or not me.t_out then return false, "ТРЕБУЕТСЯ КАЛИБРОВКА" end
    return true, "МЭ компоненты готовы."
end

function me.calibrate()
    local t_list = {}
    for addr in component.list("transposer") do table.insert(t_list, component.proxy(addr)) end
    
    if #t_list < 2 then return false, "Сначала поставьте 2 Транспоузера!" end

    local found_in = nil
    for _, t in ipairs(t_list) do
        local inv_size = t.getInventorySize(me.config.chest_side)
        if inv_size and inv_size > 0 then
            for slot = 1, inv_size do
                local stack = t.getStackInSlot(me.config.chest_side, slot)
                if stack and stack.size > 0 then found_in = t; break end
            end
        end
        if found_in then break end
    end

    if not found_in then return false, "Положите предмет в ЛЕВЫЙ сундук!" end

    me.t_in = found_in
    for _, t in ipairs(t_list) do
        if t.address ~= found_in.address then me.t_out = t; break end
    end

    local f = io.open("/home/calibration.json", "w")
    if f then
        f:write(json.encode({ in_t = me.t_in.address, out_t = me.t_out.address }))
        f:close()
    end

    return true, "Успешно откалибровано!"
end

function me.updateStock(shop_items)
    local lookup = {}
    for addr in component.list("me_interface") do
        local ok, net_items = pcall(component.proxy(addr).getItemsInNetwork)
        if ok and net_items then
            for _, n_item in ipairs(net_items) do
                local dmg = math.floor(n_item.damage or 0)
                local key = (n_item.name or "unknown") .. ":" .. dmg
                lookup[key] = (lookup[key] or 0) + n_item.size
            end
            break 
        end
    end

    for _, s_item in ipairs(shop_items) do
        local dmg = math.floor(s_item.damage or 0)
        local key = (s_item.id or "unknown") .. ":" .. dmg
        s_item.stock = lookup[key] or 0
    end
end

function me.sellAll(buyback_list)
    if not me.t_in then return false, "Транспоузер скупки не найден!", 0 end
    local inv_size = me.t_in.getInventorySize(me.config.chest_side)
    if not inv_size or inv_size == 0 then return false, "Сундук не найден!", 0 end

    local total_earned = 0; local sold_stats = {}; local err_msg = nil

    for slot = 1, inv_size do
        local stack = me.t_in.getStackInSlot(me.config.chest_side, slot)
        if stack and stack.size > 0 then
            local matched_item = nil
            for _, b_item in ipairs(buyback_list) do
                if stack.name == b_item.id and math.floor(stack.damage or 0) == math.floor(b_item.damage or 0) then
                    matched_item = b_item; break
                end
            end

            if matched_item then
                local moved, reason = me.t_in.transferItem(me.config.chest_side, me.config.me_side, stack.size, slot)
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
    else return false, "Не продано. Причина: " .. tostring(err_msg or "Нет подходящих предметов"), 0 end
end

function me.peekInput()
    if not me.t_in then return nil, nil, "Транспоузер не подключен!" end
    local inv_size = me.t_in.getInventorySize(me.config.chest_side)
    for slot = 1, inv_size do
        local stack = me.t_in.getStackInSlot(me.config.chest_side, slot)
        if stack and stack.size > 0 then return stack, slot end
    end
    return nil, nil, "Положите предмет в сундук!"
end

function me.storeToDB(chest_slot, db_slot)
    if not me.t_in or not me.db then return false end
    return me.t_in.store(me.config.chest_side, chest_slot, me.db.address, db_slot)
end

function me.buyItem(item, qty)
    if not me.db then return false, "БД не подключена!" end
    if not item.db_slot then return false, "Товар не привязан к БД!" end
    if not me.t_out then return false, "Транспоузер выдачи не найден!" end
    
    -- Очищаем интерфейсы
    for addr in component.list("me_interface") do
        pcall(function() component.proxy(addr).setInterfaceConfiguration(1) end)
    end
    
    -- Настраиваем МЭ Интерфейс
    local configured = false
    for addr in component.list("me_interface") do
        local ok = pcall(function() 
            component.proxy(addr).setInterfaceConfiguration(1, me.db.address, item.db_slot, qty) 
        end)
        if ok then configured = true end
    end
    if not configured then return false, "Не удалось настроить МЭ Интерфейсы!" end

    local moved = 0
    local attempts = 0
    
    -- Запрашиваем реальное количество слотов (обычно 9)
    local ok_inv, inv_size = pcall(me.t_out.getInventorySize, me.config.me_side)
    if not ok_inv or not inv_size or inv_size == 0 then inv_size = 9 end
    
    -- БЕЗОПАСНЫЙ СЛЕПОЙ ПЫЛЕСОС
    while moved < qty and attempts < 15 do
        os.sleep(0.25)
        for slot = 1, inv_size do
            -- Завернуто в защитный купол pcall! Больше никаких крашей!
            local ok, actual = pcall(me.t_out.transferItem, me.config.me_side, me.config.chest_side, qty - moved, slot)
            if ok and type(actual) == "number" and actual > 0 then 
                moved = moved + actual 
            end
            if moved >= qty then break end
        end
        if moved >= qty then break end
        attempts = attempts + 1
    end

    -- Очищаем настройку
    for addr in component.list("me_interface") do
        pcall(function() component.proxy(addr).setInterfaceConfiguration(1) end)
    end
    
    if moved > 0 then return true, "Выдано " .. moved .. " шт."
    else return false, "Интерфейс не отдал предмет! (Возможно, его нет в МЭ)" end
end

return me
