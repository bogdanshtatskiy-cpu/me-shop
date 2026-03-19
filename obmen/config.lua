-- /obmen/config.lua
local config = {}

-- Администраторы (имеют доступ к редактированию обменов и логам)
config.admins = {
    ["DesOope"] = true,
    ["Admin2"] = true
}

-- Часовой пояс для логов (Например: 2 для Киева, 3 для Мск)
config.timezone = 2

return config
