-- /lua/config.lua
local config = {}

-- Секретный ключ базы данных Firebase
-- В ГИТХАБЕ ОСТАВЛЯЕМ ПУСТЫМ! Заполняем только на компьютере в игре.
config.db_secret = ""

-- Название валюты
config.currency_name = "ЭМ"

-- РУБИЛЬНИК БАЗЫ ДАННЫХ
-- true = работает с Firebase и веб-панелью
-- false = работает полностью оффлайн (только жесткий диск компьютера)
config.use_database = true

-- Администраторы (кому доступна скрытая панель)
config.admins = {
    ["DesOope"] = true
}

return config
