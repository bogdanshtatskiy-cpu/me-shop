-- /obmen/installer.lua
local internet = require("internet")
local repo = "https://raw.githubusercontent.com/bogdanshtatskiy-cpu/me-shop/main/obmen/"
local files = {"config.lua", "me_logic.lua", "gui.lua", "main.lua"}

print("=== УСТАНОВКА АВТО-ОБМЕННИКА ===")
for _, file in ipairs(files) do
    io.write("Скачивание " .. file .. " ... ")
    local success, response = pcall(internet.request, repo .. file)
    if success then
        local content = ""
        for chunk in response do content = content .. chunk end
        local f = io.open("/home/" .. file, "w")
        if f then f:write(content); f:close(); print("[OK]") else print("[ОШИБКА]") end
    else print("[ОШИБКА СЕТИ]") end
end
print("Установка завершена! Введите: main")
