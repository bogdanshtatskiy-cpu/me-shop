-- /lua/me_logic.lua
local component = require("component")
local sides = require("sides")

local me = {}

me.t = nil      
me.me_net = nil 
me.db = nil     

me.config = {
    chest_side = sides.up,   
    me_side = sides.down     
}

function me.init()
    if component.isAvailable("transposer") then me.t = component.transposer end
    if component.isAvailable("me_interface") then me.me_net = component.me_interface end
    if component.isAvailable("database") then me.db = component.database end

    if not me.t then return false, "Транспоузер не найден!" end
    return true, "МЭ компоненты готовы."
end

function me.sellAll(buyback_list)
    if not me.t then return false, "Транспоузер не подключен!", 0 end

    local inv_size = me.t.getInventorySize(me.config.chest_side)
    if not inv_size or inv_size == 0 then return false, "Сундук не найден сверху!", 0 end

    local total_earned = 0
    local items_sold = 0
    local err_msg = nil

    for slot = 1, inv_size do
        local stack = me.t.getStackInSlot(me.config.chest_side, slot)
        if stack and stack.size > 0 then
            
            local matched_item = nil
            for _, b_item in ipairs(buyback_list) do
                if stack.label == b_item.name or stack.name == b_item.name then
                    matched_item = b_item; break
                end
            end

            if matched_item then
                -- Перекладываем (возвращает количество ИЛИ false + причину)
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

    if total_earned > 0 then
        local msg = "Успешно сдано: " .. items_sold .. " шт."
        if err_msg then msg = msg .. " (Часть не влезла: " .. tostring(err_msg) .. ")" end
        return true, msg, total_earned
    else
        return false, "Товары не сданы. Причина: " .. tostring(err_msg or "Нет подходящих предметов"), 0
    end
end

return me
