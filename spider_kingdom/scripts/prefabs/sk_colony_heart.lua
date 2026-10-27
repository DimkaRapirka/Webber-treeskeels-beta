-- K6 Colony Heart: the structure (+ placer). Visuals: own model (bank sk_cocoon, build sk_colony_heart);
-- darker while the network's workers are paused. Not tagged "spiderden": spiders call den callbacks on that tag.
-- Logic: components/sk_colonyheart.lua (owner, pause), colony/network.lua (links, summary),
-- colony/logistics.lua (twigs toggle action, recipe with the one-per-player check).

require "prefabutil"

local Network = require("spiderkingdom/colony/network")

-- Own model (Phase 6): bank sk_cocoon, build sk_colony_heart (art_src/tools/gen_cocoon.py).
local assets =
{
    Asset("ANIM", "anim/sk_cocoon.zip"),
    Asset("ANIM", "anim/sk_colony_heart.zip"),
}

local prefabs =
{
    "collapse_small",
}

local SCALE = 1
local ACTIVE_TINT = { 1, 1, 1, 1 }
local PAUSED_TINT = { 0.6, 0.45, 0.5, 1 }
local IDLE_ANIM = "cocoon_large"
local HIT_ANIM = "cocoon_large_hit"

local function GetHeartString(key, fallback)
    local strings = STRINGS.SK_COLONYHEART
    return strings ~= nil and strings[key] or fallback
end

local function RefreshVisual(inst)
    if not inst:HasTag("burnt") then
        inst.AnimState:SetMultColour(unpack(inst:HasTag(Network.PAUSED_TAG) and PAUSED_TINT or ACTIVE_TINT))
    end
end

local function OnHammered(inst)
    if inst.components.burnable ~= nil and inst.components.burnable:IsBurning() then
        inst.components.burnable:Extinguish()
    end
    local fx = SpawnPrefab("collapse_small")
    fx.Transform:SetPosition(inst.Transform:GetWorldPosition())
    fx:SetMaterial("straw")
    inst.components.lootdropper:DropLoot()
    inst:Remove()
end

local function OnHit(inst)
    if not inst:HasTag("burnt") then
        inst.AnimState:PlayAnimation(HIT_ANIM)
        inst.AnimState:PushAnimation(IDLE_ANIM, true)
    end
end

local function OnBurnt(inst)
    DefaultBurntStructureFn(inst)
    -- DefaultBurntStructureFn plays "burnt", which the cocoon banks do not have.
    inst.AnimState:PlayAnimation("cocoon_dead")
    inst.AnimState:SetMultColour(unpack(PAUSED_TINT))
end

local function GetStatus(inst)
    return (inst:HasTag("burnt") and "BURNT")
        or (inst.components.burnable ~= nil and inst.components.burnable:IsBurning() and "BURNING")
        or (not Network.IsHeartLinked(inst) and "DORMANT")
        or nil
end

-- Server (inspection runs in ACTIONS.LOOKAT.fn): a linked heart reports its network; otherwise the
-- status line from STRINGS.CHARACTERS.*.DESCRIBE.SK_COLONY_HEART is used.
local function GetDescription(inst, viewer)
    -- Burnt, burning or dormant (IsHeartLinked covers all three).
    if not Network.IsHeartLinked(inst) then
        return nil
    end
    local summary = Network.GetSummary(inst)
    local text = string.format(
        GetHeartString("SUMMARY", "Dens: %d. Workers: %d, haulers: %d. Free storage slots: %d."),
        summary.dens, summary.workers, summary.haulers, summary.free)
    if inst.components.sk_colonyheart:IsPaused() then
        text = text.." "..GetHeartString("SUMMARY_PAUSED", "Everyone is resting.")
    end
    return text
end

local function OnSave(inst, data)
    if inst:HasTag("burnt") or (inst.components.burnable ~= nil and inst.components.burnable:IsBurning()) then
        data.burnt = true
    end
end

local function OnLoad(inst, data)
    if data ~= nil and data.burnt then
        inst.components.burnable.onburnt(inst)
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
    inst.entity:AddMiniMapEntity()
    inst.entity:AddNetwork()

    inst:SetDeploySmartRadius(DEPLOYSPACING_RADIUS[DEPLOYSPACING.DEFAULT] / 2)
    MakeObstaclePhysics(inst, 0.5)

    inst.MiniMapEntity:SetIcon("spiderden_2.png")

    inst.AnimState:SetBank("sk_cocoon")
    inst.AnimState:SetBuild("sk_colony_heart")
    inst.AnimState:PlayAnimation(IDLE_ANIM, true)
    inst.AnimState:SetScale(SCALE, SCALE)
    inst.AnimState:SetMultColour(unpack(ACTIVE_TINT))

    inst:AddTag("structure")
    inst:AddTag(Network.HEART_TAG)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("sk_colonyheart")

    inst:AddComponent("inspectable")
    inst.components.inspectable.getstatus = GetStatus
    inst.components.inspectable.descriptionfn = GetDescription

    inst:AddComponent("lootdropper")

    inst:AddComponent("workable")
    inst.components.workable:SetWorkAction(ACTIONS.HAMMER)
    inst.components.workable:SetWorkLeft(TUNING.SPIDERKINGDOM.HEART_WORK)
    inst.components.workable:SetOnFinishCallback(OnHammered)
    inst.components.workable:SetOnWorkCallback(OnHit)

    MakeHauntableWork(inst)

    MakeMediumBurnable(inst, nil, nil, true)
    inst.components.burnable:SetOnBurntFn(OnBurnt)
    MakeMediumPropagator(inst)

    inst:ListenForEvent("sk_heartchanged", RefreshVisual)

    inst.OnSave = OnSave
    inst.OnLoad = OnLoad

    return inst
end

return Prefab(Network.HEART_PREFAB, fn, assets, prefabs),
    MakePlacer(Network.HEART_PREFAB.."_placer", "sk_cocoon", "sk_colony_heart", IDLE_ANIM, nil, nil, nil, nil, nil, nil, placer_postinit)
