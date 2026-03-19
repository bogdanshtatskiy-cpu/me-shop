-- /lua/network.lua
local internet = require("internet")

local net = {}

net.FIREBASE_URL = "https://me-shop-db-f7542-default-rtdb.europe-west1.firebasedatabase.app"
net.SECRET = "ТВОЙ_СЕКРЕТНЫЙ_КЛЮЧ_ИЗ_НАСТРОЕК_FIREBASE"

function net.request(method, path, data)
    local url = net.FIREBASE_URL .. path .. ".json?auth=" .. net.SECRET
    local headers = {}
    if data then headers["Content-Type"] = "application/json" end
    
    -- МАГИЯ ДЛЯ СТАРЫХ ВЕРСИЙ OC: ЗАСТАВЛЯЕМ FIREBASE ИГНОРИРОВАТЬ POST ОТ МОДА И ЧИТАТЬ НАШ МЕТОД
    headers["X-HTTP-Method-Override"] = method

    local success, response = pcall(function()
        local handle = internet.request(url, data, headers, method)
        local result = ""
        for chunk in handle do result = result .. chunk end
        return result
    end)
    
    if success then return true, response else return false, "Ошибка сети" end
end

function net.get(path) return net.request("GET", path) end
function net.put(path, data) return net.request("PUT", path, data) end
function net.patch(path, data) return net.request("PATCH", path, data) end

return net
