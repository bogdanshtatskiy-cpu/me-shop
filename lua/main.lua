-- /lua/main.lua
local event = require("event")
local os = require("os")
local io = require("io")
local term = require("term")
local gui = require("gui")
local computer = require("computer")
local config = require("config")
local me = require("me_logic")

os.execute("set +c")
local me_ok, me_msg = me.init()

local OWNER_NAME = "Администратор"
if config.admins then for k, v in pairs(config.admins) do OWNER_NAME = k; break end end

-- Временные локальные базы данных (позже подключим Firebase)
local mock_items = {
    { name = "Quantum Suit", price = 5000, stock = 1, category = "Броня" },
    { name = "Iridium Plate", price = 80, stock = 45, category = "Ресурсы" }
}
local mock_buyback = { { name = "Thorium", price = 15 } }
local categories = {"ВСЕ", "Ресурсы", "Механизмы", "Броня"}

local active_category = "ВСЕ"
local currentUser = nil
local idleTimer = 0
local state = "shop" -- shop, modal_qty, modal_msg, cart, admin_cat, admin_item, admin_buy, admin_wait_scan
local selectedItem = nil
local selectedQty = 1
local isCartMode = false
local cart = {}

-- ФУНКЦИЯ ВВОДА ТЕКСТА (Выключает GUI, включает консоль, возвращает текст)
local function askText(prompt_text)
    component.gpu.setBackground(0x000000)
    term.clear()
    print("=== РЕДАКТИРОВАНИЕ ===")
    print(prompt_text)
    io.write("> ")
    local input = io.read()
    return input
end

local function refreshScreen()
    if state == "shop" then
        gui.drawStatic(currentUser, currentUser and idleTimer or nil, #cart)
        gui.drawCategories(categories, active_category)
        local filtered = {}
        for _, item in ipairs(mock_items) do
            if active_category == "ВСЕ" or item.category == active_category then table.insert(filtered, item) end
        end
        gui.drawItems(filtered)
        gui.drawBuybackItems(mock_buyback, currentUser ~= nil)
        if not me_ok then component.gpu.set(2, component.gpu.getResolution(), "СИСТЕМНАЯ ОШИБКА: " .. me_msg) end
        
    elseif state == "modal_qty" then
        gui.drawStatic(currentUser, idleTimer, #cart)
        gui.drawQuantitySelector(selectedItem, selectedQty, isCartMode)
        
    elseif state == "cart" then
        gui.drawStatic(currentUser, idleTimer, #cart)
        gui.drawCart(cart)
        
    elseif state == "admin_cat" then gui.drawAdmin("cat", categories)
    elseif state == "admin_item" then gui.drawAdmin("item", mock_items)
    elseif state == "admin_buy" then gui.drawAdmin("buy", mock_buyback)
    end
end

local function showMsg(title, text, isError)
    local old_state = state
    state = "modal_msg"
    gui.drawNotification(title, text, isError)
    return old_state
end

refreshScreen()

while true do
    local ev, _, x, y, _, player_name = event.pull(1, "touch")
    
    if currentUser and state ~= "modal_msg" and not string.match(state, "admin") then
        if not ev then 
            idleTimer = idleTimer - 1
            if idleTimer <= 0 then currentUser = nil; cart = {}; state = "shop"; active_category = "ВСЕ" end
            refreshScreen()
        else idleTimer = 30 end -- 30 секунд при активности
    end

    if ev == "touch" then
        if currentUser and currentUser.name ~= player_name then computer.beep(400, 0.1)
        else
            local action = gui.checkClick(x, y)
            if action then
                computer.beep(1000, 0.05)
                
                -- ГЛОБАЛЬНЫЕ КНОПКИ
                if action == "close_modal" then state = "shop"; refreshScreen()
                elseif action == "close_admin" then state = "shop"; refreshScreen()
                elseif action == "open_cart" then state = "cart"; refreshScreen()
                
                -- МАГАЗИН
                elseif state == "shop" then
                    if action == "login" then
                        local is_adm = false; if config.admins and config.admins[player_name] then is_adm = true end
                        currentUser = { name = player_name, balance = 10000, isAdmin = is_adm }; idleTimer = 30; refreshScreen()
                    elseif action == "logout" then currentUser = nil; cart = {}; refreshScreen()
                    elseif action == "admin_panel" then state = "admin_item"; refreshScreen()
                    elseif action:match("cat_") then active_category = action:gsub("cat_", ""); refreshScreen()
                    elseif action == "sell_all" then
                        if not currentUser then showMsg("ОШИБКА", "Авторизуйтесь!", true)
                        else
                            local success, msg, earned = me.sellAll(mock_buyback)
                            if success then currentUser.balance = currentUser.balance + earned; showMsg("УСПЕХ", msg .. " +" .. earned .. " ЭМ", false)
                            else showMsg("ОШИБКА", msg, true) end
                        end
                    elseif action:match("buy_") or action:match("cart_") then
                        if not currentUser then showMsg("ОШИБКА", "Авторизуйтесь!", true)
                        else
                            local idx = tonumber(action:match("%d+"))
                            selectedItem = mock_items[idx]
                            selectedQty = 1
                            isCartMode = (action:match("cart_") ~= nil)
                            state = "modal_qty"; refreshScreen()
                        end
                    end
                
                -- ВЫБОР КОЛИЧЕСТВА
                elseif state == "modal_qty" then
                    if action == "qty_add1" then selectedQty = selectedQty + 1
                    elseif action == "qty_sub1" then selectedQty = selectedQty - 1
                    elseif action == "qty_add10" then selectedQty = selectedQty + 10
                    elseif action == "qty_sub10" then selectedQty = selectedQty - 10
                    elseif action == "confirm_cart" then
                        table.insert(cart, {item = selectedItem, qty = selectedQty})
                        state = "shop"; refreshScreen()
                    elseif action == "confirm_buy" then
                        local cost = selectedItem.price * selectedQty
                        if selectedItem.stock < selectedQty then showMsg("ОШИБКА", "Не хватает товара!", true)
                        elseif currentUser.balance < cost then showMsg("ОШИБКА", "Мало ЭМ!", true)
                        else
                            currentUser.balance = currentUser.balance - cost
                            selectedItem.stock = selectedItem.stock - selectedQty
                            showMsg("УСПЕХ", "Куплено " .. selectedQty .. " шт.", false)
                        end
                    end
                    if selectedQty < 1 then selectedQty = 1 end
                    if selectedQty > 64 then selectedQty = 64 end
                    if state == "modal_qty" then refreshScreen() end
                
                -- КОРЗИНА
                elseif state == "cart" then
                    if action:match("cart_del_") then
                        local idx = tonumber(action:match("%d+"))
                        table.remove(cart, idx); refreshScreen()
                    elseif action == "checkout" then
                        if #cart == 0 then showMsg("ОШИБКА", "Корзина пуста!", true)
                        else
                            local totalCost = 0
                            for _, ci in ipairs(cart) do totalCost = totalCost + (ci.item.price * ci.qty) end
                            if currentUser.balance < totalCost then showMsg("ОШИБКА", "Недостаточно средств!", true)
                            else
                                currentUser.balance = currentUser.balance - totalCost
                                cart = {} -- Очищаем корзину после покупки
                                showMsg("ОПЛАТА", "Покупки успешно выданы!", false)
                            end
                        end
                    end

                -- === АДМИН ПАНЕЛЬ (ПОЛНАЯ ЛОГИКА) ===
                elseif string.match(state, "admin") then
                    if action == "adm_cat" then state = "admin_cat"; refreshScreen()
                    elseif action == "adm_item" then state = "admin_item"; refreshScreen()
                    elseif action == "adm_buy" then state = "admin_buy"; refreshScreen()
                    
                    -- ДОБАВЛЕНИЕ НОВОГО
                    elseif action == "adm_add" then
                        if state == "admin_cat" then
                            local cat = askText("Введите название новой категории:")
                            if cat and cat ~= "" then table.insert(categories, cat) end
                            refreshScreen()
                        elseif state == "admin_item" or state == "admin_buy" then
                            -- Процесс сканирования
                            showMsg("СКАНИРОВАНИЕ", "Положите 1 предмет в сундук и нажмите ОК", false)
                            state = "admin_wait_scan"
                        end
                        
                    -- УДАЛЕНИЕ
                    elseif action:match("adm_del_") then
                        local idx = tonumber(action:match("%d+"))
                        if state == "admin_cat" then table.remove(categories, idx)
                        elseif state == "admin_item" then table.remove(mock_items, idx)
                        elseif state == "admin_buy" then table.remove(mock_buyback, idx) end
                        refreshScreen()
                        
                    -- РЕДАКТИРОВАНИЕ
                    elseif action:match("adm_edit_") then
                        local idx = tonumber(action:match("%d+"))
                        if state == "admin_cat" then
                            local n = askText("Новое название категории:")
                            if n and n ~= "" then categories[idx] = n end
                        elseif state == "admin_item" then
                            local n = askText("Новое имя товара (Enter - оставить " .. mock_items[idx].name .. "):")
                            local p = askText("Новая цена (число):")
                            if n and n ~= "" then mock_items[idx].name = n end
                            if p and tonumber(p) then mock_items[idx].price = tonumber(p) end
                        elseif state == "admin_buy" then
                            local n = askText("Новое имя ресурса (Enter - оставить " .. mock_buyback[idx].name .. "):")
                            local p = askText("Новая цена скупки:")
                            if n and n ~= "" then mock_buyback[idx].name = n end
                            if p and tonumber(p) then mock_buyback[idx].price = tonumber(p) end
                        end
                        refreshScreen()
                    end
                
                -- ОЖИДАНИЕ СКАНИРОВАНИЯ ИЗ СУНДУКА
                elseif state == "admin_wait_scan" and action == "close_modal" then
                    local stack, err = me.peekInput()
                    if not stack then
                        showMsg("ОШИБКА СКАНЕРА", err, true)
                        state = "admin_item" -- Возврат
                    else
                        local n = askText("Предмет: " .. stack.label .. "\nВведите красивое название для магазина:")
                        local p = askText("Введите цену (число):")
                        if n == "" then n = stack.label end
                        
                        if p and tonumber(p) then
                            -- Добавляем в ту таблицу, откуда пришли
                            table.insert(mock_items, { name = n, price = tonumber(p), stock = 0, category = "ВСЕ" })
                            state = "admin_item"
                            refreshScreen()
                        else
                            state = "admin_item"
                            showMsg("ОШИБКА", "Цена должна быть числом!", true)
                        end
                    end
                end
            end
        end
    end
end
