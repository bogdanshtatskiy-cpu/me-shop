-- /lua/main.lua
local component = require("component")
local event = require("event")
local os = require("os")
local term = require("term")
local unicode = require("unicode")
local gui = require("gui")
local config = require("config")
local me = require("me_logic")
local network = require("network")
local json = require("json")
local computer = require("computer")

os.execute("set +c")
local me_ok, me_msg = me.init()

local OWNER_NAME = "Администратор"
if config.admins then for k, v in pairs(config.admins) do OWNER_NAME = k; break end end

local shop_items = {}
local shop_buyback = {}
local categories = {"ВСЕ", "Ресурсы", "Механизмы", "Броня"}

local active_category = "ВСЕ"
local currentUser = nil
local idleTimer = 0
local state = "shop"
local selectedItem = nil
local selectedQty = 1
local isCartMode = false
local cart = {}
local admin_add_target = "item"

local function saveShop()
    local data = { categories = categories, items = shop_items, buyback = shop_buyback }
    network.put("/shop", json.encode(data))
end

local function saveUser()
    if currentUser then network.put("/users/" .. currentUser.name, json.encode({ balance = currentUser.balance })) end
end

local function loadDB()
    local succ, res = network.get("/shop")
    if succ and res and res ~= "null" then
        local parsed = json.decode(res)
        if parsed then
            if parsed.categories then categories = parsed.categories end
            if parsed.items then shop_items = parsed.items end
            if parsed.buyback then shop_buyback = parsed.buyback end
        end
    else
        saveShop()
    end
end

-- ВВОД ТЕКСТА ПРЯМО В GUI (без черных экранов)
local function readGUIInput(x, y, w, default)
    local text = default or ""
    local gpu = component.gpu
    gpu.setBackground(gui.COLORS.panel)
    gpu.setForeground(gui.COLORS.good)
    while true do
        gpu.fill(x, y, w, 1, " ")
        gpu.set(x, y, text .. "_") -- мигающий курсор
        local ev, _, char, code = event.pull("key_down")
        if code == 14 then -- Backspace
            text = unicode.sub(text, 1, -2)
        elseif code == 28 then -- Enter
            gpu.set(x, y, text .. " ")
            return text
        elseif char >= 32 then
            if unicode.len(text) < w - 2 then text = text .. unicode.char(char) end
        end
    end
end

-- Поиск свободного слота в Базе Данных (1-81)
local function getFreeDBSlot()
    local used = {}
    for _, item in ipairs(shop_items) do
        if item.db_slot then used[item.db_slot] = true end
    end
    for i = 1, 81 do
        if not used[i] then return i end
    end
    return nil
end

local function refreshScreen()
    if state == "shop" then
        me.updateStock(shop_items) -- ОБНОВЛЯЕМ КОЛИЧЕСТВО ИЗ МЭ СЕТИ!
        gui.drawStatic(currentUser, currentUser and idleTimer or nil, #cart)
        gui.drawCategories(categories, active_category)
        local filtered = {}
        for _, item in ipairs(shop_items) do
            if active_category == "ВСЕ" or item.category == active_category then table.insert(filtered, item) end
        end
        gui.drawItems(filtered)
        gui.drawBuybackItems(shop_buyback, currentUser ~= nil)
        if not me_ok then component.gpu.set(2, component.gpu.getResolution(), "СИСТЕМНАЯ ОШИБКА: " .. me_msg) end
        
    elseif state == "modal_qty" then
        gui.drawStatic(currentUser, idleTimer, #cart)
        gui.drawQuantitySelector(selectedItem, selectedQty, isCartMode)
        
    elseif state == "cart" then
        gui.drawStatic(currentUser, idleTimer, #cart)
        gui.drawCart(cart)
        
    elseif state == "admin_cat" then gui.drawAdmin("cat", categories)
    elseif state == "admin_item" then gui.drawAdmin("item", shop_items)
    elseif state == "admin_buy" then gui.drawAdmin("buy", shop_buyback)
    end
end

local function showMsg(title, text, isError)
    state = "modal_msg"
    gui.drawNotification(title, text, isError)
end

loadDB()
refreshScreen()

while true do
    local ev, _, x, y, _, player_name = event.pull(1, "touch")
    
    if currentUser and state ~= "modal_msg" and state ~= "admin_wait_scan" and not string.match(state, "admin") then
        if not ev then 
            idleTimer = idleTimer - 1
            if idleTimer <= 0 then currentUser = nil; cart = {}; state = "shop"; active_category = "ВСЕ" end
            refreshScreen()
        else idleTimer = 30 end
    end

    if ev == "touch" then
        if currentUser and currentUser.name ~= player_name then computer.beep(400, 0.1)
        else
            local action = gui.checkClick(x, y)
            if action then
                computer.beep(1000, 0.05)
                
                if action == "close_admin" then state = "shop"; refreshScreen()
                elseif action == "open_cart" then state = "cart"; refreshScreen()
                
                elseif action == "close_modal" then
                    if state == "admin_wait_scan" then
                        local stack, slot = me.peekInput()
                        if not stack then
                            state = (admin_add_target == "item") and "admin_item" or "admin_buy"
                            showMsg("ОШИБКА", slot, true) -- slot содержит сообщение об ошибке
                        else
                            -- РИСУЕМ КРАСИВЫЙ РЕДАКТОР
                            local isItem = (admin_add_target == "item")
                            local nx, ny, px, py, cx, cy, w = gui.drawEditor("ДОБАВЛЕНИЕ", stack.label, isItem)
                            
                            -- Читаем поля по очереди
                            local n = readGUIInput(nx, ny, w, stack.label)
                            local p = readGUIInput(px, py, w, "10")
                            local cat = isItem and readGUIInput(cx, cy, w, categories[2]) or "ВСЕ"
                            
                            if n == "" then n = stack.label end
                            
                            if p and tonumber(p) then
                                if isItem then
                                    local db_s = getFreeDBSlot()
                                    if db_s then
                                        me.storeToDB(slot, db_s) -- СОХРАНЯЕМ В БАЗУ ДАННЫХ
                                        table.insert(shop_items, { 
                                            name = n, price = tonumber(p), category = cat, stock = 0, 
                                            id = stack.name, orig_label = stack.label, db_slot = db_s 
                                        })
                                    else
                                        showMsg("ОШИБКА", "База данных заполнена!", true)
                                        return
                                    end
                                else
                                    table.insert(shop_buyback, { 
                                        name = n, price = tonumber(p), id = stack.name, orig_label = stack.label 
                                    })
                                end
                                saveShop()
                                state = (admin_add_target == "item") and "admin_item" or "admin_buy"
                                refreshScreen()
                            else
                                state = (admin_add_target == "item") and "admin_item" or "admin_buy"
                                showMsg("ОШИБКА", "Цена должна быть числом!", true)
                            end
                        end
                    else
                        state = "shop"; refreshScreen()
                    end
                
                elseif state == "shop" then
                    if action == "login" then
                        local is_adm = false; if config.admins and config.admins[player_name] then is_adm = true end
                        local succ, res = network.get("/users/" .. player_name)
                        local bal = 0
                        if succ and res and res ~= "null" then
                            local udata = json.decode(res)
                            if udata and udata.balance then bal = udata.balance end
                        end
                        currentUser = { name = player_name, balance = bal, isAdmin = is_adm }; idleTimer = 30; refreshScreen()
                    
                    elseif action == "logout" then currentUser = nil; cart = {}; refreshScreen()
                    elseif action == "admin_panel" then state = "admin_item"; refreshScreen()
                    elseif action:match("cat_") then active_category = action:gsub("cat_", ""); refreshScreen()
                    
                    elseif action == "sell_all" then
                        if not currentUser then showMsg("ОШИБКА", "Авторизуйтесь!", true)
                        else
                            local success, msg, earned = me.sellAll(shop_buyback)
                            if success then 
                                currentUser.balance = currentUser.balance + earned; saveUser()
                                showMsg("УСПЕХ", msg .. " +" .. earned .. " ЭМ", false)
                            else showMsg("ОШИБКА", msg, true) end
                        end
                        
                    elseif action:match("buy_") or action:match("cart_") then
                        if not currentUser then showMsg("ОШИБКА", "Авторизуйтесь!", true)
                        else
                            local idx = tonumber(action:match("%d+"))
                            local filtered = {}
                            for _, item in ipairs(shop_items) do
                                if active_category == "ВСЕ" or item.category == active_category then table.insert(filtered, item) end
                            end
                            selectedItem = filtered[idx]
                            selectedQty = 1
                            isCartMode = (action:match("cart_") ~= nil)
                            state = "modal_qty"; refreshScreen()
                        end
                    end
                
                elseif state == "modal_qty" then
                    if action == "qty_add1" then selectedQty = selectedQty + 1
                    elseif action == "qty_sub1" then selectedQty = selectedQty - 1
                    elseif action == "qty_add10" then selectedQty = selectedQty + 10
                    elseif action == "qty_sub10" then selectedQty = selectedQty - 10
                    elseif action == "confirm_cart" then
                        table.insert(cart, {item = selectedItem, qty = selectedQty}); state = "shop"; refreshScreen()
                    elseif action == "confirm_buy" then
                        local cost = selectedItem.price * selectedQty
                        if selectedItem.stock < selectedQty then showMsg("ОШИБКА", "Не хватает товара в МЭ!", true)
                        elseif currentUser.balance < cost then showMsg("ОШИБКА", "Мало ЭМ!", true)
                        else
                            currentUser.balance = currentUser.balance - cost
                            saveUser(); saveShop()
                            showMsg("ОПЛАТА", "Предметы добавлены в заказ!", false)
                        end
                    end
                    if selectedQty < 1 then selectedQty = 1 end
                    if selectedQty > 64 then selectedQty = 64 end
                    if state == "modal_qty" then refreshScreen() end
                
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
                                cart = {}
                                saveUser(); saveShop()
                                showMsg("ОПЛАТА", "Покупки успешно оформлены!", false)
                            end
                        end
                    end

                elseif string.match(state, "admin") then
                    if action == "adm_cat" then state = "admin_cat"; refreshScreen()
                    elseif action == "adm_item" then state = "admin_item"; refreshScreen()
                    elseif action == "adm_buy" then state = "admin_buy"; refreshScreen()
                    
                    elseif action == "adm_add" then
                        if state == "admin_cat" then
                            -- Для категорий оставим старый ввод (это редко нужно)
                            component.gpu.setBackground(0x000000); term.clear()
                            print("Введите название новой категории:"); io.write("> ")
                            local cat = io.read()
                            if cat and cat ~= "" then table.insert(categories, cat); saveShop() end
                            refreshScreen()
                        elseif state == "admin_item" or state == "admin_buy" then
                            admin_add_target = (state == "admin_item") and "item" or "buyback"
                            state = "admin_wait_scan"
                            gui.drawNotification("СКАНИРОВАНИЕ", "Положите 1 предмет в сундук и нажмите ОК", false)
                        end
                        
                    elseif action:match("adm_del_") then
                        local idx = tonumber(action:match("%d+"))
                        if state == "admin_cat" then table.remove(categories, idx)
                        elseif state == "admin_item" then table.remove(shop_items, idx)
                        elseif state == "admin_buy" then table.remove(shop_buyback, idx) end
                        saveShop(); refreshScreen()
                        
                    elseif action:match("adm_edit_") then
                        -- РЕДАКТИРОВАНИЕ ТЕЖЕ КРАСИВЫМ ОКНОМ
                        local idx = tonumber(action:match("%d+"))
                        if state == "admin_item" then
                            local itm = shop_items[idx]
                            local nx, ny, px, py, cx, cy, w = gui.drawEditor("РЕДАКТИРОВАНИЕ", itm.orig_label or itm.name, true)
                            local n = readGUIInput(nx, ny, w, itm.name)
                            local p = readGUIInput(px, py, w, tostring(itm.price))
                            local cat = readGUIInput(cx, cy, w, itm.category)
                            if n ~= "" then itm.name = n end
                            if tonumber(p) then itm.price = tonumber(p) end
                            if cat ~= "" then itm.category = cat end
                        elseif state == "admin_buy" then
                            local itm = shop_buyback[idx]
                            local nx, ny, px, py, _, _, w = gui.drawEditor("РЕДАКТИРОВАНИЕ", itm.orig_label or itm.name, false)
                            local n = readGUIInput(nx, ny, w, itm.name)
                            local p = readGUIInput(px, py, w, tostring(itm.price))
                            if n ~= "" then itm.name = n end
                            if tonumber(p) then itm.price = tonumber(p) end
                        end
                        saveShop(); refreshScreen()
                    end
                end
            end
        end
    end
end
