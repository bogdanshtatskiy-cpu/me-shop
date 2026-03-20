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

local me_ok, me_msg = me.init()
local trades = {}
local state = "main"
local ed_data = {}
local adminPage = 1
local isAdminMode = false

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

local function writeLog(action, details)
    local log_line = string.format("[%s] %s | %s", getRealTime(), action, details)
    local f = io.open("/home/obmen_logs.txt", "a")
    if f then f:write(log_line .. "\n"); f:close() end
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
    if state == "main" then gui.drawMain(trades)
    elseif string.match(state, "admin") and state ~= "admin_wait_scan" then
        local list = (state == "admin_trades") and trades or loadLogsLocal()
        local maxPage = math.ceil(#list / 17); if maxPage < 1 then maxPage = 1 end
        if adminPage > maxPage then adminPage = maxPage end
        local pItems = {}
        for i = (adminPage - 1) * 17 + 1, math.min(adminPage * 17, #list) do
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

while true do
    local ev, _, arg1, arg2, arg3, arg4, arg5 = event.pull(0.05)
    
    if not ev then 
        if state == "main" and me_ok then
            tickTimer = tickTimer + 0.05
            if tickTimer >= 0.1 then 
                tickTimer = 0
                local found, ok, msg, actual_out, t, input_qty = me.processOneExchange(trades)
                if found then
                    if ok then
                        t.stock = t.stock - actual_out
                        if actual_out == (input_qty * t.ratio) then
                            writeLog("ОБМЕН", string.format("%d %s -> %d %s", input_qty, t.in_label, actual_out, t.out_label))
                        else
                            writeLog("ВНИМАНИЕ", string.format("Взято %d %s, выдано %d %s. %s", input_qty, t.in_label, actual_out, t.out_label, msg))
                        end
                    else
                        writeLog("СБОЙ", string.format("Отмена для %s: %s", t.in_label, msg))
                    end
                    refreshScreen()
                end
            end
            
            stockTimer = stockTimer + 0.05
            if stockTimer >= 5.0 then
                stockTimer = 0
                pcall(me.updateStock, trades)
                refreshScreen() 
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
                
                elseif action == "adm_add" then
                    ed_data = {title="СКАНИРОВАНИЕ", msg="Положите руду в ЛЕВЫЙ сундук, а слиток - в ПРАВЫЙ", err=false}
                    state = "admin_wait_scan"; refreshScreen()
                
                elseif action == "close_modal" then
                    if state == "admin_wait_scan" then
                        local in_st, out_st = me.getScanItems()
                        if not in_st then ed_data = {title="ОШИБКА", msg="В левом сундуке пусто!", err=true}; state = "modal_msg"
                        elseif not out_st then ed_data = {title="ОШИБКА", msg="В правом сундуке пусто!", err=true}; state = "modal_msg"
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
                elseif dir < 0 then adminPage = adminPage + 1; refreshScreen() end
            end
        end
    end
end
