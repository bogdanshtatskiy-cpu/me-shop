-- /lua/installer.lua
local component = require("component")
local fs = require("filesystem")

if not component.isAvailable("internet") then
    print("Ошибка: Для установки требуется интернет-карта!")
    return
end

local internet = component.internet
local repo_url = "https://raw.githubusercontent.com/bogdanshtatskiy-cpu/me-shop/main/lua/"

-- Список файлов для загрузки
local files = {
    "main.lua",
    "gui.lua",
    "network.lua",
    "me_logic.lua",
    "config.lua",
    "json.lua" -- Библиотека для работы с JSON (добавим позже)
}

print("=== Установка ME-Shop ===")
fs.makeDirectory("/shop")

for _, file in ipairs(files) do
    io.write("Скачивание " .. file .. "... ")
    local url = repo_url .. file
    
    local success, response = pcall(function()
        local handle = internet.request(url)
        local result = ""
        while true do
            local chunk = handle.read(math.huge)
            if chunk then result = result .. chunk else break end
        end
        handle.close()
        return result
    end)
    
    if success and response and #response > 0 then
        local f = io.open("/shop/" .. file, "w")
        f:write(response)
        f:close()
        print("[ОК]")
    else
        print("[ОШИБКА]")
    end
end

print("-------------------------")
print("Установка завершена! Все файлы находятся в папке /shop")
print("Не забудьте отредактировать /shop/config.lua перед запуском.")
