-- /obmen/me_logic.lua
local component = require("component")
local os = require("os")

local me = {}
local input_chest, me_bus, db, inv_ctrl
local a_out 

function me.init()
    db = component.database
    if not db then return false, "База Данных не найдена в Адаптере 2!" end

    inv_ctrl = component.inventory_controller
    if not inv_ctrl then return false, "Контроллер Инвентаря не найден в Адаптере 3!" end

    for address, compType in component.list() do
        local p = component.proxy(address)
        if p.setInterfaceConfiguration and p.pushItem then
            me_bus = p
        elseif p.getAllStacks and p.pushItem and not p.setInterfaceConfiguration then
            input_chest = p
        end
    end

    if not input_chest then return false, "Адаптер 1 не видит ЛЕВЫЙ сундук!" end
    if not me_bus then return false, "Адаптер 2 не видит ПРАВЫЙ МЭ Интерфейс!" end

    for s = 0, 5 do
        local ok, sz = pcall(inv_ctrl.getInventorySize, s)
        if ok and sz and sz >= 27 then 
            a_out = s
            break 
        end
    end
    if not a_out then return false, "Адаптер 3 не видит ПРАВЫЙ сундук!" end

    return true, "OK"
end

function me.getScanItems()
    -- Ищем РУДУ в левом сундуке (первый найденный предмет)
    local ok1, stacks = pcall(input_chest.getAllStacks, 0)
    local in_item = nil
    if ok1 and type(stacks) == "table" then
        for _, data in pairs(stacks) do
            if type(data) == "table" and data.id then
                in_item = {
                    name = data.id,
                    damage = data.dmg or 0,
                    label = data.display_name or data.displayName or data.id
                }
                break
            end
        end
    end

    -- Ищем СЛИТОК в правом сундуке (первый найденный предмет)
    local out_item = nil
    local size = inv_ctrl.getInventorySize(a_out)
    if size then
        for i = 1, size do
            local stack = inv_ctrl.getStackInSlot(a_out, i)
            if stack and stack.name then
                out_item = {
                    name = stack.name,
                    damage = math.floor(stack.damage or 0),
                    label = stack.label or stack.name
                }
                break
            end
        end
    end

    return in_item, out_item
end

function me.getFreeSpace(target_id, target_dmg)
    local free = 0
    local size = inv_ctrl.getInventorySize(a_out)
    if not size then return 0 end
    for i = 1, size do
        local stack = inv_ctrl.getStackInSlot(a_out, i)
        if not stack then 
            free = free + 64
        elseif stack.name == target_id and math.floor(stack.damage or 0) == math.floor(target_dmg or 0) then
            free = free + (stack.maxSize - stack.size)
        end
    end
    return free
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
                    local free_space = me.getFreeSpace(t.output.name, t.output.damage)
                    local max_out_space = math.floor(free_space / t.ratio)
                    
                    local can_process = math.min(data.qty or data.size, max_out_from_me, max_out_space)

                    if can_process > 0 then
                        local pushed_ore = input_chest.pushItem("DOWN", slot, can_process)

                        if pushed_ore and pushed_ore > 0 then
                            local actual_out_qty = pushed_ore * t.ratio

                            db.clear(1)
                            me_bus.store({name = t.output.name, damage = t.output.damage}, db.address, 1)
                            me_bus.setInterfaceConfiguration(1, db.address, 1, 64)

                            local drop = 0
                            local try_count = 0
                            while drop < actual_out_qty and try_count < 20 do
                                local chunk = math.min(64, actual_out_qty - drop)
                                local dropcount = me_bus.pushItem("UP", 1, chunk)

                                if dropcount and dropcount > 0 then
                                    drop = drop + dropcount
                                    try_count = 0 
                                else
                                    os.sleep(0.1)
                                    try_count = try_count + 1
                                end
                            end

                            me_bus.setInterfaceConfiguration(1, db.address, 1, 0)

                            local msg = (drop < actual_out_qty) and "Сундук выдачи переполнен" or "OK"
                            return true, true, msg, drop, t, pushed_ore
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
