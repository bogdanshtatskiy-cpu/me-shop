-- /lua/network.lua
local component = require("component")
local config = require("config")

local network = {}

-- Ссылка на твою базу данных
network.db_url = "https://me-shop-db-f7542-default-rtdb.europe-west1.firebasedatabase.app"

-- Базовая функция запроса
local function request(method, path, data_json)
    if not component.isAvailable("internet") then
        return false, "Интернет-карта не найдена!"
    end
    
    local internet = component.internet
    local url = network.db_url .. path .. ".json"
    
    -- Если указан секретный ключ базы, добавляем его для авторизации
    if config.db_secret and config.db_secret ~= "" then
        url = url .. "?auth=" .. config.db_secret
    end
    
    local headers = { ["Content-Type"] = "application/json" }
    local result_data = ""
    
    local success, err = pcall(function()
        local handle = internet.request(url, data_json, headers, method)
        while true do
            local chunk, reason = handle.read(math.huge)
            if chunk then
                result_data = result_data .. chunk
            else
                if reason then error(reason) end
                break
            end
        end
        handle.close()
    end)
    
    if success then
        return true, result_data
    else
        return false, err or "Неизвестная ошибка сети"
    end
end

-- Получить данные (GET)
function network.get(path)
    return request("GET", path, nil)
end

-- Перезаписать данные (PUT)
function network.put(path, data_json)
    return request("PUT", path, data_json)
end

-- Обновить часть данных (PATCH)
function network.patch(path, data_json)
    return request("PATCH", path, data_json)
end

return network
