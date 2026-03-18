-- /lua/main.lua
local event = require("event")
local os = require("os")
local gui = require("gui")
local computer = require("computer")
local config = require("config")
local me = require("me_logic") -- ПОДКЛЮЧАЕМ МЭ ЛОГИКУ!

os.execute("set +c")

-- Инициализация МЭ компонентов при старте
local me_ok, me_msg = me.init()

local OWNER_NAME = "Администратор"
if config.admins then
    for k, v in pairs(config.admins) do OWNER_NAME = k; break end
end

local mock_items = {
    { name = "Quantum Suit", price = 5000, stock = 1, category = "Броня" },
    { name = "Iridium Plate", price = 80, stock = 45, category = "Ресурсы" }
}

-- Тестовый список скупки (name должен совпадать с label предмета в игре)
local mock_buyback = {
    { name = "Cobblestone", price = 1 }, -- Для тестов используем булыжник
    { name = "Thorium", price = 15 }
}

local categories = {"ВСЕ", "Ресурсы", "Механизмы", "Броня"}
local active_category = "ВСЕ"

local currentUser = nil
local idleTimer = 0
local state = "shop"
local selectedItem = nil
local selectedQty = 1

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
        
        -- Если МЭ сеть не инициализировалась, выводим предупреждение внизу экрана
        if not me_ok then
            local W, H = component.gpu.getResolution()
            component.gpu.setForeground(gui.COLORS.bad)
            component.gpu.set(2, H, "СИСТЕМНАЯ ОШИБКА: " .. me_msg)
        end
        
    elseif state == "modal_qty" then
        gui.drawStatic(currentUser, idleTimer)
        gui.drawQuantitySelector(selectedItem, selectedQty)
    elseif state == "admin" then
        require("term").clear()
        print("=== ПАНЕЛЬ АДМИНИСТРАТОРА: " .. currentUser.name .. " ===")
        print("Статус МЭ: " .. tostring(me_msg))
        print("1. Добавить товары (в разработке)")
        print("2. Калибровка МЭ сундуков (в разработке)")
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
    local ev, address, x, y, button, player_name = event.pull(1, "touch")
    
    if currentUser and state ~= "admin" and state ~= "modal_msg" then
        if not ev then 
            idleTimer = idleTimer - 1
            if idleTimer <= 0 then
                currentUser = nil; state = "shop"; active_category = "ВСЕ"
            end
            refreshScreen()
        else
            idleTimer = 20
        end
    end

    if ev == "touch" then
        if currentUser and currentUser.name ~= player_name then
            computer.beep(400, 0.1)
        else
            local action = gui.checkClick(x, y)
            if action then
                computer.beep(1000, 0.05)
                
                if action == "close_modal" or action == "close_admin" then
                    state = "shop"; refreshScreen()
                
                elseif state == "shop" then
                    if action == "login" then
                        local is_adm = false
                        if config.admins and config.admins[player_name] then is_adm = true end
                        -- Для тестов даем начальный баланс 0, чтобы проверить скупку
                        currentUser = { name = player_name, balance = 0, isAdmin = is_adm }
                        idleTimer = 20
                        refreshScreen()
                    elseif action == "logout" then
                        currentUser = nil; refreshScreen()
                    elseif action == "admin_panel" then
                        state = "admin"; refreshScreen()
                    elseif action:match("cat_") then
                        active_category = action:gsub("cat_", ""); refreshScreen()
                        
                    -- === ФИЗИЧЕСКАЯ ПРОДАЖА ПРЕДМЕТОВ ===
                    elseif action == "sell_all" then
                        if not currentUser then 
                            showMsg("ОШИБКА", "Сначала авторизуйтесь!", true)
                        else
                            local success, msg, earned = me.sellAll(mock_buyback)
                            if success then
                                currentUser.balance = currentUser.balance + earned
                                showMsg("УСПЕШНАЯ СДАЧА", msg .. " | Зачислено: " .. earned .. " ЭМ", false)
                            else
                                showMsg("ОШИБКА СДАЧИ", msg, true)
                            end
                        end
                        
                    elseif action:match("buy_") then
                        if not currentUser then showMsg("ОШИБКА", "Сначала авторизуйтесь!", true)
                        else
                            local idx = tonumber(action:match("%d+"))
                            selectedItem = mock_items[idx]
                            selectedQty = 1
                            state = "modal_qty"; refreshScreen()
                        end
                    end
                
                elseif state == "modal_qty" then
                    if action == "qty_add1" then selectedQty = selectedQty + 1
                    elseif action == "qty_sub1" then selectedQty = selectedQty - 1
                    elseif action == "qty_add10" then selectedQty = selectedQty + 10
                    elseif action == "qty_sub10" then selectedQty = selectedQty - 10
                    elseif action == "confirm_buy" then
                        local totalCost = selectedItem.price * selectedQty
                        if selectedItem.stock < selectedQty then
                            showMsg("ОШИБКА", "Не хватает товара! Напишите " .. OWNER_NAME, true)
                        elseif currentUser.balance < totalCost then
                            showMsg("ОШИБКА", "Недостаточно средств!", true)
                        else
                            -- В будущем здесь будет me.buyItem()
                            currentUser.balance = currentUser.balance - totalCost
                            selectedItem.stock = selectedItem.stock - selectedQty
                            showMsg("УСПЕХ", "Куплено " .. selectedQty .. " шт.", false)
                        end
                    end
                    if selectedQty < 1 then selectedQty = 1 end
                    if selectedQty > 64 then selectedQty = 64 end
                    if state == "modal_qty" then refreshScreen() end
                end
            end
        end
    end
end
