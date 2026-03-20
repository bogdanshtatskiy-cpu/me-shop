-- /obmen/gui.lua
local component = require("component")
local term = require("term")
local unicode = require("unicode")
local gpu = component.gpu

-- Адаптация пропорций под квадратный экран
local maxW, maxH = gpu.maxResolution()
local optW = maxH * 2
if optW < maxW then
    gpu.setResolution(optW, maxH)
else
    gpu.setResolution(maxW, maxH)
end

local gui = {}
gui.buttons = {}

gui.COLORS = {
    bg = 0x111111, tileBg = 0x222222, tileHeader = 0x333333,
    text = 0xEEEEEE, label = 0x999999, good = 0x55FF55, warn = 0xFFAA00, bad = 0xFF5555,
    energy = 0x00AAFF, btn = 0x444444, btnActive = 0x006699, panel = 0x181818,
    modalGood = 0x004400, modalBad = 0x660000, inputBg = 0x000000, inputFocus = 0x444444
}

local W, H = gpu.getResolution()
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

function gui.drawMain(trades)
    gpu.setBackground(gui.COLORS.bg); term.clear(); gui.buttons = {}
    
    rect(1, 1, W, 3, gui.COLORS.panel)
    center(1, 2, W, "АВТОМАТИЧЕСКИЙ ОБМЕННИК РУД", gui.COLORS.energy, gui.COLORS.panel)
    
    gui.btn("admin_login", W - 14, 2, 12, 1, "АДМИН", gui.COLORS.btn)
    text(4, 5, "ДОСТУПНЫЕ ОБМЕНЫ (Просто положите руду в левый сундук):", gui.COLORS.warn, gui.COLORS.bg)
    
    if #trades == 0 then 
        text(4, 7, "Обменов пока нет...", gui.COLORS.label, gui.COLORS.bg)
    else
        local y = 7
        for i, t in ipairs(trades) do
            if y > H - 2 then break end -- Защита от вылезания за экран
            
            -- Подсветка строки (Зебра)
            local bg = (i % 2 == 0) and gui.COLORS.tileBg or gui.COLORS.panel
            rect(4, y, W - 8, 1, bg)
            
            local in_str = t.in_label .. " (1 шт)"
            local out_str = t.out_label .. " x" .. t.ratio
            local stock_str = "[На складе: " .. tostring(t.stock or 0) .. "]"
            
            -- Вход
            text(6, y, in_str, gui.COLORS.warn, bg)
            -- Стрелка
            text(6 + unicode.len(in_str) + 2, y, "»", gui.COLORS.label, bg)
            -- Выход
            text(6 + unicode.len(in_str) + 5, y, out_str, gui.COLORS.good, bg)
            -- Склад (Прижат к правому краю)
            text(W - 4 - unicode.len(stock_str), y, stock_str, gui.COLORS.text, bg)
            
            -- ШАГ В 2 СТРОКИ (1 строка текста + 1 пустая строка отступа)
            y = y + 2 
        end
    end
end

function gui.drawAdmin(substate, items, page, maxPage)
    gpu.setBackground(gui.COLORS.bg); term.clear(); gui.buttons = {}
    rect(1, 1, W, 3, gui.COLORS.panel); center(1, 2, W, "ПАНЕЛЬ АДМИНИСТРАТОРА", gui.COLORS.energy, gui.COLORS.panel)
    
    gui.btn("adm_trades", 4, 5, 14, 3, "ОБМЕНЫ", substate == "trades" and gui.COLORS.btnActive or gui.COLORS.btn)
    gui.btn("adm_logs", 20, 5, 14, 3, "ЛОГИ", substate == "logs" and gui.COLORS.btnActive or gui.COLORS.btn)
    gui.btn("close_admin", W - 16, 5, 14, 3, "НАЗАД", gui.COLORS.bad)

    rect(4, 9, W - 8, H - 14, gui.COLORS.panel)
    
    if items then
        if substate == "logs" then
            local y = 10
            for i, el in ipairs(items) do
                if y >= H - 5 then break end
                local str = tostring(type(el) == "table" and el.item or el)
                local actionCol = str:match("ОБМЕН") and gui.COLORS.good or gui.COLORS.bad
                local time_part, rest = str:match("(%[%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d%]) (.*)")
                
                if time_part and rest then
                    text(6, y, time_part, gui.COLORS.label, gui.COLORS.panel)
                    local startX = 6 + unicode.len(time_part) + 1
                    local maxW = W - startX - 4
                    local currentLine = ""
                    for word in string.gmatch(rest, "%S+") do
                        if unicode.len(currentLine) + unicode.len(word) + 1 > maxW then
                            text(startX, y, currentLine, actionCol, gui.COLORS.panel)
                            y = y + 1; currentLine = word
                            if y >= H - 5 then break end
                        else currentLine = currentLine == "" and word or (currentLine .. " " .. word) end
                    end
                    if currentLine ~= "" and y < H - 5 then
                        text(startX, y, currentLine, actionCol, gui.COLORS.panel); y = y + 1
                    end
                else 
                    text(6, y, unicode.sub(str, 1, W - 12), actionCol, gui.COLORS.panel); y = y + 1
                end
            end
        else
            -- КЛАССИЧЕСКИЙ ВИД АДМИНКИ С ОТСТУПАМИ
            local y = 10
            for i, el in ipairs(items) do
                if y > H - 6 then break end
                
                local bg = (i % 2 == 0) and gui.COLORS.tileBg or gui.COLORS.panel
                rect(6, y, W - 12, 1, bg)
                
                local in_str = el.item.in_label .. " (1 шт)"
                local out_str = el.item.out_label .. " x" .. el.item.ratio
                
                text(8, y, in_str, gui.COLORS.warn, bg)
                text(8 + unicode.len(in_str) + 2, y, "»", gui.COLORS.label, bg)
                text(8 + unicode.len(in_str) + 5, y, out_str, gui.COLORS.text, bg)
                
                -- Кнопка удалить
                gui.btn("adm_del_"..el.origIdx, W - 18, y, 10, 1, "УДАЛИТЬ", gui.COLORS.bad)
                
                y = y + 2 -- Отступ
            end
        end
    end
    
    local py = H - 4
    if substate == "trades" then gui.btn("adm_add", 4, py, 24, 3, "ДОБАВИТЬ ОБМЕН", gui.COLORS.good) end
    if maxPage > 1 then
        local centerP = math.floor(W / 2)
        if page > 1 then gui.btn("adm_prev", centerP - 18, py, 12, 3, "<- НАЗАД", gui.COLORS.btnActive) end
        center(centerP - 4, py + 1, 8, "Стр " .. page .. " из " .. maxPage, gui.COLORS.text, gui.COLORS.bg)
        if page < maxPage then gui.btn("adm_next", centerP + 6, py, 12, 3, "ВПЕРЕД ->", gui.COLORS.btnActive) end
    end
end

function gui.drawEditorModal(data)
    gui.buttons = {}
    local w = 70; local h = 16; local x = math.floor((W - w) / 2); local y = math.floor((H - h) / 2)
    rect(x-1, y-1, w+2, h+2, gui.COLORS.tileHeader)
    rect(x, y, w, h, gui.COLORS.tileBg); rect(x, y, w, 2, gui.COLORS.energy)
    center(x, y, w, "НАСТРОЙКА ОБМЕНА", gui.COLORS.text, gui.COLORS.energy)
    
    text(x+4, y+3, "ВХОД (Руда):", gui.COLORS.label, gui.COLORS.tileBg)
    local bgIn = (data.focus == "in_label") and gui.COLORS.inputFocus or gui.COLORS.inputBg
    gui.btn("focus_in", x+4, y+4, w-8, 1, data.in_label .. ((data.focus == "in_label") and "_" or ""), bgIn, gui.COLORS.text)
    
    text(x+4, y+6, "ВЫХОД (Слиток):", gui.COLORS.label, gui.COLORS.tileBg)
    local bgOut = (data.focus == "out_label") and gui.COLORS.inputFocus or gui.COLORS.inputBg
    gui.btn("focus_out", x+4, y+7, w-8, 1, data.out_label .. ((data.focus == "out_label") and "_" or ""), bgOut, gui.COLORS.text)
    
    text(x+4, y+9, "Сколько слитков за 1 руду (число):", gui.COLORS.text, gui.COLORS.tileBg)
    local bgRatio = (data.focus == "ratio") and gui.COLORS.inputFocus or gui.COLORS.inputBg
    gui.btn("focus_ratio", x+4, y+10, w-8, 1, data.ratio .. ((data.focus == "ratio") and "_" or ""), bgRatio, gui.COLORS.warn)
    
    gui.btn("ed_save", x + 4, y + h - 3, math.floor(w/2) - 6, 3, "СОХРАНИТЬ", gui.COLORS.good)
    gui.btn("ed_cancel", x + math.floor(w/2) + 2, y + h - 3, math.floor(w/2) - 6, 3, "ОТМЕНА", gui.COLORS.bad)
end

function gui.drawNotification(title, message, isError)
    gui.buttons = {}; local w = 60; local h = 10; local x = math.floor((W - w) / 2); local y = math.floor((H - h) / 2)
    local titleCol = isError and gui.COLORS.modalBad or gui.COLORS.modalGood
    rect(x, y, w, h, gui.COLORS.tileBg); rect(x, y, w, 2, titleCol)
    center(x, y, w, title, gui.COLORS.text, titleCol)
    center(x, y + 4, w, message, gui.COLORS.text, gui.COLORS.tileBg)
    gui.btn("close_modal", x + 20, y + h - 3, 20, 1, "ОК", gui.COLORS.btn)
end

function gui.checkClick(x, y)
    for id, b in pairs(gui.buttons) do
        if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then return id end
    end
    return nil
end

return gui
