-- /lua/casino_network.lua
local internet = require("internet")
local config = require("casino_config")

local net = {}

function net.request(method, path, data)
    if not config.firebase_url or config.firebase_url == "" then
        return false, "Database URL not configured in casino_config.lua"
    end
    
    -- Add the main casino path to all requests
    local full_path = "/" .. (config.main_db_path or "casino") .. (path or "") .. ".json"

    local url = config.firebase_url .. full_path
    
    if config.db_secret and config.db_secret ~= "" then
        url = url .. "?auth=" .. config.db_secret
    end
    
    local headers = {}
    if data then headers["Content-Type"] = "application/json" end
    
    -- Firebase REST API uses X-HTTP-Method-Override for PATCH, but PUT and POST work directly.
    if method == "PATCH" or method == "PUT" then
        headers["X-HTTP-Method-Override"] = method
    end

    local success, response = pcall(function()
        -- For PUT/PATCH/POST send as POST, for GET send as GET
        local http_method = (method == "GET") and "GET" or "POST"
        local handle = internet.request(url, data, headers, http_method)
        local result = ""
        for chunk in handle do result = result .. chunk end
        return result
    end)
    
    if success then return true, response else return false, "Network error: " .. tostring(response) end
end

function net.get(path) return net.request("GET", path) end
function net.put(path, data) return net.request("PUT", path, data) end
function net.patch(path, data) return net.request("PATCH", path, data) end
-- POST for Firebase creates a unique ID, which is useful for logs
function net.post(path, data) return net.request("POST", path, data) end

return net
