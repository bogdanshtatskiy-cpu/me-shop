-- /lua/main.lua
local component = require("component")
local event = require("event")
local os = require("os")
local unicode = require("unicode")
local gui = require("gui")
local computer = require("computer")
local config = require("config")
local me = require("me_logic")
local network = require("network")
local json = require("json")

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

local ed_data = {}

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
    else saveShop() end
end

local function getFreeDBSlot()
    local used = {}
    for _, item in ipairs(shop_items) do if item.db_slot then used[item.db_slot] = true end end
    for i = 1, 81 do if not used[i] then return i end end
    return nil
end

local function refreshScreen()
    if state == "shop" then
        me.updateStock(shop_items)
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
        
    elseif state == "editor" then
        gui.drawStatic(currentUser, idleTimer, #cart)
        gui.drawEditorModal(ed_data, categories)
    end
end

local function showMsg(title, text, isError)
    state = "modal_msg"
    gui.drawNotification(title, text, isError)
end

loadDB()
refreshScreen()

while true do
    -- Получаем "сырые" аргументы, чтобы разобрать их правильно
    local ev, _, arg1, arg2, arg3, arg4 = event.pull(1)
    
    if currentUser and state ~= "modal_msg" and state ~= "admin_wait_scan" and state ~= "editor" and not string.match(state, "admin") then
        if not ev then 
            idleTimer = idleTimer - 1
            if idleTimer <= 0 then currentUser = nil; cart = {}; state = "shop"; active_category = "ВСЕ" end
            refreshScreen()
        else idleTimer = 30 end
    end

    -- === ОБРАБОТКА ВВОДА С КЛАВИАТУРЫ ===
    if ev == "key_down" and state == "editor" then
        local char = arg1
        local code = arg2
        local val = (ed_data.focus == "name") and ed_data.name or tostring(ed_data.price)
        
        if code == 14 then -- Нажат Backspace
            if unicode.len(val) > 0 then val = unicode.sub(val, 1, -2) end
        elseif char >= 32 then -- Нажата обычная буква или цифра
            val = val .. unicode.char(char)
        end
        
        if ed_data.focus == "name" then ed_data.name = val else ed_data.price = val end
        refreshScreen()
        
    -- === ОБРАБОТКА ВСТАВКИ ТЕКСТА (БУФЕР ОБМЕНА) ===
    elseif ev == "clipboard" and state == "editor" then
        local text = arg1
        if ed_data.focus == "name" then ed_data.name = ed_data.name .. text
        else ed_data.price = tostring(ed_data.price) .. text end
        refreshScreen()

    -- === ОБРАБОТКА КЛИКОВ ПО ЭКРАНУ ===
    elseif ev == "touch" then
        local x = arg1
        local y = arg2
        local player_name = arg4

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
                            state = (ed_data.target == "item") and "admin_item" or "admin_buy"
                            showMsg("ОШИБКА СКАНЕРА", slot, true)
                        else
                            ed_data.isItem = (ed_data.target == "item")
                            ed_data.orig_name = stack.label
                            ed_data.orig_id = stack.name
                            ed_data.name = stack.label
                            ed_data.price = ""
                            ed_data.cat = categories[2] or "ВСЕ"
                            ed_data.focus = "name"
                            ed_data.slot = slot
                            state = "editor"; refreshScreen()
                        end
                    else
                        state = "shop"; refreshScreen()
                    end
                
                elseif state == "editor" then
                    if action == "focus_name" then ed_data.focus = "name"; refreshScreen()
                    elseif action == "focus_price" then ed_data.focus = "price"; refreshScreen()
                    elseif action:match("setcat_") then
                        ed_data.cat = action:gsub("setcat_", "")
                        refreshScreen()
                    elseif action == "ed_cancel" then
                        state = (ed_data.target == "item") and "admin_item" or "admin_buy"
                        refreshScreen()
                    elseif action == "ed_save" then
                        -- Поддержка и точки, и запятой в ценах (1,5 = 1.5)
                        local p_str = tostring(ed_data.price):gsub(",", ".")
                        if p_str == "" or not tonumber(p_str) then
                            showMsg("ОШИБКА", "Введите корректную цену (число)!", true)
                        else
                            if ed_data.isItem then
                                local db_s = getFreeDBSlot()
                                if db_s then
                                    me.storeToDB(ed_data.slot, db_s)
                                    table.insert(shop_items, { 
                                        name = ed_data.name, price = tonumber(p_str), category = ed_data.cat, 
                                        stock = 0, id = ed_data.orig_id, orig_label = ed_data.orig_name, db_slot = db_s 
                                    })
                                else
                                    showMsg("ОШИБКА", "База данных заполнена!", true); return
                                end
                            else
                                table.insert(shop_buyback, { 
                                    name = ed_data.name, price = tonumber(p_str), id = ed_data.orig_id, orig_label = ed_data.orig_name 
                                })
                            end
                            saveShop()
                            state = (ed_data.target == "item") and "admin_item" or "admin_buy"
                            refreshScreen()
                        end
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
                                showMsg("УСПЕШНАЯ СДАЧА", msg .. " Зачислено: " .. earned .. " ЭМ", false)
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
                            local ok, msg = me.buyItem(selectedItem.db_slot, selectedQty)
                            if ok then
                                currentUser.balance = currentUser.balance - cost
                                saveUser(); saveShop()
                                showMsg("УСПЕХ", "Выдано " .. selectedQty .. " шт. за " .. cost .. " ЭМ", false)
                            else showMsg("ОШИБКА ВЫДАЧИ", msg, true) end
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
                                local all_ok = true
                                for _, ci in ipairs(cart) do
                                    local ok, msg = me.buyItem(ci.item.db_slot, ci.qty)
                                    if not ok then all_ok = false end
                                end
                                
                                currentUser.balance = currentUser.balance - totalCost
                                cart = {}
                                saveUser(); saveShop()
                                
                                if all_ok then showMsg("ОПЛАТА", "Покупки успешно выданы!", false)
                                else showMsg("ОШИБКА", "Оплата прошла, но некоторые предметы не выданы!", true) end
                            end
                        end
                    end

                elseif string.match(state, "admin") then
                    if action == "adm_cat" then state = "admin_cat"; refreshScreen()
                    elseif action == "adm_item" then state = "admin_item"; refreshScreen()
                    elseif action == "adm_buy" then state = "admin_buy"; refreshScreen()
                    
                    elseif action == "adm_add" then
                        if state == "admin_item" or state == "admin_buy" then
                            ed_data.target = (state == "admin_item") and "item" or "buyback"
                            state = "admin_wait_scan"
                            gui.drawNotification("СКАНИРОВАНИЕ", "Положите 1 предмет в сундук и нажмите ОК", false)
                        end
                        
                    elseif action:match("adm_del_") then
                        local idx = tonumber(action:match("%d+"))
                        if state == "admin_cat" then table.remove(categories, idx)
                        elseif state == "admin_item" then table.remove(shop_items, idx)
                        elseif state == "admin_buy" then table.remove(shop_buyback, idx) end
                        saveShop(); refreshScreen()
                    end
                end
            end
        end
    end
end
