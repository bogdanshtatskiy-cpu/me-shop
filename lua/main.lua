-- /lua/main.lua
local event = require("event")
local os = require("os")
local gui = require("gui")
-- local me = require("me_logic") -- Раскомментируем, когда подключим сундуки
-- local network = require("network") -- Раскомментируем для Firebase

-- Блокируем Ctrl+Alt+C (защита от взлома игроками)
os.execute("set +c")

-- Тестовые данные для проверки интерфейса (потом это будет грузиться из БД)
local mock_items = {
    { name = "Draconic Core", price = 150, stock = 12 },
    { name = "Iridium Plate", price = 80, stock = 45 },
    { name = "Resonant Energy Cell", price = 300, stock = 2 },
    { name = "ME Drive", price = 50, stock = 0 }
}

local currentUser = nil
local running = true

-- Главная функция отрисовки экрана
local function refreshScreen()
    gui.drawStatic(currentUser)
    gui.drawItems(mock_items)
end

-- Обработка событий
local function handleEvent(ev, address, x, y, button, player_name)
    if ev == "touch" then
        local action = gui.checkClick(x, y)
        if not action then return end
        
        if action == "login" then
            -- В OpenComputers событие touch всегда возвращает ник кликнувшего (player_name)
            currentUser = { name = player_name, balance = 1000 }
            refreshScreen()
        elseif action == "logout" then
            currentUser = nil
            refreshScreen()
        elseif action == "admin_panel" then
            -- Проверка: является ли кликнувший админом?
            -- if config.admins[player_name] then ...
            gui.drawStatic(currentUser)
            gui.btn("close_admin", 5, 5, 20, 3, "ЗАКРЫТЬ АДМИНКУ", gui.COLORS.bad)
            -- Здесь будет отрисовка интерфейса регистрации предметов
        elseif action:match("buy_") then
            local idx = tonumber(action:match("%d+"))
            local item = mock_items[idx]
            -- Логика добавления в корзину или мгновенной покупки
        elseif action == "exit" then -- Для тестов оставим возможность выйти
            running = false
        end
    end
end

-- Инициализация
refreshScreen()

-- Главный цикл
while running do
    -- Ждем события (клик по монитору)
    local ev, address, x, y, button, player_name = event.pull(0.5)
    if ev then
        handleEvent(ev, address, x, y, button, player_name)
    end
end

-- Возвращаем консоль при выходе
require("term").clear()
os.execute("set -c") -- Возвращаем работу Ctrl+Alt+C
