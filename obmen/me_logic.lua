-- /obmen/me_logic.lua
local component = require("component")
local os = require("os")

local me = {}
local input_chest, me_bus, db

function me.init()
    db = component.database
    if not db then return false, "База Данных не найдена в Адаптере 2!" end

    -- Умный поиск: Адаптеры сами понимают, к чему они прилеплены
    for address, compType in component.list() do
        local p = component.proxy(address)
        
        -- Если у блока есть функция setInterfaceConfiguration - это МЭ Интерфейс!
        if p.setInterfaceConfiguration and p.pushItem then
            me_bus = p
            
        -- Если у блока есть getAllStacks, но нет настроек МЭ - это Сундук!
        elseif p.getAllStacks and p.pushItem and not p.setInterfaceConfiguration then
            input_chest = p
        end
    end

    if not input_chest then return false, "Адаптер 1 не видит ЛЕВЫЙ сундук!" end
    if not me_bus then return false, "Адаптер 2 не видит ПРАВЫЙ МЭ Интерфейс!" end

    return true, "OK"
end

function me.getScanItems()
    -- Для сканирования обмена просто кладем Руду в 1 слот, а Слиток во 2 слот левого сундука!
    local ok, stacks = pcall(input_chest.getAllStacks, 0)
    if not ok or type(stacks) ~= "table" then return nil, nil end

    local function formatItem(data)
        if type(data) ~= "table" or not data.id then return nil end
        return {
            name = data.id,
            damage = data.dmg or 0,
            label = data.display_name or data.displayName or data.id
        }
    end

    return formatItem(stacks[1]), formatItem(stacks[2])
end

function me.updateStock(trades)
    for _, t in ipairs(trades) do
        t.stock = 0
        local ok, items = pcall(me_bus.getItemsInNetwork, {name = t.output.name, damage = t.output.damage})
        if ok and items then
            for _, item in pairs(items) do
                if type(item) == "table" and item.name == t.output.name then
                    t.stock = t.stock + (item.size or item.qty or 0)
                end
            end
        end
    end
end

function me.processOneExchange(trades)
    local ok, stacks = pcall(input_chest.getAllStacks, 0)
    if not ok or type(stacks) ~= "table" then return false end

    for slot, data in pairs(stacks) do
        if type(data) == "table" and data.id then
            for _, t in ipairs(trades) do
                if data.id == t.input.name and (data.dmg or 0) == (t.input.damage or 0) then
                    local max_out_from_me = math.floor(t.stock / t.ratio)
                    local can_process = math.min(data.qty or data.size, max_out_from_me)

                    if can_process > 0 then
                        -- 1. Скидываем руду ВНИЗ в МЭ интерфейс под левым сундуком
                        local pushed_ore = input_chest.pushItem("DOWN", slot, can_process)

                        if pushed_ore and pushed_ore > 0 then
                            local actual_out_qty = pushed_ore * t.ratio

                            -- 2. ТВОЯ ГЕНИАЛЬНАЯ ЛОГИКА: Настраиваем правый МЭ интерфейс на выдачу
                            db.clear(1)
                            me_bus.store({name = t.output.name, damage = t.output.damage}, db.address, 1)
                            me_bus.setInterfaceConfiguration(1, db.address, 1, 64)

                            local drop = 0
                            -- 3. Выплевываем ВВЕРХ в правый сундук (Если забит - ждем!)
                            while drop < actual_out_qty do
                                local chunk = math.min(64, actual_out_qty - drop)
                                local dropcount = me_bus.pushItem("UP", 1, chunk)

                                if dropcount and dropcount > 0 then
                                    drop = drop + dropcount
                                else
                                    os.sleep(1) -- Ждем 1 секунду, пока игрок освободит сундук
                                end
                            end

                            -- 4. Сбрасываем настройку
                            me_bus.setInterfaceConfiguration(1, db.address, 1, 0)

                            return true, true, "OK", drop, t, pushed_ore
                        else
                            return true, false, "МЭ интерфейс не принимает руду", 0, t, can_process
                        end
                    end
                end
            end
        end
    end
    return false
end

return me
