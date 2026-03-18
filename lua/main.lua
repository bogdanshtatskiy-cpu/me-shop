-- /lua/main.lua
local event = require("event")
local os = require("os")
local gui = require("gui")
local computer = require("computer")

os.execute("set +c")

-- Тестовые данные
local mock_items = {
    { name = "Quantum Suit", price = 5000, stock = 1, category = "Броня" },
    { name = "Iridium Plate", price = 80, stock = 45, category = "Ресурсы" },
    { name = "ME Drive", price = 50, stock = 0, category = "Механизмы" }
}

-- Тестовые предметы на скупку
local mock_buyback = {
    { name = "Thorium", price = 15 },
    { name = "Uranium", price = 25 }
}

local categories = {"ВСЕ", "Ресурсы", "Механизмы", "Броня"}
local active_category = "ВСЕ"
local currentUser = nil
local running = true

local function refreshScreen()
    gui.drawStatic(currentUser)
    gui.drawCategories(categories, active_category)
    
    -- Фильтрация по категориям
    local filtered = {}
    for _, item in ipairs(mock_items) do
        if active_category == "ВСЕ" or item.category == active_category then
            table.insert(filtered, item)
        end
    end
    
    gui.drawItems(filtered)
    gui.drawBuybackItems(mock_buyback)
end

refreshScreen()

while running do
    local ev, address, x, y, button, player_name = event.pull(0.5)
    
    if ev == "touch" then
        -- БЛОКИРОВКА СЕССИИ: Если кто-то залогинен, и это не он кликает - игнорируем
        if currentUser and currentUser.name ~= player_name then
            computer.beep(400, 0.1) -- Звук ошибки для "чужого"
        else
            local action = gui.checkClick(x, y)
            if action then
                computer.beep(1000, 0.05)
                
                if action == "login" then
                    -- Для теста даем админку, если ник совпадает с твоим (замени на свой)
                    local is_adm = (player_name == "ТвойНик")
                    currentUser = { name = player_name, balance = 1000, isAdmin = is_adm }
                    refreshScreen()
                    
                elseif action == "logout" then
                    currentUser = nil
                    active_category = "ВСЕ"
                    refreshScreen()
                    
                elseif action:match("cat_") then
                    active_category = action:gsub("cat_", "")
                    refreshScreen()
                    
                elseif action == "admin_panel" then
                    -- Переход в админку
                    require("term").clear()
                    print("Открыта админ панель (в разработке)")
                    os.sleep(2)
                    refreshScreen()
                    
                elseif action == "exit" then
                    running = false
                end
            end
        end
    end
end

require("term").clear()
os.execute("set -c")
