-- /lua/me_logic.lua
local component = require("component")
local sides = require("sides")

local me = {}

me.t = nil      
me.me_net = nil 
me.db = nil     

me.config = { 
    chest_side = sides.up,    -- Сундук скупки (СВЕРХУ от Транспоузера)
    me_side = sides.down,     -- МЭ Интерфейс (СНИЗУ от Транспоузера)
    out_chest_side = sides.up -- Сундук выдачи (СВЕРХУ от правого МЭ Интерфейса)
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
        local key = n_item.name .. "_" .. (n_item.label or "")
        lookup[key] = (lookup[key] or 0) + n_item.size
    end

    for _, s_item in ipairs(shop_items) do
        local key = s_item.id .. "_" .. (s_item.orig_label or "")
        s_item.stock = lookup[key] or 0
    end
end

-- МОМЕНТАЛЬНАЯ СКУПКА ЧЕРЕЗ getAllStacks()
function me.sellAll(buyback_list)
    if not me.t then return false, "Транспоузер не подключен!", 0 end

    -- Делаем мгновенный слепок сундука
    local stacks = me.t.getAllStacks(me.config.chest_side)
    if not stacks then return false, "Сундук не найден!", 0 end

    local total_earned = 0
    local sold_stats = {}
    local err_msg = nil
    local slot = 0

    -- Перебираем предметы из памяти (без задержек)
    local function processStack(s_slot, stack)
        if type(stack) == "table" and stack.size and stack.size > 0 then
            local matched_item = nil
            for _, b_item in ipairs(buyback_list) do
                if stack.name == b_item.id or stack.label == b_item.orig_label then
                    matched_item = b_item; break
                end
            end
            if matched_item then
                local moved, reason = me.t.transferItem(me.config.chest_side, me.config.me_side, stack.size, s_slot)
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

    if type(stacks) == "table" then
        for s_slot, stack in pairs(stacks) do processStack(s_slot, stack) end
    elseif type(stacks) == "function" then
        for stack in stacks do slot = slot + 1; processStack(slot, stack) end
    end

    if total_earned > 0 then
        -- Формируем красивый чек
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

-- ВЫДАЧА ПРЕДМЕТА ЧЕРЕЗ МЭ ИНТЕРФЕЙС
function me.buyItem(db_slot, qty)
    if not me.me_net or not me.db then return false, "МЭ или БД не подключены!" end
    if not db_slot then return false, "Товар не привязан к Базе Данных!" end
    
    local ok, err = pcall(function()
        -- exportItem(адрес_БД, слот_БД, количество, сторона_выдачи)
        me.me_net.exportItem(me.db.address, db_slot, qty, me.config.out_chest_side)
    end)
    
    if ok then return true, "Выдано" else return false, tostring(err) end
end

return me
