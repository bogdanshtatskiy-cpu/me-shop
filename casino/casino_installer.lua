-- /lua/casino_installer.lua
local internet = require("internet")

-- ССЫЛКА НА ТВОЙ РЕПОЗИТОРИЙ НА GITHUB (ИЗМЕНИТЬ НА ПРАВИЛЬНЫЙ)
local repo = "https://raw.githubusercontent.com/bogdanshtatskiy-cpu/me-shop/main/lua/" -- ЗАГЛУШКА, НУЖНО ИЗМЕНИТЬ

local files = {
    "casino_config.lua",
    "casino_network.lua",
    "casino_me_logic.lua",
    "casino_gui.lua",
    "casino_json.lua",
    "casino_main.lua"
}

print("=== УСТАНОВКА КАЗИНО ===")
print("Подключение к GitHub...
")

for _, file in ipairs(files) do
    io.write("Скачивание " .. file .. " ... ")
    -- Предполагаем, что файлы в репозитории будут иметь те же имена, что и в `files`
    local url = repo .. file:gsub("casino_", "") -- Убираем префикс для скачивания, если в репо они без него
    
    -- Если файлы в репо с префиксом, то строка выше должна быть: local url = repo .. file
    
    local success, response = pcall(internet.request, url)
    
    if success then
        local content = ""
        for chunk in response do content = content .. chunk end
        
        if content:match("404: Not Found") then
            print("[ОШИБКА: Файл не найден]")
        else
            -- Сохраняем файл с префиксом
            local f = io.open("/home/" .. file, "w")
            if f then
                f:write(content)
                f:close()
                print("[OK]")
            else
                print("[ОШИБКА записи файла]")
            end
        end
    else
        print("[ОШИБКА сети]")
    end
end

print("
==============================")
print("Установка казино завершена!")
print("Обязательно настройте /home/casino_config.lua")
print("Для первого запуска введите:")
print("casino_main")
print("==============================")
