-- /obmen/main.lua
local component = require("component")
local event = require("event")
local os = require("os")
local io = require("io")
local fs = require("filesystem")
local unicode = require("unicode")
local serialization = require("serialization")
local gui = require("gui")
local computer = require("computer")
local config = require("config")
local me = require("me_logic")

-- === ОТКЛЮЧАЕМ БЕЗУСЛОВНОЕ ЗАКРЫТИЕ НА CTRL+ALT+C ===
event.shouldInterrupt = function() return false end

-- === БРОНЯ ОТ ГОНКИ ЗАГРУЗКИ (Ждем 5 секунд, пока прогрузятся МЭ сеть и чанки) ===
os.sleep(5)

local me_ok, me_msg = me.init()
local trades = {}
local state = "main"
local ed_data = {}
local adminPage = 1
local adminMaxPage = 1
local isAdminMode = false
local isChestFull = false

-- Переменные для анти-спама логов
local last_err_msg = ""
local last_err_time = 0

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

local function getRealTime()
    local tz = tonumber(config.timezone) or 0
    local tmp_file = "/home/HostTime.tmp"
    local file = io.open(tmp_file, "w")
    if file then
        file:write(""); file:close()
        local lastModifiedMs = fs.lastModified(tmp_file)
        fs.remove(tmp_file)
        if lastModifiedMs and lastModifiedMs > 0 then
            return formatUnixTime(math.floor(lastModifiedMs / 1000) + (tz * 3600))
        end
    end
    return os.date("%Y-%m-%d %H:%M:%S") .. " (Игр.)"
end

local function loadLogsLocal()
    local logs = {}
    local f = io.open("/home/obmen_logs.txt", "r")
    if f then
        for line in f:lines() do table.insert(logs, line) end
        f:close()
    end
    local res = {}
    local start = math.max(1, #logs - 150)
    for i = #logs, start, -1 do table.insert(res, logs[i]) end
    return res
end

local function writeLog(action, details)
    local log_line = string.format("[%s] %s | %s", getRealTime(), action, details)
    local f = io.open("/home/obmen_logs.txt", "a")
    if f then f:write(log_line .. "\n"); f:close() end
    
    local size = fs.size("/home/obmen_logs.txt")
    if size and size > 50000 then
        local logs = loadLogsLocal()
        local fw = io.open("/home/obmen_logs.txt", "w")
        if fw then
            for i = #logs, 1, -1 do fw:write(logs[i] .. "\n") end
            fw:close()
        end
    end
end

local function loadTrades()
    local f = io.open("/home/trades.cfg", "r")
    if f then
        local data = f:read("*a")
        if data and data ~= "" then trades = serialization.unserialize(data) or {} end
        f:close()
    end
end

local function saveTrades()
    local f = io.open("/home/trades.cfg", "w")
    if f then f:write(serialization.serialize(trades)); f:close() end
end

local function refreshScreen()
    if state == "main" then 
        gui.drawMain(trades, isChestFull)
    elseif string.match(state, "admin") and state ~= "admin_wait_scan" then
        local list = (state == "admin_trades") and trades or loadLogsLocal()
        
        local _, h = component.gpu.getResolution()
        local isLogs = (state == "admin_logs")
        local perPage = isLogs and (h - 15) or math.floor((h - 15) / 2)
        
        local maxPage = math.ceil(#list / perPage); if maxPage < 1 then maxPage = 1 end
        adminMaxPage = maxPage
        if adminPage > maxPage then adminPage = maxPage end
        
        local pItems = {}
        for i = (adminPage - 1) * perPage + 1, math.min(adminPage * perPage, #list) do
            table.insert(pItems, {item = list[i], origIdx = (state == "admin_trades" and i or nil)})
        end
        gui.drawAdmin(state:gsub("admin_", ""), pItems, adminPage, maxPage)
    elseif state == "admin_wait_scan" then 
        gui.drawNotification(ed_data.title, ed_data.msg, ed_data.err)
    elseif state == "editor" then 
        gui.drawEditorModal(ed_data)
    elseif state == "modal_msg" then 
        gui.drawNotification(ed_data.title, ed_data.msg, ed_data.err) 
    end
end

loadTrades()
if me_ok then pcall(me.updateStock, trades) end
refreshScreen()
if not me_ok then ed_data={title="ОШИБКА СИСТЕМЫ", msg=me_msg, err=true}; state="modal_msg"; refreshScreen() end

local tickTimer = 0
local stockTimer = 0

-- =========================================================================
-- ВЕСЬ ТЕЛО ЦИКЛА ВЫНЕСЕНО В ФУНКЦИЮ ДЛЯ ЗАЩИТЫ ОТ ВЫГРУЗКИ ЧАНКОВ
-- =========================================================================
local function obmenTick()
    local ev, _, arg1, arg2, arg3, arg4, arg5 = event.pull(0.05)
    
    -- ПЕРЕХВАТЧИК ЗАКРЫТИЯ ПРИЛОЖЕНИЯ
    if ev == "interrupted" then
        if isAdminMode then
            component.gpu.setBackground(0x000000)
            component.gpu.setForeground(0xFFFFFF)
            require("term").clear()
            print("Программа завершена администратором.")
            error("ADMIN_EXIT") -- Генерируем кодовое слово для выхода
        else
            ed_data = {title="ОТКАЗ В ДОСТУПЕ", msg="Войдите как админ, чтобы закрыть!", err=true}
            state = "modal_msg"
            refreshScreen()
        end
        return
    end
    
    if not ev then 
        if state == "main" and me_ok then
            tickTimer = tickTimer + 0.05
            if tickTimer >= 0.1 then 
                tickTimer = 0
                local found, ok, msg, actual_out, t, input_qty = me.processOneExchange(trades)
                
                if found then
                    local needs_redraw = false
                    
                    if ok then
                        if isChestFull then 
                            isChestFull = false
                            needs_redraw = true 
                        end
                        
                        t.stock = t.stock - actual_out
                        needs_redraw = true
                        
                        if actual_out == (input_qty * t.ratio) then
                            writeLog("ОБМЕН", string.format("%d %s -> %d %s", input_qty, t.in_label, actual_out, t.out_label))
                        else
                            writeLog("ВНИМАНИЕ", string.format("Взято %d %s, выдано %d %s. %s", input_qty, t.in_label, actual_out, t.out_label, msg))
                        end
                        
                        last_err_msg = "" -- Сброс спам-фильтра
                    else
                        local is_full_err = msg:match("забит") or msg:match("переполнен")
                        if is_full_err then
                            if not isChestFull then
                                isChestFull = true
                                needs_redraw = true
                            end
                        end
                        
                        -- АНТИ-СПАМ ФИЛЬТР ЛОГОВ (пишем ошибку не чаще 1 раза в 10 сек)
                        if msg ~= last_err_msg or (computer.uptime() - last_err_time) > 10 then
                            writeLog("СБОЙ", string.format("Отмена для %s: %s", t.in_label, msg))
                            last_err_msg = msg
                            last_err_time = computer.uptime()
                        end
                    end
                    
                    if needs_redraw then refreshScreen() end
                end
            end
            
            stockTimer = stockTimer + 0.05
            if stockTimer >= 5.0 then
                stockTimer = 0
                
                -- Сохраняем старые данные для сравнения
                local old_stocks = {}
                for i, tr in ipairs(trades) do old_stocks[i] = tr.stock end
                
                pcall(me.updateStock, trades)
                
                local changed = false
                
                -- Проверяем, изменились ли цифры склада
                for i, tr in ipairs(trades) do
                    if old_stocks[i] ~= tr.stock then changed = true; break end
                end
                
                -- Проверяем, нужно ли показать/скрыть баннер, если никто ничего не кидает
                if me_ok then
                    local ok_full, full = pcall(me.isOutputChestFull)
                    if ok_full and full ~= isChestFull then
                        isChestFull = full
                        changed = true
                    end
                end
                
                -- ПЕРЕРИСОВЫВАЕМ ЭКРАН ТОЛЬКО ЕСЛИ ЧТО-ТО ВИЗУАЛЬНО ПОМЕНЯЛОСЬ!
                if changed then refreshScreen() end 
            end
        end
    else
        if ev == "touch" then
            local action = gui.checkClick(arg1, arg2)
            if action then
                computer.beep(1000, 0.05)
                local player = arg4
                local is_adm = (config.admins and config.admins[player])
                
                if action == "admin_login" then
                    if is_adm then isAdminMode = true; state = "admin_trades"; adminPage = 1; refreshScreen()
                    else ed_data = {title="ОШИБКА", msg="У вас нет прав администратора!", err=true}; state = "modal_msg"; refreshScreen() end
                
                elseif action == "close_admin" then isAdminMode = false; state = "main"; refreshScreen()
                elseif action == "adm_trades" then state = "admin_trades"; adminPage = 1; refreshScreen()
                elseif action == "adm_logs" then state = "admin_logs"; adminPage = 1; refreshScreen()
                
                elseif action == "adm_prev" then
                    if adminPage > 1 then adminPage = adminPage - 1; refreshScreen() end
                elseif action == "adm_next" then
                    if adminPage < adminMaxPage then adminPage = adminPage + 1; refreshScreen() end
                
                elseif action == "adm_add" then
                    ed_data = {title="СКАНИРОВАНИЕ", msg="Положите руду в ЛЕВЫЙ сундук, а слиток - в ПРАВЫЙ", err=false}
                    state = "admin_wait_scan"; refreshScreen()
                
                elseif action == "close_modal" then
                    if state == "admin_wait_scan" then
                        local in_st, out_st = me.getScanItems()
                        if not out_st then ed_data = {title="ОШИБКА", msg="В ПРАВОМ сундуке нет слитка!", err=true}; state = "modal_msg"
                        elseif not in_st then ed_data = {title="ОШИБКА", msg="В ЛЕВОМ сундуке нет руды!", err=true}; state = "modal_msg"
                        else
                            ed_data = {
                                input = {name = in_st.name, damage = in_st.damage},
                                output = {name = out_st.name, damage = out_st.damage},
                                in_label = in_st.label, out_label = out_st.label, ratio = "1", focus = "ratio"
                            }
                            state = "editor"
                        end
                        refreshScreen()
                    else state = isAdminMode and "admin_trades" or "main"; refreshScreen() end
                
                elseif state == "editor" then
                    if action == "focus_in" then ed_data.focus = "in_label"; refreshScreen()
                    elseif action == "focus_out" then ed_data.focus = "out_label"; refreshScreen()
                    elseif action == "focus_ratio" then ed_data.focus = "ratio"; refreshScreen()
                    elseif action == "ed_cancel" then state = "admin_trades"; refreshScreen()
                    elseif action == "ed_save" then
                        local r = tonumber(ed_data.ratio)
                        if not r or r <= 0 then ed_data={title="ОШИБКА", msg="Укажите корректное число!", err=true}; state="modal_msg"
                        else
                            table.insert(trades, {input=ed_data.input, output=ed_data.output, in_label=ed_data.in_label, out_label=ed_data.out_label, ratio=r, stock=0})
                            saveTrades(); pcall(me.updateStock, trades); state = "admin_trades"
                        end
                        refreshScreen()
                    end
                elseif action:match("adm_del_") then
                    local idx = tonumber(action:match("%d+"))
                    table.remove(trades, idx); saveTrades(); refreshScreen()
                end
            end
        elseif ev == "key_down" and state == "editor" then
            local char, code = arg1, arg2
            local val = ed_data[ed_data.focus]
            if code == 14 then if unicode.len(val) > 0 then val = unicode.sub(val, 1, -2) end
            elseif char >= 32 then val = val .. unicode.char(char) end
            ed_data[ed_data.focus] = val; refreshScreen()
        elseif ev == "scroll" then
            local dir = arg4
            if string.match(state, "admin") then
                if dir > 0 and adminPage > 1 then adminPage = adminPage - 1; refreshScreen()
                elseif dir < 0 and adminPage < adminMaxPage then adminPage = adminPage + 1; refreshScreen() end
            end
        end
    end
end

-- =========================================================================
-- СТОРОЖЕВОЙ ПЕС (WATCHDOG) С ВОЗМОЖНОСТЬЮ ВЫХОДА ДЛЯ АДМИНА
-- =========================================================================
while true do
    local ok, err = pcall(obmenTick)
    if not ok then
        -- ПРОПУСКАЕМ АДМИНА В КОНСОЛЬ:
        if tostring(err):match("ADMIN_EXIT") then break end
        
        local f = io.open("/home/obmen_crash.log", "a")
        if f then 
            f:write(os.date("%Y-%m-%d %H:%M:%S") .. " | FATAL CRASH: " .. tostring(err) .. "\n")
            f:close() 
        end
        
        os.sleep(3)
        computer.shutdown(true) 
    end
end
