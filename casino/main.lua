-- /lua/casino_main.lua
local component = require("component")
local event = require("event")
local os = require("os")
local io = require("io")
local fs = require("filesystem")
local unicode = require("unicode")
local gui = require("casino_gui")
local computer = require("computer")
local config = require("casino_config")
local me = require("casino_me_logic")
local network = require("casino_network")
local json = require("casino_json")

-- === ОТКЛЮЧАЕМ БЕЗУСЛОВНОЕ ЗАКРЫТИЕ НА CTRL+ALT+C ===
event.shouldInterrupt = function() return false end

-- === ИНИЦИАЛИЗАЦИЯ ИСТИННОГО РАНДОМА ===
math.randomseed(os.time() + (os.clock() * 1000))

local me_ok, me_msg = me.init()
local CUR = config.currency_name or "ЭМ"

local OWNER_NAME = "Администратор"
if config.admins then for k, v in pairs(config.admins) do OWNER_NAME = k; break end end

local casino_cases = {}
local users_db = {} 
local casino_name = "КАЗИНО"

local currentUser = nil
local idleTimer = 0
local msgTimer = 0
local syncTimer = 15
local state = "casino"
local ed_data = {}
local log_filter = ""
local selectedCaseIndex = nil
local selectedItemIndex = nil
local roulette_strip = {}
local roulette_winner = nil
local roulette_start_time = 0
local roulette_duration = 7 -- секунды
local roulette_target_pos = 0
local roulette_start_pos = 0

local currentPage = 1
local ITEMS_PER_PAGE = 6
local adminPage = 1
local ADMIN_ITEMS_PER_PAGE = 17

-- === КАСТОМНЫЙ КАЛЕНДАРЬ ===
local function formatUnixTime(unix)
    local z = math.floor(unix / 86400) + 719468
    local era = math.floor((z >= 0 and z or (z - 146096)) / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - doe / 1460 + doe / 36524 - doe / 146096) / 365)
    local y = yoe + era * 400
    local doy = doe - math.floor((365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100)))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp + (mp < 10 and 3 or -9)
    y = y + (m <= 2 and 1 or 0)
    
    local h = math.floor((unix % 86400) / 3600)
    local min = math.floor((unix % 3600) / 60)
    local s = math.floor(unix % 60)
    
    return string.format("%04d-%02d-%02d %02d:%02d:%02d", y, m, d, h, min, s)
end

-- === ТРЮК С ФАЙЛОМ ДЛЯ РЕАЛЬНОГО ВРЕМЕНИ ===
local function getRealTime()
    local tz = tonumber(config.timezone) or 0
    local tmp_file = "/home/HostTime.tmp"
    
    local file = io.open(tmp_file, "w")
    if file then
        file:write("")
        file:close()
        
        local lastModifiedMs = fs.lastModified(tmp_file)
        fs.remove(tmp_file)
        
        if lastModifiedMs and lastModifiedMs > 0 then
            local current_unix = math.floor(lastModifiedMs / 1000)
            return formatUnixTime(current_unix + (tz * 3600))
        end
    end
    
    return os.date("%Y-%m-%d %H:%M:%S") .. " (Игр.)"
end

local function writeLog(action, user, details)
    local time_str = getRealTime()
    local log_line = string.format("[%s] %s | %s | %s", time_str, action, user, details)
    
    local f = io.open("/home/casino_logs.txt", "a")
    if f then f:write(log_line .. "\n"); f:close() end
    
    if config.use_database and component.isAvailable("internet") then
        pcall(function() 
            network.post("/logs", json.encode({ time = time_str, action = action, user = user, details = details })) 
        end)
    end

    local size = fs.size("/home/casino_logs.txt")
    if size and size > 200000 then 
        local lines = {}
        local fr = io.open("/home/casino_logs.txt", "r")
        if fr then
            for line in fr:lines() do table.insert(lines, line) end
            fr:close()
        end
        
        local fw = io.open("/home/casino_logs.txt", "w")
        if fw then
            local start_idx = math.max(1, #lines - 200)
            for i = start_idx, #lines do
                fw:write(lines[i] .. "\n")
            end
            fw:close()
        end
    end
end

local function loadLogsLocal(filter)
    local logs = {}
    local f = io.open("/home/casino_logs.txt", "r")
    if f then
        for line in f:lines() do 
            if not filter or filter == "" or string.find(unicode.lower(line), unicode.lower(filter), 1, true) then
                table.insert(logs, line)
            end
        end
        f:close()
    end
    local res = {}
    local count = #logs
    local start = math.max(1, count - 150)
    for i = count, start, -1 do table.insert(res, logs[i]) end
    if #res == 0 then table.insert(res, "Логи не найдены или не соответствуют фильтру...") end
    return res
end

local function loadUsersLocal()
    local f = io.open("/home/casino_users.json", "r")
    if f then
        local data = f:read("*a")
        if data and data ~= "" then users_db = json.decode(data) or {} end
        f:close()
    end
end

local function loadCasinoLocal()
    local f = io.open("/home/casino_data.json", "r")
    if f then
        local data = f:read("*a")
        f:close()
        if data and data ~= "" then
            local parsed = json.decode(data)
            if parsed then
                if parsed.cases then casino_cases = parsed.cases end
                if parsed.casino_name then casino_name = parsed.casino_name end
            end
        end
    end
end

local function saveUser()
    if not currentUser then return end
    if not users_db[currentUser.name] then users_db[currentUser.name] = { balance = 0, spent = 0 } end
    users_db[currentUser.name].balance = currentUser.balance
    users_db[currentUser.name].spent = currentUser.spent
    
    local f = io.open("/home/casino_users.json", "w")
    if f then f:write(json.encode(users_db)); f:close() end
    
    if config.use_database and component.isAvailable("internet") then
        pcall(function() network.patch("/users/" .. currentUser.name, json.encode({ balance = currentUser.balance, spent = currentUser.spent })) end)
    end
end

local function saveCasino()
    local data = { cases = casino_cases, casino_name = casino_name }
    local encoded = json.encode(data)
    local f = io.open("/home/casino_data.json", "w")
    if f then f:write(encoded); f:close() end
    
    if config.use_database and component.isAvailable("internet") then
        pcall(function() network.put("/data", encoded) end)
    end
end

local function loadDB()
    if config.use_database and component.isAvailable("internet") then
        local succ_data, res_data = network.get("/data")
        if succ_data and res_data and res_data ~= "null" then
            local parsed = json.decode(res_data)
            if parsed then
                if parsed.cases then casino_cases = parsed.cases end
                if parsed.casino_name then casino_name = parsed.casino_name end
            end
        else loadCasinoLocal() end
        
        local succ_u, res_u = network.get("/users")
        if succ_u and res_u and res_u ~= "null" then
            local parsed_u = json.decode(res_u)
            if parsed_u then users_db = parsed_u end
        else loadUsersLocal() end
    else
        loadCasinoLocal()
        loadUsersLocal()
    end
end

local function getTop3Players()
    local sorted = {}
    for name, data in pairs(users_db) do table.insert(sorted, {name = name, spent = data.spent or 0}) end
    table.sort(sorted, function(a, b) return a.spent > b.spent end)
    local top3 = {}
    for i = 1, math.min(3, #sorted) do table.insert(top3, sorted[i]) end
    return top3
end

local function getPageItems(list, perPage)
    local maxPage = math.ceil(#list / perPage)
    if maxPage < 1 then maxPage = 1 end
    if currentPage > maxPage then currentPage = maxPage end
    local pageData = {}
    local startIdx = (currentPage - 1) * perPage + 1
    local endIdx = math.min(startIdx + perPage - 1, #list)
    for i = startIdx, endIdx do table.insert(pageData, {item = list[i], origIdx = i}) end
    return pageData, maxPage
end

local function getAdminPageItems(list, limit)
    limit = limit or ADMIN_ITEMS_PER_PAGE
    local maxPage = math.ceil(#list / limit)
    if maxPage < 1 then maxPage = 1 end
    if adminPage > maxPage then adminPage = maxPage end
    local pageData = {}
    local startIdx = (adminPage - 1) * limit + 1
    local endIdx = math.min(startIdx + limit - 1, #list)
    for i = startIdx, endIdx do table.insert(pageData, {item = list[i], origIdx = i}) end
    return pageData, maxPage
end

local function easeOutCubic(t)
    return 1 - math.pow(1 - t, 3)
end

local function refreshScreen()
    if state == "casino" then
        gui.drawStatic(currentUser, currentUser and idleTimer or nil, getTop3Players(), casino_name)
        local pItems, maxPage = getPageItems(casino_cases, ITEMS_PER_PAGE)
        gui.drawCases(pItems, currentPage, maxPage)
        if not me_ok then component.gpu.set(2, component.gpu.getResolution(), "СИСТЕМНАЯ ОШИБКА: " .. me_msg) end
    elseif state == "admin_edit_case" then
        local case = casino_cases[selectedCaseIndex]
        gui.drawCaseEditor(case, case.items or {})
    elseif state == "admin_edit_item" then
        gui.drawItemEditor(ed_data)
    elseif string.match(state, "admin") and state ~= "admin_wait_scan" then
        local listToPass = {}
        local perPage = ADMIN_ITEMS_PER_PAGE
        if state == "admin_cases" then listToPass = casino_cases
        elseif state == "admin_logs" then 
            listToPass = loadLogsLocal(log_filter)
            perPage = 30
        end
        local pItems, maxP = getAdminPageItems(listToPass, perPage)
        gui.drawAdmin(state:gsub("admin_", ""), pItems, adminPage, maxP, log_filter)
    elseif state == "editor" then
        gui.drawStatic(currentUser, idleTimer, getTop3Players(), casino_name)
        gui.drawEditorModal(ed_data)
    end
end

local function showMsg(title, text, isError, timeout)
    state = "modal_msg"
    msgTimer = timeout or 0
    gui.drawNotification(title, text, isError)
end

-- Инициализация
loadDB()
refreshScreen()

while true do
    local ev, _, arg1, arg2, arg3, arg4, arg5 = event.pull(0.01)
    if not ev then 
        if state == "roulette" then
            local elapsed = os.clock() - roulette_start_time
            if elapsed >= roulette_duration then
                state = "casino"
                ed_data.return_to = "casino"
                local ok, msg, num_given = me.givePrize(roulette_winner.id, roulette_winner.damage, 1)
                if ok and num_given > 0 then
                    writeLog("ВЫИГРЫШ", currentUser.name, "Выиграл " .. roulette_winner.name .. " из кейса " .. ed_data.case_name)
                    showMsg("ВЫИГРЫШ!", "Вы получили: " .. roulette_winner.name, false, 5)
                else
                    currentUser.balance = currentUser.balance + ed_data.case_price
                    writeLog("ОШИБКА ВЫДАЧИ", currentUser.name, "Не удалось выдать " .. roulette_winner.name .. ". " .. msg)
                    showMsg("ОШИБКА ВЫДАЧИ", "Не удалось выдать приз. Средства возвращены. " .. msg, true, 5)
                end
                saveUser()
                roulette_strip = {}
                roulette_winner = nil
                refreshScreen()
            else
                local t = elapsed / roulette_duration
                local current_pos = roulette_start_pos + (roulette_target_pos - roulette_start_pos) * easeOutCubic(t)
                gui.drawRoulette(roulette_strip, current_pos)
            end
        else
            local shouldRefreshFull = false
            if state == "modal_msg" and msgTimer > 0 then
                msgTimer = msgTimer - 1
                if msgTimer <= 0 then 
                    if ed_data.return_to then state = ed_data.return_to; ed_data.return_to = nil else state = "casino" end
                    shouldRefreshFull = true 
                end
            end
            if currentUser and state ~= "modal_msg" and state ~= "admin_wait_scan" and not string.match(state, "editor") and not string.match(state, "admin") and state ~= "roulette" then
                idleTimer = idleTimer - 1
                if idleTimer <= 0 then 
                    currentUser = nil; state = "casino"; currentPage = 1
                    shouldRefreshFull = true
                else
                    if state == "casino" then gui.drawTick(currentUser, idleTimer) end
                end
            end
            if state == "casino" and not shouldRefreshFull then
                if config.use_database and component.isAvailable("internet") then
                    syncTimer = syncTimer - 1
                    if syncTimer <= 0 then
                        syncTimer = 15
                        loadDB() 
                        if currentUser and users_db[currentUser.name] then
                            currentUser.balance = users_db[currentUser.name].balance
                            currentUser.spent = users_db[currentUser.name].spent
                        end
                        shouldRefreshFull = true
                    end
                end
            end
            if shouldRefreshFull then refreshScreen() end
        end
    else
        if currentUser and state ~= "roulette" then idleTimer = 30 end
        if ev == "interrupted" then
            if currentUser and currentUser.isAdmin then
                component.gpu.setBackground(0x000000)
                component.gpu.setForeground(0xFFFFFF)
                require("term").clear()
                print("Программа завершена администратором: " .. currentUser.name)
                os.exit()
            else
                showMsg("ОТКАЗ В ДОСТУПЕ", "Только администратор может закрыть программу!", true, 3)
            end
        elseif ev == "key_down" and (state == "editor" or state == "admin_edit_item") then
            local char = arg1; local code = arg2
            local val
            if ed_data.focus == "name" then val = ed_data.name 
            elseif ed_data.focus == "price" then val = tostring(ed_data.price)
            elseif ed_data.focus == "chance" then val = tostring(ed_data.chance)
            end
            if val then
                if code == 14 then
                    if unicode.len(val) > 0 then val = unicode.sub(val, 1, -2) end
                elseif char >= 32 then val = val .. unicode.char(char) end
                if ed_data.focus == "name" then ed_data.name = val
                elseif ed_data.focus == "price" then ed_data.price = val
                elseif ed_data.focus == "chance" then ed_data.chance = val
                end
                refreshScreen()
            end
        elseif ev == "clipboard" and (state == "editor" or state == "admin_edit_item") then
            local text = arg1
            if ed_data.focus == "name" then ed_data.name = ed_data.name .. text
            elseif ed_data.focus == "price" then ed_data.price = tostring(ed_data.price) .. text
            elseif ed_data.focus == "chance" then ed_data.chance = tostring(ed_data.chance) .. text
            end
            refreshScreen()
        elseif ev == "scroll" and state ~= "roulette" then
            local dir = arg4
            local player_name = arg5
            if currentUser and currentUser.name ~= player_name then computer.beep(400, 0.1)
            else
                if state == "casino" then
                    if dir > 0 and currentPage > 1 then currentPage = currentPage - 1; refreshScreen()
                    elseif dir < 0 then currentPage = currentPage + 1; refreshScreen() end
                elseif string.match(state, "admin") then
                    if dir > 0 and adminPage > 1 then adminPage = adminPage - 1; refreshScreen()
                    elseif dir < 0 then adminPage = adminPage + 1; refreshScreen() end
                end
            end
        elseif ev == "touch" and state ~= "roulette" then
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
                    elseif action == "close_admin" then state = "casino"; refreshScreen()
                    elseif action == "close_modal" then 
                        if state == "admin_wait_scan" then
                            local stack, msg = me.peekInput()
                            if not stack then
                                ed_data.return_to = "admin_edit_case"
                                showMsg("ОШИБКА СКАНЕРА", msg, true, 4)
                            else
                                state = "admin_edit_item"
                                ed_data.is_new = true
                                ed_data.name = stack.label
                                ed_data.price = "0"
                                ed_data.chance = "10"
                                ed_data.orig_id = stack.name
                                ed_data.damage = stack.damage or 0
                                ed_data.focus = "name"
                                refreshScreen()
                            end
                        else
                            state = "casino"; msgTimer = 0; refreshScreen()
                        end
                    elseif action == "filter_logs" then
                        ed_data = {target = "log_filter", focus = "name", name = log_filter}
                        state = "editor"; refreshScreen()
                    elseif action == "clear_filter" then
                        log_filter = ""; adminPage = 1; refreshScreen()
                    elseif action == "adm_name" then
                        ed_data = {target = "casino_name", focus = "name", name = casino_name}
                        state = "editor"; refreshScreen()
                    elseif action:match("adm_edit_") then
                        local origIdx = tonumber(action:match("%d+"))
                        if state == "admin_cases" then
                            state = "admin_edit_case"
                            selectedCaseIndex = origIdx
                            refreshScreen()
                        end
                    elseif state == "editor" then
                        if action == "focus_name" then ed_data.focus = "name"; refreshScreen()
                        elseif action == "focus_price" then ed_data.focus = "price"; refreshScreen()
                        elseif action == "ed_cancel" then
                             state = "admin_cases"; refreshScreen()
                        elseif action == "ed_save" then
                            local p_str = tostring(ed_data.price):gsub(",", ".")
                            if ed_data.target ~= "log_filter" and (p_str == "" or not tonumber(p_str)) then showMsg("ОШИБКА", "Цена должна быть числом!", true); return end
                            if ed_data.target == "log_filter" then
                                log_filter = ed_data.name; state = "admin_logs"; adminPage = 1; refreshScreen()
                            elseif ed_data.target == "casino_name" then
                                casino_name = ed_data.name; saveCasino(); state = "admin_cases"; refreshScreen()
                            elseif ed_data.target == "add_case" then
                                table.insert(casino_cases, { name = ed_data.name, price = tonumber(p_str), items = {} })
                                writeLog("КЕЙС ДОБАВЛЕН", currentUser.name, ed_data.name .. " за " .. p_str .. " " .. CUR)
                                saveCasino(); state = "admin_cases"; adminPage = 1; refreshScreen()
                            end
                        end
                    elseif state == "admin_edit_case" then
                        if action == "back_to_admin" then state = "admin_cases"; selectedCaseIndex = nil; refreshScreen() 
                        elseif action == "case_add_item" then
                            state = "admin_wait_scan"
                            gui.drawNotification("СКАНИРОВАНИЕ", "Положите 1 предмет в сундук и нажмите ОК", false)
                        elseif action:match("case_edit_item_") then
                            selectedItemIndex = tonumber(action:match("%d+"))
                            local item = casino_cases[selectedCaseIndex].items[selectedItemIndex]
                            state = "admin_edit_item"
                            ed_data.is_new = false
                            ed_data.name = item.name
                            ed_data.price = tostring(item.price)
                            ed_data.chance = tostring(item.chance)
                            ed_data.orig_id = item.id
                            ed_data.damage = item.damage
                            ed_data.focus = "name"
                            refreshScreen()
                        elseif action:match("case_del_item_") then
                            local item_idx = tonumber(action:match("%d+"))
                            table.remove(casino_cases[selectedCaseIndex].items, item_idx)
                            saveCasino(); refreshScreen()
                        end
                    elseif state == "admin_edit_item" then
                        if action == "focus_name" then ed_data.focus = "name"
                        elseif action == "focus_price" then ed_data.focus = "price"
                        elseif action == "focus_chance" then ed_data.focus = "chance"
                        elseif action == "item_ed_cancel" then state = "admin_edit_case"
                        elseif action == "item_ed_save" then
                            -- ИСПРАВЛЕНО: вытаскиваем строку до tonumber
                            local p_str = tostring(ed_data.price):gsub(",", ".")
                            local c_str = tostring(ed_data.chance):gsub(",", ".")
                            
                            local price = tonumber(p_str)
                            local chance = tonumber(c_str)
                            
                            if not price or not chance then
                                ed_data.return_to = "admin_edit_item"
                                showMsg("ОШИБКА", "Цена и шанс должны быть числами!", true, 4)
                            else
                                local item_data = {
                                    name = ed_data.name, price = price, chance = chance,
                                    id = ed_data.orig_id, damage = ed_data.damage
                                }
                                if ed_data.is_new then
                                    table.insert(casino_cases[selectedCaseIndex].items, item_data)
                                else
                                    casino_cases[selectedCaseIndex].items[selectedItemIndex] = item_data
                                end
                                saveCasino()
                                state = "admin_edit_case"
                            end
                        end
                        refreshScreen()
                    elseif state == "casino" then
                        if action == "login" then
                            local is_adm = false; if config.admins and config.admins[player_name] then is_adm = true end
                            local bal, spent = 0, 0
                            if users_db[player_name] then 
                                bal = users_db[player_name].balance or 0
                                spent = users_db[player_name].spent or 0
                            else
                                if config.use_database and component.isAvailable("internet") then
                                    local succ, res = network.get("/users/" .. player_name)
                                    if succ and res and res ~= "null" then
                                        local udata = json.decode(res)
                                        if udata then 
                                            bal = udata.balance or 0
                                            spent = udata.spent or 0
                                        end
                                    end
                                end
                            end
                            currentUser = { name = player_name, balance = bal, spent = spent, isAdmin = is_adm }; idleTimer = 30; refreshScreen()
                        elseif action == "logout" then currentUser = nil; currentPage = 1; refreshScreen()
                        elseif action == "admin_panel" then state = "admin_cases"; adminPage = 1; refreshScreen()
                        elseif action == "deposit" then
                            if not currentUser then showMsg("ОШИБКА", "Сначала авторизуйтесь!", true)
                            else
                                local success, msg, earned = me.sellAllToBalance()
                                if success and earned > 0 then 
                                    currentUser.balance = currentUser.balance + earned; saveUser()
                                    writeLog("ПОПОЛНЕНИЕ", currentUser.name, msg .. " Зачислено: " .. earned .. " " .. CUR)
                                    showMsg("УСПЕШНО", msg .. " Зачислено: " .. earned .. " " .. CUR, false, 3)
                                else showMsg("ОШИБКА", msg, true) end
                            end
                        elseif action:match("open_case_") then
                            local case_idx = tonumber(action:match("%d+"))
                            local case = casino_cases[case_idx]
                            if not currentUser then showMsg("ОШИБКА", "Сначала авторизуйтесь!", true, 3) return end
                            if not case.items or #case.items == 0 then showMsg("ОШИБКА", "Этот кейс пуст!", true, 3) return end
                            if currentUser.balance < case.price then showMsg("ОШИБКА", "Недостаточно средств!", true, 3) return end
                            currentUser.balance = currentUser.balance - case.price
                            currentUser.spent = (currentUser.spent or 0) + case.price
                            local total_chance = 0
                            for _, item in ipairs(case.items) do total_chance = total_chance + item.chance end
                            local random_num = math.random() * total_chance
                            local cumulative_chance = 0
                            for _, item in ipairs(case.items) do
                                cumulative_chance = cumulative_chance + item.chance
                                if random_num <= cumulative_chance then
                                    roulette_winner = item
                                    break
                                end
                            end
                            if not roulette_winner then roulette_winner = case.items[#case.items] end
                            roulette_strip = {}
                            for i=1, 50 do
                                table.insert(roulette_strip, case.items[math.random(#case.items)])
                            end
                            roulette_target_pos = 40 + math.random()
                            roulette_strip[41] = roulette_winner
                            ed_data.case_name = case.name
                            ed_data.case_price = case.price
                            state = "roulette"
                            roulette_start_pos = math.random(5, 15)
                            roulette_start_time = os.clock()
                        elseif action:match("view_case_") then
                            -- TODO: Осмотр кейса
                        end
                    elseif string.match(state, "admin") then
                        if action == "adm_cases" then state = "admin_cases"; adminPage = 1; refreshScreen()
                        elseif action == "adm_logs" then state = "admin_logs"; adminPage = 1; refreshScreen()
                        elseif action == "adm_name" then ed_data = {target = "casino_name", focus = "name", name = casino_name}; state = "editor"; refreshScreen()
                        elseif action == "adm_add" then
                            if state == "admin_cases" then
                                ed_data = {target = "add_case", focus = "name", name = "Новый кейс", price = "100"}
                                state = "editor"; refreshScreen()
                            end
                        elseif action:match("adm_del_") then
                            local idx = tonumber(action:match("%d+"))
                            if state == "admin_cases" then 
                                writeLog("КЕЙС УДАЛЕН", currentUser.name, casino_cases[idx].name); 
                                table.remove(casino_cases, idx) 
                            end
                            saveCasino(); refreshScreen()
                        end
                    end
                end
            end
        end
    end
end
