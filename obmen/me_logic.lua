-- /obmen/me_logic.lua
local component = require("component")
local os = require("os")
local io = require("io")

local me = {}
local chests = {}
local input_chest = nil
local output_chest = nil
local me_bus, db, inv_ctrl
local a_out 

function me.init()
    db = component.database
    if not db then return false, "База Данных не найдена в Адаптере 2!" end

    inv_ctrl = component.inventory_controller
    if not inv_ctrl then return false, "Контроллер Инвентаря не найден в Адаптере 3!" end

    chests = {}
    input_chest = nil
    output_chest = nil

    for address, compType in component.list() do
        local p = component.proxy(address)
        if p.setInterfaceConfiguration and p.pushItem then
            me_bus = p
        elseif p.getAllStacks and p.pushItem and not p.setInterfaceConfiguration then
            table.insert(chests, p)
        end
    end

    if #chests == 0 then return false, "Не найдено ни одного сундука!" end
    if not me_bus then return false, "Адаптер 2 не видит ПРАВЫЙ МЭ Интерфейс!" end

    for s = 0, 5 do
        local ok, sz = pcall(inv_ctrl.getInventorySize, s)
        if ok and sz and sz >= 27 then 
            a_out = s
            break 
        end
    end
    if not a_out then return false, "Адаптер 3 не видит ПРАВЫЙ сундук!" end

    local f1 = io.open("/home/left_chest.cfg", "r")
    if f1 then 
        local addr = f1:read("*a"); f1:close()
        for _, c in ipairs(chests) do if c.address == addr then input_chest = c break end end
    end

    local f2 = io.open("/home/right_chest.cfg", "r")
    if f2 then 
        local addr = f2:read("*a"); f2:close()
        for _, c in ipairs(chests) do if c.address == addr then output_chest = c break end end
    end

    if not input_chest and output_chest and #chests == 2 then
        for _, c in ipairs(chests) do
            if c.address ~= output_chest.address then
                input_chest = c
                local f = io.open("/home/left_chest.cfg", "w")
                if f then f:write(c.address); f:close() end
                break
            end
        end
    end
    if not output_chest and input_chest and #chests == 2 then
        for _, c in ipairs(chests) do
            if c.address ~= input_chest.address then
                output_chest = c
                local f = io.open("/home/right_chest.cfg", "w")
                if f then f:write(c.address); f:close() end
                break
            end
        end
    end

    return true, "OK"
end

function me.getScanItems()
    local out_item = nil
    local out_label = nil
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
                out_label = stack.label or stack.name
                break
            end
        end
    end

    if not out_item then return nil, nil end

    if not input_chest or not output_chest then
        for _, chest in ipairs(chests) do
            local ok, stacks = pcall(chest.getAllStacks, 0)
            local has_output_item = false
            local has_any_item = false

            if ok and type(stacks) == "table" then
                for _, data in pairs(stacks) do
                    if type(data) == "table" and data.id then
                        has_any_item = true
                        local label = data.display_name or data.displayName or data.id
                        if label == out_label then
                            has_output_item = true
                            break
                        end
                    end
                end
            end

            if has_output_item then
                output_chest = chest
                local f = io.open("/home/right_chest.cfg", "w")
                if f then f:write(chest.address); f:close() end
            elseif has_any_item and not has_output_item then
                input_chest = chest
                local f = io.open("/home/left_chest.cfg", "w")
                if f then f:write(chest.address); f:close() end
            end
        end
    end

    local in_item = nil
    if input_chest then
        local ok, stacks = pcall(input_chest.getAllStacks, 0)
        if ok and type(stacks) == "table" then
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
    end

    return in_item, out_item
end

function me.getFreeSpace(target_id, target_dmg)
    local size = inv_ctrl.getInventorySize(a_out)
    if not size then return 0 end
    
    if output_chest then
        local ok, stacks = pcall(output_chest.getAllStacks, 0)
        if ok and type(stacks) == "table" then
            local free = 0
            for i = 1, size do
                local stack = stacks[i]
                if not stack or not stack.id then
                    free = free + 64 
                elseif stack.id == target_id and math.floor(stack.dmg or 0) == math.floor(target_dmg or 0) then
                    local max = stack.max_size or stack.maxSize or 64
                    free = free + (max - (stack.qty or 0))
                end
            end
            return free
        end
    end

    local free = 0
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

-- НОВАЯ ФУНКЦИЯ ДЛЯ БАННЕРА: Проверяет, забит ли сундук на 100%
function me.isOutputChestFull()
    if not inv_ctrl or not a_out then return false end
    local size = inv_ctrl.getInventorySize(a_out)
    if not size then return false end
    
    if output_chest then
        local ok, stacks = pcall(output_chest.getAllStacks, 0)
        if ok and type(stacks) == "table" then
            local free_slots = 0
            for i = 1, size do
                if not stacks[i] or not stacks[i].id then
                    free_slots = free_slots + 1
                end
            end
            return free_slots == 0
        end
    end

    local free_slots = 0
    for i = 1, size do
        if not inv_ctrl.getStackInSlot(a_out, i) then free_slots = free_slots + 1 end
    end
    return free_slots == 0
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
    if not input_chest then return false end

    local ok, stacks = pcall(input_chest.getAllStacks, 0)
    if not ok or type(stacks) ~= "table" then return false end

    for _, t in ipairs(trades) do
        local total_ore = 0
        local ore_slots = {}
        
        for slot, data in pairs(stacks) do
            if type(data) == "table" and data.id == t.input.name and math.floor(data.dmg or 0) == math.floor(t.input.damage or 0) then
                total_ore = total_ore + (data.qty or data.size or 0)
                table.insert(ore_slots, {slot = slot, qty = (data.qty or data.size or 0)})
            end
        end

        if total_ore > 0 then
            local max_out_from_me = math.floor(t.stock / t.ratio)
            local free_space = me.getFreeSpace(t.output.name, t.output.damage)
            local max_out_space = math.floor(free_space / t.ratio)
            
            local max_ore_we_can_process = math.min(total_ore, max_out_from_me, max_out_space)

            if max_ore_we_can_process <= 0 then
                local reason = ""
                if max_out_from_me <= 0 then reason = "В МЭ нет слитков (" .. t.stock .. " шт)"
                elseif max_out_space <= 0 then reason = "Правый сундук забит"
                else reason = "Ошибка лимитов" end
                return true, false, reason, 0, t, total_ore
            end

            local total_ore_pushed = 0
            
            for _, s in ipairs(ore_slots) do
                local to_push = math.min(s.qty, max_ore_we_can_process - total_ore_pushed)
                if to_push <= 0 then break end
                
                local pushed = input_chest.pushItem("DOWN", s.slot, to_push)
                if pushed and pushed > 0 then
                    total_ore_pushed = total_ore_pushed + pushed
                end
            end

            if total_ore_pushed > 0 then
                local actual_out_qty = total_ore_pushed * t.ratio

                db.clear(1)
                me_bus.store({name = t.output.name, damage = t.output.damage}, db.address, 1)
                me_bus.setInterfaceConfiguration(1, db.address, 1, 64)

                local drop = 0
                local try_count = 0
                while drop < actual_out_qty and try_count < 30 do
                    local chunk = math.min(64, actual_out_qty - drop)
                    local dropcount = me_bus.pushItem("UP", 1, chunk)

                    if dropcount and dropcount > 0 then
                        drop = drop + dropcount
                        try_count = 0 
                    else
                        os.sleep(0.05)
                        try_count = try_count + 1
                    end
                end

                me_bus.setInterfaceConfiguration(1, db.address, 1, 0)

                local msg = (drop < actual_out_qty) and "МЭ не смогла выдать все слитки" or "OK"
                return true, true, msg, drop, t, total_ore_pushed
            else
                return true, false, "МЭ интерфейс под левым сундуком не принимает руду", 0, t, max_ore_we_can_process
            end
        end
    end
    return false
end

return me
