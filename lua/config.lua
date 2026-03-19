-- /lua/config.lua
local config = {}

-- Секретный ключ базы данных Firebase
-- В ГИТХАБЕ ОСТАВЛЯЕМ ПУСТЫМ! Заполняем только на компьютере в игре.
config.db_secret = ""

-- Название валюты
config.currency_name = "ЭМ"

-- Часовой пояс (смещение от UTC в часах)
-- Впиши цифру. Например: 2 (для UTC+2), 3 (для UTC+3), -5 (для UTC-5)
config.timezone = 2

-- РУБИЛЬНИК БАЗЫ ДАННЫХ
-- true = работает с Firebase и веб-панелью
-- false = работает полностью оффлайн (только жесткий диск компьютера)
config.use_database = true

-- Администраторы (кому доступна скрытая панель)
config.admins = {
    ["DesOope"] = true
    ["ник"] = true
}

return config
