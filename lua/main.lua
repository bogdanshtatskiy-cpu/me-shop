-- /lua/main.lua
local component = require("component")
local event = require("event")
local os = require("os")
local io = require("io")
local unicode = require("unicode")
local gui = require("gui")
local computer = require("computer")
local config = require("config")
local me = require("me_logic")
local network = require("network")
local json = require("json")

local me_ok, me_msg = me.init()

local OWNER_NAME = "Администратор"
if config.admins then for k, v in pairs(config.admins) do OWNER_NAME = k; break end end

local shop_items = {}
local shop_buyback = {}
local categories = {"ВСЕ", "Ресурсы", "Механизмы", "Броня"}
local users_db = {} 
local shop_name = "МЭ МАГАЗИН"

local active_category = "ВСЕ"
local currentUser = nil
local idleTimer = 0
local msgTimer = 0
local state = "shop"
local selectedItem = nil
local selectedQty = 1
local isCartMode = false
local cart = {}
local ed_data = {}

local currentPage = 1
local ITEMS_PER_PAGE = 20
local adminPage = 1
local ADMIN_ITEMS_PER_PAGE = 17

-- === ПРОБИВАЕМ БЛОКИРОВКУ ВРЕМЕНИ ===
local function getRealTime()
    local ok, res = pcall(function()
        -- Надеваем маску обычного браузера, чтобы сервер времени нас не заблокировал
        local headers = { ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" }
        -- Запрашиваем время Киева в простом текстовом формате (.txt)
        local handle = require("internet").request("http://worldtimeapi.org/api/timezone/Europe/Kiev.txt", nil, headers)
        local data = ""
        for chunk in handle do data = data .. chunk end
        return data
    end)
    
    if ok and res and res ~= "" then
        -- Вырезаем дату и время прямо из текста
        local d, t = string.match(res, "datetime: (%d%d%d%d%-%d%d%-%d%d)T(%d%d:%d%d:%d%d)")
        if d and t then return d .. " " .. t end
    end
    -- Страховка с пометкой, если сервер времени упал
    return os.date("%Y-%m-%d %H:%M:%S") .. " (Игровое)"
end

local function writeLog(action, user, details)
    local time_str = getRealTime()
    local log_line = string.format("[%s] %s | %s | %s", time_str, action, user, details)
    
    local f = io.open("/home/shop_logs.txt", "a")
    if f then f:write(log_line .. "\n"); f:close() end
    
    pcall(function() 
        network.request("POST", "/logs", json.encode({ 
            time = time_str, 
            action = action, 
            user = user, 
            details = details 
        })) 
    end)
end

local function loadUsers()
    local f = io.open("/home/users.json", "r")
    if f then
        local data = f:read("*a")
        if data and data ~= "" then users_db = json.decode(data) or {} end
        f:close()
    end
end

local function saveUser()
    if not currentUser then return end
    if not users_db[currentUser.name] then users_db[currentUser.name] = {} end
    users_db[currentUser.name].balance = currentUser.balance
    
    local f = io.open("/home/users.json", "w")
    if f then f:write(json.encode(users_db)); f:close() end
    pcall(function() network.put("/users/" .. currentUser.name, json.encode({ balance = currentUser.balance })) end)
end

local function getTop3Players()
    local sorted = {}
    for name, data in pairs(users_db) do table.insert(sorted, {name = name, balance = data.balance}) end
    table.sort(sorted, function(a, b) return a.balance > b.balance end)
    local top3 = {}
    for i = 1, math.min(3, #sorted) do table.insert(top3, sorted[i]) end
    return top3
end

local function loadShopLocal()
    local f = io.open("/home/shop_data.json", "r")
    if f then
        local data = f:read("*a")
        f:close()
        if data and data ~= "" then
            local parsed = json.decode(data)
            if parsed then
                if parsed.categories then categories = parsed.categories end
                if parsed.items then shop_items = parsed.items end
                if parsed.buyback then shop_buyback = parsed.buyback end
                if parsed.shop_name then shop_name = parsed.shop_name end
                return true
            end
        end
    end
    return false
end

local function saveShop()
    local data = { categories = categories, items = shop_items, buyback = shop_buyback, shop_name = shop_name }
    local encoded = json.encode(data)
    local f = io.open("/home/shop_data.json", "w")
    if f then f:write(encoded); f:close() end
    pcall(function() network.put("/shop", encoded) end)
end

local function loadDB()
    loadUsers()
    if not loadShopLocal() then
        local succ, res = network.get("/shop")
        if succ and res and res ~= "null" then
            local parsed = json.decode(res)
            if parsed then
                if parsed.categories then categories = parsed.categories end
                if parsed.items then shop_items = parsed.items end
                if parsed.buyback then shop_buyback = parsed.buyback end
                if parsed.shop_name then shop_name = parsed.shop_name end
                saveShop()
            end
        else saveShop() end
    end
end

local function getFreeDBSlot()
    local used = {}
    for _, item in ipairs(shop_items) do if item.db_slot then used[item.db_slot] = true end end
    for i = 1, 81 do if not used[i] then return i end end
    return nil
end

local function getPageItems()
    local filtered = {}
    for i, item in ipairs(shop_items) do
        if active_category == "ВСЕ" or item.category == active_category then 
            table.insert(filtered, {item = item, origIdx = i}) 
        end
    end
    
    local maxPage = math.ceil(#filtered / ITEMS_PER_PAGE)
    if maxPage < 1 then maxPage = 1 end
    if currentPage > maxPage then currentPage = maxPage end
    
    local pageData = {}
    local startIdx = (currentPage - 1) * ITEMS_PER_PAGE + 1
    local endIdx = math.min(startIdx + ITEMS_PER_PAGE - 1, #filtered)
    for i = startIdx, endIdx do table.insert(pageData, filtered[i]) end
    return pageData, maxPage
end

local function getAdminPageItems(list)
    local maxPage = math.ceil(#list / ADMIN_ITEMS_PER_PAGE)
    if maxPage < 1 then maxPage = 1 end
    if adminPage > maxPage then adminPage = maxPage end
    local pageData = {}
    local startIdx = (adminPage - 1) * ADMIN_ITEMS_PER_PAGE + 1
    local endIdx = math.min(startIdx + ADMIN_ITEMS_PER_PAGE - 1, #list)
    for i = startIdx, endIdx do table.insert(pageData, {item = list[i], origIdx = i}) end
    return pageData, maxPage
end

local function refreshScreen()
    if state == "shop" then
        me.updateStock(shop_items)
        gui.drawStatic(currentUser, currentUser and idleTimer or nil, #cart, getTop3Players(), shop_name)
        gui.drawCategories(categories, active_category)
        
        local pItems, maxPage = getPageItems()
        gui.drawItems(pItems, currentPage, maxPage)
        gui.drawBuybackItems(shop_buyback)
        
        if not me_ok then component.gpu.set(2, component.gpu.getResolution(), "СИСТЕМНАЯ ОШИБКА: " .. me_msg) end
        
    elseif state == "modal_qty" then
        gui.drawStatic(currentUser, idleTimer, #cart, getTop3Players(), shop_name)
        gui.drawQuantitySelector(selectedItem, selectedQty, isCartMode)
        
    elseif state == "cart" then
        gui.drawStatic(currentUser, idleTimer, #cart, getTop3Players(), shop_name)
        gui.drawCart(cart)
        
    elseif string.match(state, "admin") and state ~= "admin_wait_scan" then
        local listToPass = (state == "admin_cat") and categories or (state == "admin_item" and shop_items or shop_buyback)
        local pItems, maxP = getAdminPageItems(listToPass)
        gui.drawAdmin(state:gsub("admin_", ""), pItems, adminPage, maxP)
        
    elseif state == "editor" then
        gui.drawStatic(currentUser, idleTimer, #cart, getTop3Players(), shop_name)
        gui.drawEditorModal(ed_data, categories)
    end
end

local function showMsg(title, text, isError, timeout)
    state = "modal_msg"
    msgTimer = timeout or 0
    gui.drawNotification(title, text, isError)
end

loadDB()
refreshScreen()

while true do
    local ev, _, arg1, arg2, arg3, arg4 = event.pull(1)
    
    if not ev then 
        local shouldRefreshFull = false

        if state == "modal_msg" and msgTimer > 0 then
            msgTimer = msgTimer - 1
            if msgTimer <= 0 then state = "shop"; shouldRefreshFull = true end
        end

        if currentUser and state ~= "modal_msg" and state ~= "admin_wait_scan" and state ~= "editor" and not string.match(state, "admin") then
            idleTimer = idleTimer - 1
            if idleTimer <= 0 then 
                currentUser = nil; cart = {}; state = "shop"; active_category = "ВСЕ"; currentPage = 1
                shouldRefreshFull = true
            else
                if state == "shop" or state == "modal_qty" or state == "cart" then gui.drawTick(currentUser, idleTimer) end
            end
        end

        if state == "shop" and not shouldRefreshFull then
            me.updateStock(shop_items)
            local pItems, _ = getPageItems()
            gui.drawStockTick(pItems)
        end

        if shouldRefreshFull then refreshScreen() end
    
    else
        if currentUser then idleTimer = 30 end

        if ev == "key_down" and state == "editor" then
            local char = arg1; local code = arg2
            local val = (ed_data.focus == "name") and ed_data.name or tostring(ed_data.price)
            if code == 14 then
                if unicode.len(val) > 0 then val = unicode.sub(val, 1, -2) end
            elseif char >= 32 then val = val .. unicode.char(char) end
            if ed_data.focus == "name" then ed_data.name = val else ed_data.price = val end
            refreshScreen()
            
        elseif ev == "clipboard" and state == "editor" then
            local text = arg1
            if ed_data.focus == "name" then ed_data.name = ed_data.name .. text
            else ed_data.price = tostring(ed_data.price) .. text end
            refreshScreen()

        elseif ev == "touch" then
            local x = arg1; local y = arg2; local player_name = arg4

            if currentUser and currentUser.name ~= player_name then computer.beep(400, 0.1)
            else
                local action = gui.checkClick(x, y)
                if action then
                    computer.beep(1000, 0.05)
                    
                    if action == "page_prev" then currentPage = currentPage - 1; refreshScreen()
                    elseif action == "page_next" then currentPage = currentPage + 1; refreshScreen()
                    
                    elseif action == "adm_prev" then adminPage = adminPage - 1; refreshScreen()
                    elseif action == "adm_next" then adminPage = adminPage + 1; refreshScreen()
                    
                    elseif action == "close_admin" then state = "shop"; refreshScreen()
                    elseif action == "open_cart" then state = "cart"; refreshScreen()
                    
                    elseif action == "adm_name" then
                        ed_data = {target = "shop_name", focus = "name", name = shop_name, isItem = false}
                        state = "editor"; refreshScreen()
                        
                    elseif action:match("adm_edit_") then
                        local origIdx = tonumber(action:match("%d+"))
                        if state == "admin_cat" then
                            ed_data = {target = "edit_cat", focus = "name", name = categories[origIdx], orig_idx = origIdx}
                            state = "editor"; refreshScreen()
                        elseif state == "admin_item" then
                            local it = shop_items[origIdx]
                            ed_data = {target = "edit_item", focus = "price", name = it.name, price = tostring(it.price), cat = it.category, orig_id = it.id, damage = it.damage, orig_name = it.orig_label, orig_idx = origIdx, isItem = true}
                            state = "editor"; refreshScreen()
                        elseif state == "admin_buy" then
                            local it = shop_buyback[origIdx]
                            ed_data = {target = "edit_buyback", focus = "price", name = it.name, price = tostring(it.price), orig_id = it.id, damage = it.damage, orig_name = it.orig_label, orig_idx = origIdx, isItem = false}
                            state = "editor"; refreshScreen()
                        end
                    
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
                                ed_data.damage = stack.damage or 0
                                ed_data.name = stack.label
                                ed_data.price = ""
                                ed_data.cat = categories[2] or "ВСЕ"
                                ed_data.focus = "name"
                                ed_data.slot = slot
                                state = "editor"; refreshScreen()
                            end
                        else
                            state = "shop"; msgTimer = 0; refreshScreen()
                        end
                    
                    elseif state == "editor" then
                        if action == "focus_name" then ed_data.focus = "name"; refreshScreen()
                        elseif action == "focus_price" then ed_data.focus = "price"; refreshScreen()
                        elseif action:match("setcat_") then
                            ed_data.cat = action:gsub("setcat_", "")
                            refreshScreen()
                        elseif action == "ed_cancel" then
                            if ed_data.target == "shop_name" or ed_data.target == "edit_cat" then state = "admin_cat"
                            elseif ed_data.target == "edit_item" then state = "admin_item"
                            elseif ed_data.target == "edit_buyback" then state = "admin_buy"
                            else state = (ed_data.target == "item") and "admin_item" or "admin_buy" end
                            refreshScreen()
                            
                        elseif action == "ed_save" then
                            if ed_data.target == "shop_name" then
                                shop_name = ed_data.name
                                saveShop(); state = "admin_cat"; refreshScreen()
                                
                            elseif ed_data.target == "edit_cat" then
                                local old_name = categories[ed_data.orig_idx]
                                categories[ed_data.orig_idx] = ed_data.name
                                for _, it in ipairs(shop_items) do
                                    if it.category == old_name then it.category = ed_data.name end
                                end
                                saveShop(); state = "admin_cat"; refreshScreen()
                                
                            elseif ed_data.target == "edit_item" then
                                local p_str = tostring(ed_data.price):gsub(",", ".")
                                if p_str == "" or not tonumber(p_str) then showMsg("ОШИБКА", "Введите цену (число)!", true); return end
                                local it = shop_items[ed_data.orig_idx]
                                it.name = ed_data.name; it.price = tonumber(p_str); it.category = ed_data.cat
                                saveShop(); state = "admin_item"; refreshScreen()
                                
                            elseif ed_data.target == "edit_buyback" then
                                local p_str = tostring(ed_data.price):gsub(",", ".")
                                if p_str == "" or not tonumber(p_str) then showMsg("ОШИБКА", "Введите цену (число)!", true); return end
                                local it = shop_buyback[ed_data.orig_idx]
                                it.name = ed_data.name; it.price = tonumber(p_str)
                                saveShop(); state = "admin_buy"; refreshScreen()
                                
                            else
                                local p_str = tostring(ed_data.price):gsub(",", ".")
                                if p_str == "" or not tonumber(p_str) then
                                    showMsg("ОШИБКА", "Введите корректную цену (число)!", true)
                                else
                                    if ed_data.isItem then
                                        table.insert(shop_items, { 
                                            name = ed_data.name, price = tonumber(p_str), category = ed_data.cat, 
                                            stock = 0, id = ed_data.orig_id, damage = ed_data.damage, orig_label = ed_data.orig_name 
                                        })
                                        writeLog("ДОБАВЛЕН ТОВАР", currentUser.name, ed_data.name .. " за " .. p_str .. " ЭМ")
                                    else
                                        table.insert(shop_buyback, { 
                                            name = ed_data.name, price = tonumber(p_str), id = ed_data.orig_id, damage = ed_data.damage, orig_label = ed_data.orig_name 
                                        })
                                        writeLog("ДОБАВЛЕНА СКУПКА", currentUser.name, ed_data.name .. " по " .. p_str .. " ЭМ")
                                    end
                                    saveShop()
                                    state = (ed_data.target == "item") and "admin_item" or "admin_buy"
                                    refreshScreen()
                                end
                            end
                        end
                    
                    elseif state == "shop" then
                        if action == "login" then
                            local is_adm = false; if config.admins and config.admins[player_name] then is_adm = true end
                            local bal = 0
                            if users_db[player_name] then bal = users_db[player_name].balance
                            else
                                local succ, res = network.get("/users/" .. player_name)
                                if succ and res and res ~= "null" then
                                    local udata = json.decode(res)
                                    if udata and udata.balance then bal = udata.balance end
                                end
                            end
                            currentUser = { name = player_name, balance = bal, isAdmin = is_adm }; idleTimer = 30; refreshScreen()
                        
                        elseif action == "logout" then currentUser = nil; cart = {}; currentPage = 1; refreshScreen()
                        elseif action == "admin_panel" then state = "admin_item"; adminPage = 1; refreshScreen()
                        elseif action:match("cat_") then active_category = action:gsub("cat_", ""); currentPage = 1; refreshScreen()
                        
                        elseif action == "sell_all" then
                            if not currentUser then showMsg("ОШИБКА", "Авторизуйтесь!", true)
                            else
                                local success, msg, earned = me.sellAll(shop_buyback)
                                if success then 
                                    currentUser.balance = currentUser.balance + earned; saveUser()
                                    writeLog("ПРОДАЖА", currentUser.name, msg .. " Начислено: " .. earned .. " ЭМ")
                                    showMsg("УСПЕШНАЯ СДАЧА", msg .. " Зачислено: " .. earned .. " ЭМ", false, 3)
                                else showMsg("ОШИБКА", msg, true) end
                            end
                            
                        elseif action:match("buy_") or action:match("cart_") then
                            if not currentUser then showMsg("ОШИБКА", "Авторизуйтесь!", true)
                            else
                                local origIdx = tonumber(action:match("%d+"))
                                selectedItem = shop_items[origIdx]
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
                        elseif action == "qty_add100" then selectedQty = selectedQty + 100
                        elseif action == "qty_sub100" then selectedQty = selectedQty - 100
                        elseif action == "qty_add1000" then selectedQty = selectedQty + 1000
                        elseif action == "qty_sub1000" then selectedQty = selectedQty - 1000
                        elseif action == "confirm_cart" then
                            table.insert(cart, {item = selectedItem, qty = selectedQty}); state = "shop"; refreshScreen()
                        elseif action == "confirm_buy" then
                            local cost = selectedItem.price * selectedQty
                            if selectedItem.stock < selectedQty then showMsg("ОШИБКА", "Не хватает товара в МЭ!", true)
                            elseif currentUser.balance < cost then showMsg("ОШИБКА", "Мало ЭМ!", true)
                            else
                                local ok, msg, actual_moved = me.buyItem(selectedItem, selectedQty)
                                if ok and actual_moved and actual_moved > 0 then
                                    local actual_cost = selectedItem.price * actual_moved
                                    currentUser.balance = currentUser.balance - actual_cost
                                    saveUser(); saveShop()
                                    writeLog("ПОКУПКА", currentUser.name, "Куплено: " .. selectedItem.name .. " x" .. actual_moved .. " за " .. actual_cost .. " ЭМ")
                                    
                                    if actual_moved < selectedQty then
                                        showMsg("ВНИМАНИЕ", "Сундук полон! Выдано " .. actual_moved .. " шт. Списано: " .. actual_cost .. " ЭМ", true, 6)
                                    else
                                        showMsg("УСПЕХ", "Выдано " .. actual_moved .. " шт. за " .. actual_cost .. " ЭМ", false, 3)
                                    end
                                else showMsg("ОШИБКА ВЫДАЧИ", msg, true) end
                            end
                        end
                        if selectedQty < 1 then selectedQty = 1 end
                        if selectedQty > 64000 then selectedQty = 64000 end
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
                                    local actual_total = 0
                                    for _, ci in ipairs(cart) do
                                        local ok, msg, actual_moved = me.buyItem(ci.item, ci.qty)
                                        if ok and actual_moved and actual_moved > 0 then
                                            actual_total = actual_total + (ci.item.price * actual_moved)
                                            if actual_moved < ci.qty then all_ok = false end
                                        else
                                            all_ok = false
                                        end
                                    end
                                    
                                    currentUser.balance = currentUser.balance - actual_total
                                    cart = {}
                                    saveUser(); saveShop()
                                    writeLog("ПОКУПКА (КОРЗИНА)", currentUser.name, "Оплачена корзина на сумму " .. actual_total .. " ЭМ")
                                    
                                    if all_ok then showMsg("ОПЛАТА", "Покупки успешно выданы!", false, 3)
                                    else showMsg("ВНИМАНИЕ", "Места не хватило. Выдано частично! Списано: " .. actual_total .. " ЭМ", true, 6) end
                                end
                            end
                        end

                    elseif string.match(state, "admin") then
                        if action == "adm_cat" then state = "admin_cat"; adminPage = 1; refreshScreen()
                        elseif action == "adm_item" then state = "admin_item"; adminPage = 1; refreshScreen()
                        elseif action == "adm_buy" then state = "admin_buy"; adminPage = 1; refreshScreen()
                        elseif action == "adm_name" then
                            ed_data = {target = "shop_name", focus = "name", name = shop_name, isItem = false}
                            state = "editor"; refreshScreen()
                        elseif action == "adm_add" then
                            if state == "admin_cat" then
                                ed_data = {target = "edit_cat", focus = "name", name = "Новая категория", orig_idx = #categories + 1}
                                table.insert(categories, "Новая категория")
                                state = "editor"; refreshScreen()
                            else
                                ed_data.target = (state == "admin_item") and "item" or "buyback"
                                state = "admin_wait_scan"
                                gui.drawNotification("СКАНИРОВАНИЕ", "Положите 1 предмет в левый сундук и нажмите ОК", false)
                            end
                            
                        elseif action:match("adm_del_") then
                            local idx = tonumber(action:match("%d+"))
                            if state == "admin_cat" then table.remove(categories, idx)
                            elseif state == "admin_item" then 
                                writeLog("УДАЛЕН ТОВАР", currentUser.name, shop_items[idx].name)
                                table.remove(shop_items, idx)
                            elseif state == "admin_buy" then 
                                writeLog("УДАЛЕНА СКУПКА", currentUser.name, shop_buyback[idx].name)
                                table.remove(shop_buyback, idx) 
                            end
                            saveShop(); refreshScreen()
                        end
                    end
                end
            end
        end
    end
end
