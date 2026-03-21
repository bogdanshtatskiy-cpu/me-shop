-- /lua/casino_gui.lua
local component = require("component")
local term = require("term")
local unicode = require("unicode")
local config = require("casino_config")
local gpu = component.gpu

local gui = {}
gui.buttons = {}
local CUR = config.currency_name or "ЭМ"

gui.COLORS = {
    bg = 0x111111, tileBg = 0x222222, tileHeader = 0x333333,
    text = 0xEEEEEE, label = 0x999999, good = 0x55FF55, warn = 0xFFAA00, bad = 0xFF5555,
    energy = 0x00AAFF, btn = 0x444444, btnActive = 0x006699, panel = 0x181818,
    modalGood = 0x004400, modalBad = 0x660000, inputBg = 0x000000, inputFocus = 0x444444
}

local W, H = gpu.getResolution()
local rightColX = math.floor(W * 0.75) + 1
local rightColW = W - rightColX + 1

local function rect(x, y, w, h, col) gpu.setBackground(col); gpu.fill(x, y, w, h, " ") end
local function text(x, y, str, fg, bg) if bg then gpu.setBackground(bg) end; gpu.setForeground(fg); gpu.set(x, y, str) end
local function center(x, y, w, str, fg, bg) 
    if bg then gpu.setBackground(bg) end; gpu.fill(x, y, w, 1, " ")
    local px = x + math.floor((w - unicode.len(str))/2)
    if fg then gpu.setForeground(fg) end; gpu.set(px, y, str) 
end

function gui.btn(id, x, y, w, h, str, bg, fg) 
    local actualFg = fg or gui.COLORS.text
    if bg == gui.COLORS.good then actualFg = gui.COLORS.bg end
    rect(x, y, w, h, bg); center(x, y + math.floor(h/2), w, str, actualFg, bg)
    gui.buttons[id] = {x=x, y=y, w=w, h=h} 
end

function gui.drawStatic(user, timer, top3, casinoName)
    gpu.setBackground(gui.COLORS.bg); term.clear(); gui.buttons = {}
    rect(1, 1, rightColX - 1, 3, gui.COLORS.panel)
    center(1, 2, rightColX - 1, casinoName or "КАЗИНО", gui.COLORS.energy, gui.COLORS.panel)

    rect(rightColX, 1, rightColW, H, gui.COLORS.panel)
    
    local rY = 2
    if user then
        gui.btn("logout", rightColX + 2, rY, rightColW - 4, 3, "ВЫХОД", gui.COLORS.bad)
        rY = rY + 4
        center(rightColX, rY, rightColW, user.name, gui.COLORS.good, gui.COLORS.panel); rY = rY + 1
        center(rightColX, rY, rightColW, user.balance .. " " .. CUR, gui.COLORS.warn, gui.COLORS.panel); rY = rY + 2
        if timer then center(rightColX, rY, rightColW, "Выход через: " .. timer .. "с", gui.COLORS.label, gui.COLORS.panel) end
        rY = rY + 2
        gui.btn("deposit", rightColX + 2, rY, rightColW - 4, 3, "ПОПОЛНИТЬ СЧЕТ", gui.COLORS.good)
        rY = rY + 4
        if user.isAdmin then gui.btn("admin_panel", rightColX + 2, rY, rightColW - 4, 1, "АДМИН ПАНЕЛЬ", gui.COLORS.energy); rY = rY + 2 end
    else
        gui.btn("login", rightColX + 2, rY, rightColW - 4, 3, "АВТОРИЗАЦИЯ", gui.COLORS.good)
        rY = rY + 4
        center(rightColX, rY, rightColW, "Войдите для игры", gui.COLORS.label, gui.COLORS.panel)
        rY = rY + 3
    end

    rect(rightColX, rY, rightColW, 1, gui.COLORS.tileHeader)
    center(rightColX, rY, rightColW, "ТОП 3 ПО ТРАТАМ:", gui.COLORS.warn, gui.COLORS.tileHeader)
    rY = rY + 2
    if top3 and #top3 > 0 then
        for i, t in ipairs(top3) do
            text(rightColX + 2, rY, i .. ". " .. t.name, gui.COLORS.text, gui.COLORS.panel)
            text(rightColX + rightColW - string.len(tostring(t.spent)) - string.len(CUR) - 3, rY, t.spent .. " " .. CUR, gui.COLORS.warn, gui.COLORS.panel)
            rY = rY + 1
        end
    else
        center(rightColX, rY, rightColW, "Нет данных", gui.COLORS.label, gui.COLORS.panel); rY = rY + 1
    end
end

function gui.drawCases(pageItems, page, maxPage)
    rect(1, 5, rightColX - 1, H - 4, gui.COLORS.bg)
    local margin = 2; local cols = 3;
    local tileW = math.floor((rightColX - (cols + 1) * margin) / cols); local tileH = 8
    local row, col = 0, 0
    
    for _, pItem in ipairs(pageItems) do
        local case = pItem.item
        local id = pItem.origIdx
        local x = margin + col * (tileW + margin); local y = 5 + row * (tileH + 1)
        
        rect(x, y, tileW, tileH, gui.COLORS.tileBg)
        center(x, y, tileW, case.name, gui.COLORS.text, gui.COLORS.tileHeader)
        center(x, y + 2, tileW, "Цена:", gui.COLORS.label, gui.COLORS.tileBg)
        center(x, y + 3, tileW, case.price .. " " .. CUR, gui.COLORS.warn, gui.COLORS.tileBg)
        
        gui.btn("view_case_"..id, x + 2, y + 5, tileW - 4, 1, "ОСМОТРЕТЬ", gui.COLORS.btn)
        gui.btn("open_case_"..id, x + 2, y + 7, tileW - 4, 1, "ОТКРЫТЬ", gui.COLORS.good)
        
        col = col + 1; if col >= cols then col = 0; row = row + 1 end
    end

    local py = H - 3
    if page > 1 then gui.btn("page_prev", 2, py, 14, 3, "<- НАЗАД", gui.COLORS.btnActive) end
    center(1, py + 1, rightColX - 1, "Страница " .. page .. " из " .. maxPage, gui.COLORS.text, gui.COLORS.bg)
    if page < maxPage then gui.btn("page_next", rightColX - 16, py, 14, 3, "ВПЕРЕД ->", gui.COLORS.btnActive) end
end

function gui.drawTick(user, timer)
    if user and timer then center(rightColX, 9, rightColW, "Выход через: " .. timer .. "с   ", gui.COLORS.label, gui.COLORS.panel) end
end

function gui.drawNotification(title, message, isError)
    gui.buttons = {}; local w = 60
    
    local lines = {}
    local currentLine = ""
    for word in string.gmatch(message, "%S+") do
        if unicode.len(currentLine) + unicode.len(word) + 1 > w - 4 then
            table.insert(lines, currentLine)
            currentLine = word
        else
            currentLine = currentLine == "" and word or (currentLine .. " " .. word)
        end
    end
    if currentLine ~= "" then table.insert(lines, currentLine) end

    local h = math.max(10, 7 + #lines)
    local x = math.floor((W - w) / 2); local y = math.floor((H - h) / 2)
    local titleCol = isError and gui.COLORS.modalBad or gui.COLORS.modalGood
    
    rect(x, y, w, h, gui.COLORS.tileBg); rect(x, y, w, 2, titleCol)
    center(x, y, w, title, gui.COLORS.text, titleCol)
    
    for i, l in ipairs(lines) do center(x, y + 2 + i, w, l, gui.COLORS.text, gui.COLORS.tileBg) end
    
    gui.btn("close_modal", x + 20, y + h - 3, 20, 1, "ОК", gui.COLORS.btn)
end

function gui.drawAdmin(substate, pageItems, page, maxPage, logFilter)
    gpu.setBackground(gui.COLORS.bg); term.clear(); gui.buttons = {}
    rect(1, 1, W, 3, gui.COLORS.panel); center(1, 2, W, "ПАНЕЛЬ УПРАВЛЕНИЯ КАЗИНО", gui.COLORS.energy, gui.COLORS.panel)
    
    gui.btn("adm_cases", 2, 5, 14, 3, "КЕЙСЫ", substate == "cases" and gui.COLORS.btnActive or gui.COLORS.btn)
    gui.btn("adm_name", 17, 5, 18, 3, "ИМЯ КАЗИНО", gui.COLORS.btn)
    gui.btn("adm_logs", 36, 5, 14, 3, "ЛОГИ", substate == "logs" and gui.COLORS.btnActive or gui.COLORS.btn)
    gui.btn("close_admin", W - 16, 5, 14, 3, "ВЫЙТИ", gui.COLORS.bad)

    rect(2, 9, W - 4, H - 14, gui.COLORS.panel)
    local y = 10
    
    if pageItems then
        for _, pItem in ipairs(pageItems) do
            if y >= H - 5 then break end 
            
            local el = pItem.item
            local id = pItem.origIdx
            
            if substate == "logs" then
                local str = tostring(el)
                local actionCol = gui.COLORS.text
                if str:match("ВЫИГРЫШ") then actionCol = gui.COLORS.good
                elseif str:match("ПОПОЛНЕНИЕ") then actionCol = gui.COLORS.warn
                elseif str:match("УДАЛЕН") or str:match("ОШИБКА") then actionCol = gui.COLORS.bad end
                
                local time_part, rest = str:match("(%[%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d%]) (.*)")
                if time_part and rest then
                    text(4, y, time_part, gui.COLORS.label, gui.COLORS.panel)
                    local startX = 4 + unicode.len(time_part) + 1
                    local maxW = W - startX - 4
                    
                    local currentLine = ""
                    for word in string.gmatch(rest, "%S+") do
                        if unicode.len(currentLine) + unicode.len(word) + 1 > maxW then
                            text(startX, y, currentLine, actionCol, gui.COLORS.panel)
                            y = y + 1
                            currentLine = word
                            if y >= H - 5 then break end
                        else
                            currentLine = currentLine == "" and word or (currentLine .. " " .. word)
                        end
                    end
                    if currentLine ~= "" and y < H - 5 then
                        text(startX, y, currentLine, actionCol, gui.COLORS.panel)
                        y = y + 1
                    end
                else
                    text(4, y, unicode.sub(str, 1, W - 8), actionCol, gui.COLORS.panel)
                    y = y + 1
                end
            else
                local name = type(el) == "table" and el.name or el
                local extra = type(el) == "table" and (" (" .. el.price .. " " .. CUR .. ")") or ""

                text(4, y, name .. extra, gui.COLORS.text, gui.COLORS.panel)
                gui.btn("adm_edit_"..id, W - 28, y, 12, 1, "РЕДАКТ", gui.COLORS.warn)
                gui.btn("adm_del_"..id, W - 14, y, 12, 1, "УДАЛИТЬ", gui.COLORS.bad)
                y = y + 2
            end
        end
    end
    
    local py = H - 4
    if substate == "logs" then
        local filterText = (log_filter == nil or log_filter == "") and "ВСЕ" or unicode.sub(log_filter, 1, 12)
        gui.btn("filter_logs", 2, py, 24, 3, "ФИЛЬТР: " .. filterText, gui.COLORS.energy)
        if log_filter ~= nil and log_filter ~= "" then
            gui.btn("clear_filter", 28, py, 14, 3, "СБРОСИТЬ", gui.COLORS.bad)
        end
    else
        gui.btn("adm_add", 2, py, 24, 3, "ДОБАВИТЬ КЕЙС", gui.COLORS.good)
    end
    
    if maxPage > 1 then
        local centerP = math.floor(W / 2)
        if page > 1 then gui.btn("adm_prev", centerP - 18, py, 12, 3, "<- НАЗАД", gui.COLORS.btnActive) end
        center(centerP - 4, py + 1, 8, "Стр " .. page .. " из " .. maxPage, gui.COLORS.text, gui.COLORS.bg)
        if page < maxPage then gui.btn("adm_next", centerP + 6, py, 12, 3, "ВПЕРЕД ->", gui.COLORS.btnActive) end
    end
end

function gui.drawEditorModal(data)
    gui.buttons = {}
    local w = 70; local h = 12
    local x = math.floor((W - w) / 2); local y = math.floor((H - h) / 2)
    
    rect(x-1, y-1, w+2, h+2, gui.COLORS.tileHeader)
    rect(x, y, w, h, gui.COLORS.tileBg); rect(x, y, w, 2, gui.COLORS.energy)
    center(x, y, w, "РЕДАКТОР КЕЙСА", gui.COLORS.text, gui.COLORS.energy)
    
    if data.target == "log_filter" then
        text(x+4, y+4, "Поиск по логам (ник, действие):", gui.COLORS.label, gui.COLORS.tileBg)
        local bgName = (data.focus == "name") and gui.COLORS.inputFocus or gui.COLORS.inputBg
        gui.btn("focus_name", x+4, y+6, w-8, 1, data.name .. ((data.focus == "name") and "_" or ""), bgName, gui.COLORS.text)
    elseif data.target == "casino_name" then
        text(x+4, y+4, "Новое название казино:", gui.COLORS.label, gui.COLORS.tileBg)
        local bgName = (data.focus == "name") and gui.COLORS.inputFocus or gui.COLORS.inputBg
        gui.btn("focus_name", x+4, y+6, w-8, 1, data.name .. ((data.focus == "name") and "_" or ""), bgName, gui.COLORS.text)
    elseif data.target == "edit_case" or data.target == "add_case" then
        text(x+4, y+4, "Название кейса:", gui.COLORS.label, gui.COLORS.tileBg)
        local bgName = (data.focus == "name") and gui.COLORS.inputFocus or gui.COLORS.inputBg
        gui.btn("focus_name", x+4, y+5, w-8, 1, data.name .. ((data.focus == "name") and "_" or ""), bgName, gui.COLORS.text)
        
        text(x+4, y+7, "Цена (число):", gui.COLORS.label, gui.COLORS.tileBg)
        local bgPrice = (data.focus == "price") and gui.COLORS.inputFocus or gui.COLORS.inputBg
        gui.btn("focus_price", x+4, y+8, w-8, 1, data.price .. ((data.focus == "price") and "_" or ""), bgPrice, gui.COLORS.warn)
    end
    
    local btnText = (data.target == "log_filter") and "ИСКАТЬ" or "СОХРАНИТЬ"
    gui.btn("ed_save", x + 4, y + h - 4, math.floor(w/2) - 6, 3, btnText, gui.COLORS.good)
    gui.btn("ed_cancel", x + math.floor(w/2) + 2, y + h - 4, math.floor(w/2) - 6, 3, "ОТМЕНА", gui.COLORS.bad)
end

function gui.drawCaseEditor(case, items)
    gpu.setBackground(gui.COLORS.bg); term.clear(); gui.buttons = {}
    local w = W - 4; local h = H - 6
    local x = 3; local y = 4

    rect(x, y, w, h, gui.COLORS.panel)
    rect(x, y, w, 2, gui.COLORS.energy)
    center(x, y, w, "РЕДАКТОР СОДЕРЖИМОГО: " .. case.name, gui.COLORS.text, gui.COLORS.energy)

    local currentY = y + 3
    if #items > 0 then
        for i, item in ipairs(items) do
            if currentY > y + h - 5 then break end
            local chanceColor = gui.COLORS.text
            if item.chance < 5 then chanceColor = config.rarity_colors.super_rare
            elseif item.chance < 20 then chanceColor = config.rarity_colors.rare
            elseif item.chance < 60 then chanceColor = config.rarity_colors.uncommon
            end
            
            text(x + 2, currentY, item.name, gui.COLORS.text, gui.COLORS.panel)
            text(x + 45, currentY, "Цена: " .. item.price, gui.COLORS.warn, gui.COLORS.panel)
            text(x + 60, currentY, "Шанс: " .. item.chance .. "%", chanceColor, gui.COLORS.panel)
            
            gui.btn("case_edit_item_"..i, x + w - 26, currentY, 12, 1, "ИЗМЕНИТЬ", gui.COLORS.warn)
            gui.btn("case_del_item_"..i, x + w - 12, currentY, 10, 1, "X", gui.COLORS.bad)
            currentY = currentY + 2
        end
    else
        center(x, y + 5, w, "В этом кейсе пока нет предметов", gui.COLORS.label, gui.COLORS.panel)
    end
    
    gui.btn("case_add_item", x + 2, y + h - 3, 20, 1, "ДОБАВИТЬ ПРЕДМЕТ", gui.COLORS.good)
    gui.btn("back_to_admin", x + w - 22, y + h - 3, 20, 1, "НАЗАД", gui.COLORS.btn)
end

function gui.drawItemEditor(data)
    gui.buttons = {}
    local w = 70; local h = 18
    local x = math.floor((W - w) / 2); local y = math.floor((H - h) / 2)
    
    rect(x-1, y-1, w+2, h+2, gui.COLORS.tileHeader)
    rect(x, y, w, h, gui.COLORS.tileBg); rect(x, y, w, 2, gui.COLORS.energy)
    center(x, y, w, data.is_new and "ДОБАВЛЕНИЕ ПРЕДМЕТА" or "РЕДАКТИРОВАНИЕ ПРЕДМЕТА", gui.COLORS.text, gui.COLORS.energy)

    text(x+4, y+3, "Системное имя: " .. data.orig_id .. ":" .. (data.damage or 0), gui.COLORS.label, gui.COLORS.tileBg)

    text(x+4, y+5, "Отображаемое имя (можно изменить):", gui.COLORS.text, gui.COLORS.tileBg)
    local bgName = (data.focus == "name") and gui.COLORS.inputFocus or gui.COLORS.inputBg
    gui.btn("focus_name", x+4, y+6, w-8, 1, data.name .. ((data.focus == "name") and "_" or ""), bgName, gui.COLORS.text)
    
    text(x+4, y+8, "Цена (для симулятора и аналитики):", gui.COLORS.text, gui.COLORS.tileBg)
    local bgPrice = (data.focus == "price") and gui.COLORS.inputFocus or gui.COLORS.inputBg
    gui.btn("focus_price", x+4, y+9, w-8, 1, data.price .. ((data.focus == "price") and "_" or ""), bgPrice, gui.COLORS.warn)

    text(x+4, y+11, "Шанс выпадения, % (число, можно дробное):", gui.COLORS.text, gui.COLORS.tileBg)
    local bgChance = (data.focus == "chance") and gui.COLORS.inputFocus or gui.COLORS.inputBg
    gui.btn("focus_chance", x+4, y+12, w-8, 1, data.chance .. ((data.focus == "chance") and "_" or ""), bgChance, gui.COLORS.good)

    gui.btn("item_ed_save", x + 4, y + h - 4, math.floor(w/2) - 6, 3, "СОХРАНИТЬ", gui.COLORS.good)
    gui.btn("item_ed_cancel", x + math.floor(w/2) + 2, y + h - 4, math.floor(w/2) - 6, 3, "ОТМЕНА", gui.COLORS.bad)
end


function gui.drawRoulette(strip, strip_pos)
    gpu.setBackground(gui.COLORS.bg); term.clear(); gui.buttons = {}
    local w, h = gpu.getResolution()

    local item_w, item_h = 16, 7
    local total_items = #strip
    
    -- Рисуем центральный указатель
    local pointer_x = math.floor(w / 2)
    gpu.setForeground(gui.COLORS.good)
    gpu.set(pointer_x, math.floor(h/2) - math.floor(item_h/2) - 1, "▼")
    gpu.set(pointer_x, math.floor(h/2) + math.floor(item_h/2) + 1, "▲")

    -- Позиция первого видимого элемента
    local start_x = pointer_x - math.floor(item_w / 2)

    for i, item in ipairs(strip) do
        local item_center_x = start_x + (i - strip_pos) * (item_w + 1)
        local item_start_x = item_center_x - math.floor(item_w / 2)
        local item_y = math.floor((h - item_h) / 2)

        -- Отсекаем невидимые элементы
        if item_start_x + item_w >= 1 and item_start_x <= w then
            local rarity_color = gui.COLORS.label
            if item.chance < 5 then rarity_color = config.rarity_colors.super_rare
            elseif item.chance < 20 then rarity_color = config.rarity_colors.rare
            elseif item.chance < 60 then rarity_color = config.rarity_colors.uncommon
            elseif item.chance < 80 then rarity_color = config.rarity_colors.common
            else rarity_color = config.rarity_colors.trash
            end

            -- Рамка с цветом редкости
            rect(item_start_x, item_y, item_w, item_h, rarity_color)
            rect(item_start_x + 1, item_y + 1, item_w - 2, item_h - 2, gui.COLORS.tileBg)

            -- Название (с обрезкой, если не влезает)
            local name = unicode.sub(item.name, 1, item_w - 2)
            center(item_start_x, item_y + 2, item_w, name, gui.COLORS.text, gui.COLORS.tileBg)

            -- Цена
            local price_str = tostring(item.price) .. " " .. CUR
            center(item_start_x, item_y + 4, item_w, price_str, gui.COLORS.warn, gui.COLORS.tileBg)
        end
    end
end

function gui.checkClick(x, y)
    for id, b in pairs(gui.buttons) do
        if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then return id end
    end
    return nil
end

return gui
