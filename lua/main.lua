-- /lua/main.lua
local event = require("event")
local os = require("os")
local gui = require("gui")
local computer = require("computer")

os.execute("set +c")

local mock_items = {
    { name = "Quantum Suit", price = 5000, stock = 1, category = "Броня" },
    { name = "Iridium Plate", price = 80, stock = 45, category = "Ресурсы" },
    { name = "ME Drive", price = 50, stock = 0, category = "Механизмы" }
}

local mock_buyback = {
    { name = "Thorium", price = 15 },
    { name = "Uranium", price = 25 }
}

local categories = {"ВСЕ", "Ресурсы", "Механизмы", "Броня"}
local active_category = "ВСЕ"

local currentUser = nil
local idleTimer = 0
local state = "shop" -- shop, modal_msg, modal_qty, admin
local selectedItem = nil
local selectedQty = 1

local OWNER_NAME = "Admin" -- Замени на свой ник

local function refreshScreen()
    if state == "shop" then
        gui.drawStatic(currentUser, currentUser and idleTimer or nil)
        gui.drawCategories(categories, active_category)
        local filtered = {}
        for _, item in ipairs(mock_items) do
            if active_category == "ВСЕ" or item.category == active_category then
                table.insert(filtered, item)
            end
        end
        gui.drawItems(filtered)
        gui.drawBuybackItems(mock_buyback)
    elseif state == "modal_msg" then
        -- Экран не перерисовываем целиком, просто модалка висит
    elseif state == "modal_qty" then
        gui.drawStatic(currentUser, idleTimer)
        gui.drawQuantitySelector(selectedItem, selectedQty)
    elseif state == "admin" then
        require("term").clear()
        print("=== ПАНЕЛЬ АДМИНИСТРАТОРА ===")
        print("1. Редактировать категории (в разработке)")
        print("2. Редактировать товары (в разработке)")
        print("3. Настроить сундуки (в разработке)")
        gui.buttons = {}
        gui.btn("close_admin", 5, 10, 20, 3, "ВЫЙТИ ИЗ АДМИНКИ", gui.COLORS.bad)
    end
end

local function showMsg(title, text, isError)
    state = "modal_msg"
    gui.drawNotification(title, text, isError)
end

refreshScreen()

while true do
    -- Ждем события ровно 1 секунду. Если ничего не произошло - возвращает nil
    local ev, address, x, y, button, player_name = event.pull(1, "touch")
    
    -- Обработка таймера
    if currentUser and state ~= "admin" then
        if not ev then 
            idleTimer = idleTimer - 1
            if idleTimer <= 0 then
                currentUser = nil
                state = "shop"
                active_category = "ВСЕ"
            end
            refreshScreen() -- Обновляем цифры таймера на экране
        else
            idleTimer = 20 -- Сброс таймера при любом клике
        end
    end

    -- Обработка кликов
    if ev == "touch" then
        if currentUser and currentUser.name ~= player_name then
            computer.beep(400, 0.1) -- Чужой клик
        else
            local action = gui.checkClick(x, y)
            if action then
                computer.beep(1000, 0.05)
                
                if action == "close_modal" then
                    state = "shop"; refreshScreen()
                elseif action == "close_admin" then
                    state = "shop"; refreshScreen()
                
                elseif state == "shop" then
                    if action == "login" then
                        local is_adm = (player_name == OWNER_NAME)
                        currentUser = { name = player_name, balance = 1000, isAdmin = is_adm }
                        idleTimer = 20
                        refreshScreen()
                    elseif action == "logout" then
                        currentUser = nil; refreshScreen()
                    elseif action == "admin_panel" then
                        state = "admin"; refreshScreen()
                    elseif action:match("cat_") then
                        active_category = action:gsub("cat_", ""); refreshScreen()
                    
                    -- НАЖАТИЕ НА "ПРОДАТЬ ВСЁ"
                    elseif action == "sell_all" then
                        if not currentUser then
                            showMsg("ОШИБКА", "Сначала авторизуйтесь!", true)
                        else
                            -- Здесь будет вызов me_logic.lua для сканирования сундука
                            -- Пока делаем мок-уведомление
                            local earned = 150
                            local items_sold = "Торий (x10)"
                            currentUser.balance = currentUser.balance + earned
                            showMsg("УСПЕШНАЯ СДАЧА", "Продано: " .. items_sold .. " | Зачислено: " .. earned .. " ЭМ", false)
                        end

                    -- НАЖАТИЕ НА "КУПИТЬ" (открытие модалки)
                    elseif action:match("buy_") then
                        if not currentUser then
                            showMsg("ОШИБКА", "Сначала авторизуйтесь!", true)
                        else
                            local idx = tonumber(action:match("%d+"))
                            selectedItem = mock_items[idx]
                            selectedQty = 1
                            state = "modal_qty"
                            refreshScreen()
                        end
                    end
                
                -- ЛОГИКА ВНУТРИ ОКНА ВЫБОРА КОЛИЧЕСТВА
                elseif state == "modal_qty" then
                    if action == "qty_add1" then selectedQty = selectedQty + 1
                    elseif action == "qty_sub1" then selectedQty = selectedQty - 1
                    elseif action == "qty_add10" then selectedQty = selectedQty + 10
                    elseif action == "qty_sub10" then selectedQty = selectedQty - 10
                    elseif action == "confirm_buy" then
                        local totalCost = selectedItem.price * selectedQty
                        
                        -- Проверки
                        if selectedItem.stock < selectedQty then
                            showMsg("ОШИБКА", "Не хватает товара! Напишите " .. OWNER_NAME, true)
                        elseif currentUser.balance < totalCost then
                            showMsg("ОШИБКА", "Недостаточно средств (нужно " .. totalCost .. ")", true)
                        else
                            -- Здесь будет вызов me_logic.lua на выдачу
                            currentUser.balance = currentUser.balance - totalCost
                            selectedItem.stock = selectedItem.stock - selectedQty
                            showMsg("УСПЕХ", "Куплено " .. selectedQty .. " шт. за " .. totalCost .. " ЭМ", false)
                        end
                    end
                    
                    -- Ограничения кнопок +/-
                    if selectedQty < 1 then selectedQty = 1 end
                    if selectedQty > 64 then selectedQty = 64 end
                    if state == "modal_qty" then refreshScreen() end
                end
            end
        end
    end
end
