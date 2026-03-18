-- /lua/gui.lua
local component = require("component")
local term = require("term")
local unicode = require("unicode")
local gpu = component.gpu

local gui = {}
gui.buttons = {}

local COLORS = {
    bg = 0x111111, tileBg = 0x222222, tileHeader = 0x333333,
    text = 0xEEEEEE, label = 0x999999,
    good = 0x55FF55, warn = 0xFFAA00, bad = 0xFF5555,
    energy = 0x00AAFF, btn = 0x444444, btnActive = 0x006699,
    panel = 0x181818
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
    rect(x, y, w, h, bg)
    center(x, y + math.floor(h/2), w, str, fg or COLORS.text, bg)
    gui.buttons[id] = {x=x, y=y, w=w, h=h} 
end

-- === ОТРИСОВКА КАРКАСА И ИНФО ИГРОКА ===
function gui.drawStatic(user)
    gpu.setBackground(COLORS.bg)
    term.clear()
    gui.buttons = {}

    -- Верхняя шапка (Логотип)
    rect(1, 1, rightColX - 1, 3, COLORS.panel)
    text(3, 2, "МЭ МАГАЗИН v2.0", COLORS.energy, COLORS.panel)

    -- Правая панель (Скупка и Профиль)
    rect(rightColX, 1, rightColW, H, COLORS.panel)
    
    -- Блок пользователя (справа вверху)
    local userBoxY = 1
    if user then
        gui.btn("logout", rightColX + 2, userBoxY + 1, rightColW - 4, 3, "ВЫХОД", COLORS.bad)
        center(rightColX, userBoxY + 5, rightColW, user.name, COLORS.good, COLORS.panel)
        center(rightColX, userBoxY + 6, rightColW, user.balance .. " ЭМ", COLORS.warn, COLORS.panel)
        
        -- Кнопка админки (появляется только если игрок админ)
        if user.isAdmin then
            gui.btn("admin_panel", rightColX + 2, userBoxY + 8, rightColW - 4, 1, "АДМИН ПАНЕЛЬ", COLORS.energy)
        end
    else
        gui.btn("login", rightColX + 2, userBoxY + 1, rightColW - 4, 5, "АВТОРИЗАЦИЯ", COLORS.good)
        center(rightColX, userBoxY + 7, rightColW, "Войдите для покупок", COLORS.label, COLORS.panel)
    end

    -- Заголовок зоны скупки
    local buybackY = 11
    rect(rightColX, buybackY, rightColW, 1, COLORS.tileHeader)
    center(rightColX, buybackY, rightColW, "МЫ СКУПАЕМ:", COLORS.text, COLORS.tileHeader)
end

-- === ОТРИСОВКА КАТЕГОРИЙ ===
function gui.drawCategories(categories, active_cat)
    local x = 2
    local y = 5
    for i, cat in ipairs(categories) do
        local catW = unicode.len(cat) + 4
        local bg = (cat == active_cat) and COLORS.btnActive or COLORS.btn
        gui.btn("cat_"..cat, x, y, catW, 1, cat, bg)
        x = x + catW + 1
    end
end

-- === ОТРИСОВКА ТОВАРОВ (НА ПРОДАЖУ) ===
function gui.drawItems(items)
    -- Очищаем зону товаров
    rect(1, 7, rightColX - 1, H - 6, COLORS.bg)
    
    local margin = 2
    local cols = 3
    local tileW = math.floor((rightColX - (cols + 1) * margin) / cols)
    local tileH = 6
    
    local row, col = 0, 0
    for i, item in ipairs(items) do
        local x = margin + col * (tileW + margin)
        local y = 7 + row * (tileH + margin)
        
        rect(x, y, tileW, tileH, COLORS.tileBg)
        center(x, y, tileW, item.name, COLORS.text, COLORS.tileHeader)
        
        text(x + 2, y + 2, "Цена: " .. item.price .. " ЭМ", COLORS.warn, COLORS.tileBg)
        text(x + 2, y + 3, "В МЭ: " .. (item.stock or 0) .. " шт", COLORS.label, COLORS.tileBg)
        
        gui.btn("buy_"..i, x + 1, y + 4, math.floor(tileW/2)-1, 1, "КУПИТЬ", COLORS.good)
        gui.btn("cart_"..i, x + math.floor(tileW/2) + 1, y + 4, math.floor(tileW/2)-1, 1, "+ В КОРЗИНУ", COLORS.energy)

        col = col + 1
        if col >= cols then col = 0; row = row + 1 end
    end
end

-- === ОТРИСОВКА СПИСКА СКУПКИ (Справа) ===
function gui.drawBuybackItems(buyback_items)
    local y = 13
    local x = rightColX + 2
    local w = rightColW - 4

    for i, item in ipairs(buyback_items) do
        text(x, y, item.name, COLORS.text, COLORS.panel)
        text(x, y + 1, "Цена: " .. item.price .. " ЭМ/шт", COLORS.warn, COLORS.panel)
        gui.btn("sell_"..i, x, y + 2, w, 1, "СДАТЬ ИЗ СУНДУКА", COLORS.energy)
        y = y + 4
    end
end

function gui.checkClick(x, y)
    for id, b in pairs(gui.buttons) do
        if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
            return id
        end
    end
    return nil
end

return gui
