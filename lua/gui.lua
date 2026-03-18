-- /lua/gui.lua
local component = require("component")
local term = require("term")
local unicode = require("unicode")
local gpu = component.gpu

local gui = {}
gui.buttons = {}

gui.COLORS = {
    bg = 0x111111, tileBg = 0x222222, tileHeader = 0x333333,
    text = 0xEEEEEE, label = 0x999999,
    good = 0x55FF55, warn = 0xFFAA00, bad = 0xFF5555,
    energy = 0x00AAFF, btn = 0x444444, btnActive = 0x006699,
    panel = 0x181818, modalBg = 0x000000
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
    center(x, y + math.floor(h/2), w, str, fg or gui.COLORS.text, bg)
    gui.buttons[id] = {x=x, y=y, w=w, h=h} 
end

function gui.drawStatic(user, timer)
    gpu.setBackground(gui.COLORS.bg)
    term.clear()
    gui.buttons = {}

    rect(1, 1, rightColX - 1, 3, gui.COLORS.panel)
    text(3, 2, "МЭ МАГАЗИН v2.1", gui.COLORS.energy, gui.COLORS.panel)

    rect(rightColX, 1, rightColW, H, gui.COLORS.panel)
    
    local userBoxY = 1
    if user then
        gui.btn("logout", rightColX + 2, userBoxY + 1, rightColW - 4, 3, "ВЫХОД", gui.COLORS.bad)
        center(rightColX, userBoxY + 5, rightColW, user.name, gui.COLORS.good, gui.COLORS.panel)
        center(rightColX, userBoxY + 6, rightColW, user.balance .. " ЭМ", gui.COLORS.warn, gui.COLORS.panel)
        
        if timer then
            center(rightColX, userBoxY + 8, rightColW, "Выход через: " .. timer .. "с", gui.COLORS.label, gui.COLORS.panel)
        end
        
        if user.isAdmin then
            gui.btn("admin_panel", rightColX + 2, userBoxY + 10, rightColW - 4, 1, "АДМИН ПАНЕЛЬ", gui.COLORS.energy)
        end
    else
        gui.btn("login", rightColX + 2, userBoxY + 1, rightColW - 4, 5, "АВТОРИЗАЦИЯ", gui.COLORS.good)
        center(rightColX, userBoxY + 7, rightColW, "Войдите для покупок", gui.COLORS.label, gui.COLORS.panel)
    end

    local buybackY = 13
    rect(rightColX, buybackY, rightColW, 1, gui.COLORS.tileHeader)
    center(rightColX, buybackY, rightColW, "МЫ СКУПАЕМ:", gui.COLORS.text, gui.COLORS.tileHeader)
end

function gui.drawCategories(categories, active_cat)
    local x = 2; local y = 5
    for i, cat in ipairs(categories) do
        local catW = unicode.len(cat) + 4
        local bg = (cat == active_cat) and gui.COLORS.btnActive or gui.COLORS.btn
        gui.btn("cat_"..cat, x, y, catW, 1, cat, bg)
        x = x + catW + 1
    end
end

function gui.drawItems(items)
    rect(1, 7, rightColX - 1, H - 6, gui.COLORS.bg)
    local margin = 2; local cols = 3
    local tileW = math.floor((rightColX - (cols + 1) * margin) / cols); local tileH = 6
    local row, col = 0, 0
    for i, item in ipairs(items) do
        local x = margin + col * (tileW + margin); local y = 7 + row * (tileH + margin)
        rect(x, y, tileW, tileH, gui.COLORS.tileBg)
        center(x, y, tileW, item.name, gui.COLORS.text, gui.COLORS.tileHeader)
        text(x + 2, y + 2, "Цена: " .. item.price .. " ЭМ", gui.COLORS.warn, gui.COLORS.tileBg)
        text(x + 2, y + 3, "В МЭ: " .. (item.stock or 0) .. " шт", gui.COLORS.label, gui.COLORS.tileBg)
        gui.btn("buy_"..i, x + 1, y + 4, math.floor(tileW/2)-1, 1, "КУПИТЬ", gui.COLORS.good)
        gui.btn("cart_"..i, x + math.floor(tileW/2) + 1, y + 4, math.floor(tileW/2)-1, 1, "В КОРЗИНУ", gui.COLORS.energy)
        col = col + 1; if col >= cols then col = 0; row = row + 1 end
    end
end

function gui.drawBuybackItems(buyback_items)
    local y = 15; local x = rightColX + 2; local w = rightColW - 4
    for i, item in ipairs(buyback_items) do
        text(x, y, "- " .. item.name .. " (" .. item.price .. " ЭМ)", gui.COLORS.warn, gui.COLORS.panel)
        y = y + 1
    end
    gui.btn("sell_all", x, H - 3, w, 3, "ПРОДАТЬ ВСЁ", gui.COLORS.good)
end

function gui.drawNotification(title, message, isError)
    gui.buttons = {}
    local w = 50; local h = 10; local x = math.floor((W - w) / 2); local y = math.floor((H - h) / 2)
    local titleCol = isError and gui.COLORS.bad or gui.COLORS.good
    rect(x, y, w, h, gui.COLORS.tileBg)
    rect(x, y, w, 2, titleCol)
    center(x, y, w, title, gui.COLORS.bg, titleCol)
    center(x, y + 4, w, message, gui.COLORS.text, gui.COLORS.tileBg)
    gui.btn("close_modal", x + 15, y + 7, 20, 1, "ОК", gui.COLORS.btn)
end

function gui.drawQuantitySelector(item, qty)
    gui.buttons = {}
    local w = 40; local h = 12; local x = math.floor((W - w) / 2); local y = math.floor((H - h) / 2)
    rect(x, y, w, h, gui.COLORS.tileBg)
    rect(x, y, w, 2, gui.COLORS.tileHeader)
    center(x, y, w, "ПОКУПКА: " .. item.name, gui.COLORS.text, gui.COLORS.tileHeader)
    center(x, y + 3, w, "В наличии: " .. item.stock .. " шт", gui.COLORS.label, gui.COLORS.tileBg)
    center(x, y + 5, w, "Количество: " .. qty, gui.COLORS.text, gui.COLORS.tileBg)
    center(x, y + 7, w, "К оплате: " .. (item.price * qty) .. " ЭМ", gui.COLORS.warn, gui.COLORS.tileBg)
    gui.btn("qty_sub10", x + 2, y + 5, 5, 1, "-10", gui.COLORS.bad)
    gui.btn("qty_sub1", x + 8, y + 5, 5, 1, "-1", gui.COLORS.bad)
    gui.btn("qty_add1", x + 27, y + 5, 5, 1, "+1", gui.COLORS.good)
    gui.btn("qty_add10", x + 33, y + 5, 5, 1, "+10", gui.COLORS.good)
    gui.btn("confirm_buy", x + 2, y + 10, 16, 1, "ПОДТВЕРДИТЬ", gui.COLORS.good)
    gui.btn("close_modal", x + 22, y + 10, 16, 1, "ОТМЕНА", gui.COLORS.bad)
end

function gui.checkClick(x, y)
    for id, b in pairs(gui.buttons) do
        if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then return id end
    end
    return nil
end

return gui
