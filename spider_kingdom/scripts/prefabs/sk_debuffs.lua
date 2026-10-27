-- Server-only debuff entities, same structure as the official prefabs/spider_buffs.lua.

-- B3 Predator Fangs: venom damage over time. Re-applying refreshes the duration and sets the stack count.
local function venom_tick(inst)
    local target = inst.target
    if target == nil or not target:IsValid() or target.components.health == nil or target.components.health:IsDead() then
        inst.components.debuff:Stop()
        return
    end

    local damage = TUNING.SPIDERKINGDOM.FANGS_DAMAGE_PER_STACK * inst.stacks
    local attacker = inst.attacker ~= nil and inst.attacker:IsValid() and inst.attacker or nil
    target.components.health:DoDelta(-damage, true, "sk_venom", nil, attacker)
end

local function venom_onextended(inst, target, followsymbol, followoffset, data)
    inst.target = target
    if data ~= nil then
        inst.stacks = data.stacks or inst.stacks
        inst.attacker = data.attacker or inst.attacker
    end

    if inst.decaytimer ~= nil then
        inst.decaytimer:Cancel()
    end
    inst.decaytimer = inst:DoTaskInTime(TUNING.SPIDERKINGDOM.FANGS_DURATION, function() inst.components.debuff:Stop() end)

    if inst.ticktask == nil then
        inst.ticktask = inst:DoPeriodicTask(TUNING.SPIDERKINGDOM.FANGS_TICK_PERIOD, venom_tick)
    end
end

local function venom_ondetached(inst, target)
    if inst.decaytimer ~= nil then
        inst.decaytimer:Cancel()
        inst.decaytimer = nil
    end
    if inst.ticktask ~= nil then
        inst.ticktask:Cancel()
        inst.ticktask = nil
    end
    inst:Remove()
end

local function venom_fn()
    local inst = CreateEntity()

    if not TheWorld.ismastersim then
        --Not meant for client!
        inst:DoTaskInTime(0, inst.Remove)
        return inst
    end

    inst.entity:AddTransform()

    --[[Non-networked entity]]
    inst.entity:Hide()
    inst.persists = false

    inst:AddTag("CLASSIFIED")

    inst.stacks = 1

    inst:AddComponent("debuff")
    inst.components.debuff:SetAttachedFn(venom_onextended)
    inst.components.debuff:SetExtendedFn(venom_onextended)
    inst.components.debuff:SetDetachedFn(venom_ondetached)

    return inst
end

-- B4 Silk Spit: slowed for SILKSPIT_SLOW_DURATION, tagged "sk_marked" for SILKSPIT_MARK_DURATION.
local WEBBED_SPEED_KEY = "sk_webbed"

local function webbed_endslow(inst)
    inst.slowtask = nil
    local target = inst.target
    if target ~= nil and target:IsValid() and target.components.locomotor ~= nil then
        target.components.locomotor:RemoveExternalSpeedMultiplier(inst, WEBBED_SPEED_KEY)
    end
end

local function webbed_onextended(inst, target)
    local tuning = TUNING.SPIDERKINGDOM
    inst.target = target

    if target.components.locomotor ~= nil then
        target.components.locomotor:SetExternalSpeedMultiplier(inst, WEBBED_SPEED_KEY, tuning.SILKSPIT_SPEED_MULT)
    end
    target:AddTag("sk_marked")

    if inst.slowtask ~= nil then
        inst.slowtask:Cancel()
    end
    inst.slowtask = inst:DoTaskInTime(tuning.SILKSPIT_SLOW_DURATION, webbed_endslow)

    if inst.decaytimer ~= nil then
        inst.decaytimer:Cancel()
    end
    inst.decaytimer = inst:DoTaskInTime(tuning.SILKSPIT_MARK_DURATION, function() inst.components.debuff:Stop() end)
end

local function webbed_ondetached(inst, target)
    if inst.slowtask ~= nil then
        inst.slowtask:Cancel()
        inst.slowtask = nil
    end
    if inst.decaytimer ~= nil then
        inst.decaytimer:Cancel()
        inst.decaytimer = nil
    end
    if target ~= nil and target:IsValid() then
        if target.components.locomotor ~= nil then
            target.components.locomotor:RemoveExternalSpeedMultiplier(inst, WEBBED_SPEED_KEY)
        end
        target:RemoveTag("sk_marked")
    end
    inst:Remove()
end

local function webbed_fn()
    local inst = CreateEntity()

    if not TheWorld.ismastersim then
        --Not meant for client!
        inst:DoTaskInTime(0, inst.Remove)
        return inst
    end

    inst.entity:AddTransform()

    --[[Non-networked entity]]
    inst.entity:Hide()
    inst.persists = false

    inst:AddTag("CLASSIFIED")

    inst:AddComponent("debuff")
    inst.components.debuff:SetAttachedFn(webbed_onextended)
    inst.components.debuff:SetExtendedFn(webbed_onextended)
    inst.components.debuff:SetDetachedFn(webbed_ondetached)

    return inst
end

return Prefab("sk_venom_debuff", venom_fn),
    Prefab("sk_webbed_debuff", webbed_fn)
