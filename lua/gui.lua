-- /lua/gui.lua
local component = require("component")
local term = require("term")
local unicode = require("unicode")
local gpu = component.gpu

local gui = {}
gui.buttons = {}

-- Цветовая палитра (из твоего кода)
local COLORS = {
    bg = 0x111111, tileBg = 0x222222, tileHeader = 0x333333,
    text = 0xEEEEEE, label = 0x999999,
    good = 0x55FF55, warn = 0xFFAA00, bad = 0xFF5555,
    energy = 0x00AAFF, btn = 0x444444, btnActive = 0x006699
}

local W, H = gpu.getResolution()

-- Базовые функции отрисовки
local function rect(x, y, w, h, col) gpu.setBackground(col); gpu.fill(x, y, w, h, " ") end
local function text(x, y, str, fg, bg) if bg then gpu.setBackground(bg) end; gpu.setForeground(fg); gpu.set(x, y, str) end
local function center(x, y, w, str, fg, bg) 
    if bg then gpu.setBackground(bg) end; gpu.fill(x, y, w, 1, " ")
    local px = x + math.floor((w - unicode.len(str))/2)
    if fg then gpu.setForeground(fg) end; gpu.set(px, y, str) 
end

function gui.btn(id, x, y, w, h, str, bg, fg) 
    rect(x, y, w, h, bg)
    center(x, y + math.floor(h/2), w, str, fg or COLORS.text, bg)
    gui.buttons[id] = {x=x, y=y, w=w, h=h} 
end

-- Отрисовка статического каркаса
function gui.drawStatic(user)
    gpu.setBackground(COLORS.bg)
    term.clear()
    gui.buttons = {} -- Очищаем старые кнопки

    -- Верхняя панель (Шапка)
    rect(1, 1, W, 3, 0x181818)
    text(3, 2, "МЭ МАГАЗИН v1.0", COLORS.energy, 0x181818)
    
    if user then
        text(W - 40, 2, "Игрок: " .. user.name, COLORS.good, 0x181818)
        text(W - 20, 2, "Баланс: " .. user.balance .. " ЭМ", COLORS.warn, 0x181818)
        gui.btn("logout", W - 10, 1, 10, 3, "ВЫХОД", COLORS.bad)
    else
        gui.btn("login", W - 15, 1, 15, 3, "АВТОРИЗАЦИЯ", COLORS.good)
    end

    -- Скрытая кнопка админа (правый верхний угол, невидимая)
    gui.buttons["admin_panel"] = {x=W-2, y=1, w=2, h=1}

    -- Панель корзины (Справа)
    local cartX = math.floor(W * 0.75) + 1
    local cartW = W - cartX + 1
    rect(cartX, 4, cartW, H - 3, 0x181818)
    center(cartX, 5, cartW, "КОРЗИНА", COLORS.text, 0x181818)
    rect(cartX, 6, cartW, 1, COLORS.label)
end

-- Отрисовка витрины товаров (Сетка)
function gui.drawItems(items)
    local cartX = math.floor(W * 0.75)
    local margin = 2
    local cols = 3
    local tileW = math.floor((cartX - (cols + 1) * margin) / cols)
    local tileH = 7
    
    local row, col = 0, 0
    for i, item in ipairs(items) do
        local x = margin + col * (tileW + margin)
        local y = 5 + row * (tileH + margin)
        
        rect(x, y, tileW, tileH, COLORS.tileBg)
        rect(x, y, tileW, 2, COLORS.tileHeader)
        center(x, y, tileW, item.name, COLORS.text, COLORS.tileHeader)
        
        text(x + 2, y + 3, "Цена: " .. item.price .. " ЭМ", COLORS.warn, COLORS.tileBg)
        text(x + 2, y + 4, "В наличии: " .. (item.stock or 0), COLORS.label, COLORS.tileBg)
        
        gui.btn("buy_"..i, x + 1, y + 5, math.floor(tileW/2)-1, 1, "КУПИТЬ", COLORS.good)
        gui.btn("sell_"..i, x + math.floor(tileW/2) + 1, y + 5, math.floor(tileW/2)-1, 1, "ПРОДАТЬ", COLORS.energy)

        col = col + 1
        if col >= cols then col = 0; row = row + 1 end
    end
end

-- Обработчик кликов
function gui.checkClick(x, y)
    for id, b in pairs(gui.buttons) do
        if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
            return id
        end
    end
    return nil
end

return gui
