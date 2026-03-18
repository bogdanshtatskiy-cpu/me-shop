-- /lua/me_logic.lua
local component = require("component")
local sides = require("sides")

local me = {}

-- Переменные для хранения подключенных компонентов
me.chest_in = nil    -- Контроллер инвентаря для Сундука 1 (Продажа/Добавление)
me.chest_out = nil   -- Контроллер инвентаря для Сундука 2 (Покупка/Выдача)
me.me_net = nil      -- МЭ Интерфейс
me.db = nil          -- Улучшение "База данных"

-- === ИНИЦИАЛИЗАЦИЯ ===
function me.init()
    -- Ищем базу данных
    if component.isAvailable("database") then
        me.db = component.database
    else
        return false, "ОШИБКА: Улучшение 'База данных' не найдено!"
    end

    -- Ищем МЭ интерфейс
    if component.isAvailable("me_interface") then
        me.me_net = component.me_interface
    else
        return false, "ОШИБКА: МЭ Интерфейс не подключен к компьютеру!"
    end

    -- Ищем контроллеры инвентаря
    local invs = {}
    for address, _ in component.list("inventory_controller") do
        table.insert(invs, component.proxy(address))
    end

    if #invs < 2 then
        return false, "ОШИБКА: Найдено менее 2-х контроллеров инвентаря! Нужно два (для Сундука 1 и Сундука 2)."
    end

    -- Пока что жестко привязываем первый найденный контроллер к ВВОДУ, второй к ВЫВОДУ.
    -- В будущем можно сделать умную калибровку.
    me.chest_in = invs[1]
    me.chest_out = invs[2]

    return true, "МЭ компоненты и сундуки успешно инициализированы!"
end

-- === РАБОТА С СУНДУКОМ ВВОДА (Продажа / Регистрация) ===

-- Сканируем Сундук 1 на наличие предметов
function me.scanInputChest(chest_side)
    -- chest_side - это сторона, с которой сундук прилегает к адаптеру (sides.top, sides.bottom и т.д.)
    local items = {}
    local size = me.chest_in.getInventorySize(chest_side)
    
    if not size then return items end -- Если сундука нет

    for i = 1, size do
        local item = me.chest_in.getStackInSlot(chest_side, i)
        if item then
            item.slot = i -- Запоминаем, в каком слоте лежит предмет
            table.insert(items, item)
        end
    end
    return items
end

-- Создать точный "слепок" предмета в Базе Данных (для админа при добавлении товара)
function me.saveItemToDB(chest_side, chest_slot, db_slot)
    -- Берем предмет из указанного слота сундука и сохраняем его хэш+NBT в ячейку базы данных
    local success = me.chest_in.store(chest_side, chest_slot, me.db.address, db_slot)
    return success
end

-- === РАБОТА С МЭ СЕТЬЮ И СУНДУКОМ ВЫВОДА (Покупка) ===

-- Проверить, сколько такого предмета есть в МЭ сети
function me.checkMEAmount(db_slot)
    local item_in_net = me.me_net.getItemDetail({ id = me.db.address, slot = db_slot })
    if item_in_net then
        return item_in_net.qty
    end
    return 0
end

-- Выдать предмет из МЭ сети в Сундук 2
function me.extractItem(db_slot, amount, extract_direction)
    -- extract_direction - это сторона, куда МЭ интерфейс должен вытолкнуть предмет (в Сундук 2)
    -- Функция exportItem берет шаблон предмета из нашей БД и просит МЭ сеть выдать его
    local success = me.me_net.exportItem(me.db.address, db_slot, amount, extract_direction)
    return success
end

return me
