-- /lua/casino_me_logic.lua
local component = require("component")
local sides = require("sides")
local json = require("casino_json")
local fs = require("filesystem")

local me = {}
me.t = nil      

-- Default configuration. Can be overridden if needed.
me.config = { chest_side = sides.up, me_side = sides.down }

-- Temporary database for deposit prices. Loaded from a file.
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

-- Public function to save prices (can be called from admin panel)
function me.saveDepositPrices(new_prices)
    if type(new_prices) ~= "table" then return false, "Invalid data format" end
    deposit_prices = new_prices
    local f = io.open(DEPOSIT_DB_PATH, "w")
    if f then
        f:write(json.encode(deposit_prices))
        f:close()
        return true
    else
        return false, "Failed to write prices file"
    end
end

function me.getDepositPrices()
    return deposit_prices
end

function me.init()
    if component.isAvailable("transposer") then me.t = component.transposer end
    if not me.t then return false, "Transposer not found!" end
    if not component.isAvailable("me_interface") then return false, "ME Interface not found!" end
    
    loadDepositPrices() -- Load prices on init
    
    return true, "ME components are ready."
end

function me.sellAllToBalance()
    if not me.t then return false, "Transposer not connected!", 0 end
    local inv_size = me.t.getInventorySize(me.config.chest_side)
    if not inv_size or inv_size == 0 then return false, "Deposit chest not found!", 0 end

    local total_earned = 0; local sold_stats = {}; local err_msg = nil

    for slot = 1, inv_size do
        local stack = me.t.getStackInSlot(me.config.chest_side, slot)
        if stack and stack.size > 0 then
            local item_key = stack.name .. (stack.damage > 0 and (":"..stack.damage) or "")
            local price = deposit_prices[item_key]

            if price and tonumber(price) then
                local moved, reason = me.t.transferItem(me.config.chest_side, me.config.me_side, stack.size, slot)
                local actual_moved = 0
                if type(moved) == "number" then actual_moved = moved
                elseif type(moved) == "boolean" and moved == true then actual_moved = stack.size
                elseif type(moved) == "boolean" and moved == false then err_msg = reason end

                if actual_moved > 0 then
                    total_earned = total_earned + (actual_moved * tonumber(price))
                    local display_name = stack.label or stack.name
                    sold_stats[display_name] = (sold_stats[display_name] or 0) + actual_moved
                end
            end
        end
    end

    if total_earned > 0 then
        local receipt = ""
        for name, qty in pairs(sold_stats) do receipt = receipt .. name .. "(x" .. qty .. ") " end
        return true, "Sold: " .. receipt, total_earned
    else return false, "Nothing sold. Reason: " .. tostring(err_msg or "No matching items or prices not set"), 0 end
end

function me.peekInput()
    if not me.t then return nil, "Transposer not connected!" end
    local inv_size = me.t.getInventorySize(me.config.chest_side)
    for slot = 1, inv_size do
        local stack = me.t.getStackInSlot(me.config.chest_side, slot)
        if stack and stack.size > 0 then return stack end
    end
    return nil, "Place an item in the chest!"
end

-- Prize delivery
function me.givePrize(item_id, item_damage, qty)
    local perfect_fingerprint = {
        id = item_id,
        dmg = math.floor(item_damage or 0)
    }
    
    local total_moved = 0
    local last_err = "Output chest not found above any ME Interface!"

    for addr in component.list("me_interface") do
        local me_proxy = component.proxy(addr)
        for side = 0, 5 do
            local ok, result = pcall(me_proxy.exportItem, perfect_fingerprint, side, qty)
            local moved_now = 0
            
            if ok and type(result) == "table" and result.size then moved_now = result.size
            elseif ok and type(result) == "number" then moved_now = result end
            
            if moved_now > 0 then
                total_moved = total_moved + moved_now
                
                local attempts = 0
                while total_moved < qty and attempts < 150 do
                    local batch = qty - total_moved
                    local ok2, res2 = pcall(me_proxy.exportItem, perfect_fingerprint, side, batch)
                    local m2 = 0
                    
                    if ok2 and type(res2) == "table" and res2.size then m2 = res2.size
                    elseif ok2 and type(res2) == "number" then m2 = res2 end
                    
                    if m2 > 0 then
                        total_moved = total_moved + m2
                    else
                        break 
                    end
                    attempts = attempts + 1
                end
                
                return true, "Success", total_moved
            elseif not ok then
                last_err = tostring(result)
            end
        end
        if total_moved > 0 then break end
    end
    
    if total_moved > 0 then 
        return true, "Partial", total_moved
    else 
        return false, "Error: " .. last_err, 0 
    end
end

return me
