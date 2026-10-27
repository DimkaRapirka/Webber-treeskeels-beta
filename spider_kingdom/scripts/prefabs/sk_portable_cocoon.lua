-- K5 Portable Home: a small cocoon tent Webber can deploy, sleep in and pack up again.
-- Logic follows Walter's official prefabs/portabletent.lua (portablestructure + sleepingbag + finiteuses,
-- ReplacePrefab back to the item keeping its uses). Sleeping uses the stock den animations
-- (cocoon_enter / cocoon_sleep_loop from prefabs/spiderden.lua) on a scaled-down cocoon.
-- Only Webbers may sleep in it unless its owner has T3 Cozy Place (tag "sk_cozy", see
-- networking/sleep_actions.lua and colony/ownership.lua). It is NOT tagged "spiderden": spiders look
-- for that tag to call den combat callbacks this structure does not have.

require "prefabutil"

local Ownership = require("spiderkingdom/colony/ownership")

local assets =
{
    Asset("ANIM", "anim/sk_cocoon.zip"),             -- own model (Phase 6), art_src/tools/gen_cocoon.py
    Asset("ANIM", "anim/sk_portable_cocoon.zip"),
    Asset("ANIM", "anim/sk_item.zip"),
    Asset("ANIM", "anim/sk_portable_cocoon_item.zip"),
}

local prefabs =
{
    "collapse_small",
    "sk_portable_cocoon_item",
}

local prefabs_item =
{
    "sk_portable_cocoon",
}

local SCALE = 1

local function GetUses()
    return TUNING.SPIDERKINGDOM.PORTABLE_COCOON_USES
end

local function CanDismantle(inst, doer)
    return doer:HasTag("spiderwhisperer")
end

-- Structure ------------------------------------------------------------------------------------

local function ChangeToItem(inst)
    local uses = inst.components.finiteuses:GetUses()
    local item = ReplacePrefab(inst, "sk_portable_cocoon_item")
    item.components.finiteuses:SetUses(uses)
end

local function OnHammered(inst)
    if inst._sk_depleted then
        return
    end
    if inst.components.burnable ~= nil and inst.components.burnable:IsBurning() then
        inst.components.burnable:Extinguish()
    end

    if inst:HasTag("burnt") then
        local fx = SpawnPrefab("collapse_small")
        fx.Transform:SetPosition(inst.Transform:GetWorldPosition())
        inst.components.lootdropper:DropLoot()
        inst:Remove()
    else
        ChangeToItem(inst)
    end
end

local function OnHit(inst)
    if inst.components.sleepingbag ~= nil and inst.components.sleepingbag.sleeper ~= nil then
        inst.components.sleepingbag:DoWakeUp()
    end
end

local function OnDismantle(inst)
    if not inst._sk_depleted then
        ChangeToItem(inst)
    end
end

local function OnBurnt(inst)
    DefaultBurntStructureFn(inst)
    -- DefaultBurntStructureFn plays "burnt", which the cocoon banks do not have.
    inst.AnimState:PlayAnimation("cocoon_dead")
    RemovePhysicsColliders(inst)
    if inst.components.portablestructure ~= nil then
        inst:RemoveComponent("portablestructure")
    end
end

local function OnIgnite(inst)
    if inst.components.sleepingbag ~= nil then
        inst.components.sleepingbag:DoWakeUp()
    end
end

local function OnSleep(inst, sleeper)
    sleeper:ListenForEvent("onignite", OnIgnite, inst)
    inst.AnimState:PlayAnimation("cocoon_enter")
    inst.AnimState:PushAnimation("cocoon_sleep_loop", true)
    inst.SoundEmitter:PlaySound("webber2/common/spiderden/in")
end

local function OnWake(inst, sleeper, nostatechange)
    sleeper:RemoveEventCallback("onignite", OnIgnite, inst)
    inst.AnimState:PlayAnimation("cocoon_enter")
    inst.AnimState:PushAnimation("cocoon_large", true)
    inst.SoundEmitter:PlaySound("webber2/common/spiderden/out")
    inst.components.finiteuses:Use()
end

local function TemperatureTick(inst, sleeper)
    local ent_temp = GetEntityTemperature(sleeper)
    if ent_temp ~= nil and ent_temp < TUNING.SLEEP_TARGET_TEMP_TENT then
        SetEntityTemperature(sleeper, ent_temp + TUNING.SLEEP_TEMP_PER_TICK)
    end
end

local function RemoveDepleted(inst)
    local fx = SpawnPrefab("collapse_small")
    fx.Transform:SetPosition(inst.Transform:GetWorldPosition())
    inst:Remove()
end

-- The last use is spent from OnWake, which can run inside Burnable:Ignite (onignite -> DoWakeUp).
-- Remove on the next frame so the caller does not keep working on a removed entity.
local function OnFinished(inst)
    if not inst:HasTag("burnt") and not inst._sk_depleted then
        inst._sk_depleted = true
        inst.persists = false
        inst:AddTag("NOCLICK")
        inst:DoTaskInTime(0, RemoveDepleted)
    end
end

local function SetOwner(inst, userid)
    inst.sk_owner_userid = userid
    Ownership.Register(inst, userid)
end

local function OnSave(inst, data)
    if inst:HasTag("burnt") or (inst.components.burnable ~= nil and inst.components.burnable:IsBurning()) then
        data.burnt = true
    end
    data.owner = inst.sk_owner_userid
end

local function OnLoad(inst, data)
    if data ~= nil then
        if data.burnt then
            inst.components.burnable.onburnt(inst)
        end
        if data.owner ~= nil then
            SetOwner(inst, data.owner)
        end
    end
end

local function placer_postinit(placer)
    placer.AnimState:HideSymbol("bedazzled_flare")
    placer.AnimState:SetScale(SCALE, SCALE)
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()

    inst:SetDeploySmartRadius(DEPLOYSPACING_RADIUS[DEPLOYSPACING.DEFAULT] / 2)
    inst:SetPhysicsRadiusOverride(.5)
    MakeObstaclePhysics(inst, inst.physicsradiusoverride)

    inst.AnimState:SetBank("sk_cocoon")
    inst.AnimState:SetBuild("sk_portable_cocoon")
    inst.AnimState:PlayAnimation("cocoon_large", true)
    inst.AnimState:SetScale(SCALE, SCALE)

    inst:AddTag("tent")
    inst:AddTag("portabletent")
    inst:AddTag("structure")
    inst:AddTag("sk_portablecocoon")

    -- Client and server: used by the official DISMANTLE collector (componentactions.lua portablestructure).
    inst.candismantle = CanDismantle

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.SetOwner = SetOwner

    inst:AddComponent("portablestructure")
    inst.components.portablestructure:SetOnDismantleFn(OnDismantle)

    inst:AddComponent("inspectable")
    inst:AddComponent("lootdropper")

    inst:AddComponent("workable")
    inst.components.workable:SetWorkAction(ACTIONS.HAMMER)
    inst.components.workable:SetWorkLeft(4)
    inst.components.workable:SetOnFinishCallback(OnHammered)
    inst.components.workable:SetOnWorkCallback(OnHit)

    inst:AddComponent("sleepingbag")
    inst.components.sleepingbag.onsleep = OnSleep
    inst.components.sleepingbag.onwake = OnWake
    inst.components.sleepingbag.health_tick = TUNING.SLEEP_HEALTH_PER_TICK * 1.5
    inst.components.sleepingbag.hunger_tick = TUNING.SLEEP_HUNGER_PER_TICK * 1.5
    inst.components.sleepingbag.dryingrate = math.max(0, -TUNING.SLEEP_WETNESS_PER_TICK / TUNING.SLEEP_TICK_PERIOD)
    inst.components.sleepingbag:SetTemperatureTickFn(TemperatureTick)

    inst:AddComponent("finiteuses")
    inst.components.finiteuses:SetOnFinished(OnFinished)
    inst.components.finiteuses:SetMaxUses(GetUses())
    inst.components.finiteuses:SetUses(GetUses())

    MakeHauntableWork(inst)

    MakeMediumBurnable(inst, nil, nil, true)
    inst.components.burnable:SetOnBurntFn(OnBurnt)
    MakeSmallPropagator(inst)

    inst.OnSave = OnSave
    inst.OnLoad = OnLoad

    return inst
end

-- Item -----------------------------------------------------------------------------------------

local function OnDeploy(inst, pt, deployer)
    local cocoon = SpawnPrefab("sk_portable_cocoon")
    if cocoon ~= nil then
        cocoon.Physics:SetCollides(false)
        cocoon.Physics:Teleport(pt.x, 0, pt.z)
        cocoon.Physics:SetCollides(true)

        cocoon.AnimState:PlayAnimation("grow_sac_to_small")
        cocoon.AnimState:PushAnimation("cocoon_large", true)
        cocoon.SoundEmitter:PlaySound("dontstarve/creatures/spider/spider_egg_sack")

        cocoon.components.finiteuses:SetUses(inst.components.finiteuses:GetUses())
        if deployer ~= nil and deployer.userid ~= nil then
            cocoon:SetOwner(deployer.userid)
        end

        inst:Remove()
        PreventCharacterCollisionsWithPlacedObjects(cocoon)
    end
end

local function itemfn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()

    MakeInventoryPhysics(inst)

    inst.AnimState:SetBank("sk_item")
    inst.AnimState:SetBuild("sk_portable_cocoon_item")
    inst.AnimState:PlayAnimation("idle")

    inst:AddTag("portableitem")

    MakeInventoryFloatable(inst, "med", 0.05, {0.85, 0.6, 0.85})

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("finiteuses")
    inst.components.finiteuses:SetOnFinished(inst.Remove)
    inst.components.finiteuses:SetMaxUses(GetUses())
    inst.components.finiteuses:SetUses(GetUses())

    inst:AddComponent("inspectable")

    inst:AddComponent("inventoryitem")

    inst:AddComponent("deployable")
    inst.components.deployable.ondeploy = OnDeploy

    inst:AddComponent("hauntable")
    inst.components.hauntable:SetHauntValue(TUNING.HAUNT_TINY)

    MakeSmallBurnable(inst)
    MakeSmallPropagator(inst)

    return inst
end

return Prefab("sk_portable_cocoon", fn, assets, prefabs),
    MakePlacer("sk_portable_cocoon_item_placer", "sk_cocoon", "sk_portable_cocoon", "cocoon_large", nil, nil, nil, nil, nil, nil, placer_postinit),
    Prefab("sk_portable_cocoon_item", itemfn, assets, prefabs_item)
