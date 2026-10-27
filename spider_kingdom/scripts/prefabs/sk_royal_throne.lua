-- R2 Royal Throne: the throne structure (+ placer) and the Royal Invitation item.
-- Visuals: own model, bank sk_cocoon + build sk_royal_throne; with a queen inside it plays the den's
-- "someone sleeps inside" loop (cocoon_enter / cocoon_sleep_loop, as prefabs/spiderden.lua), which shows
-- the queen resting on the throne, and gets the name "Royal Throne (Spider Queen)".
-- The invitation has its own art (bank sk_item, build sk_royal_invitation).
-- Queen storage and release live in components/sk_royalthrone.lua, the invitation action in
-- spiderkingdom/royalty/throne.lua. Not tagged "spiderden": spiders call den callbacks on that tag.
-- R3 Royal Workshop (royalty/workshops.lua) adds the prototyper component while the workshop is open:
-- the throne then gets a warmer tint and bows ("hit" animation) whenever something is crafted at it.
-- R4 Royal Expedition (royalty/expeditions.lua): while the queen is out with the owner the throne looks
-- empty, is named "Royal Throne (Queen away)" and inspects as AWAY. Fire ends the "away" mark: she then
-- comes home to whichever usable throne the owner has on this shard.
-- Affinity rituals (affinity/rituals.lua): the owner's userid is networked (net_string, Thrones.GetOwnerId) so
-- the client offers SK_QUEENRITUAL to the owner only. Ritual materials already offered are dropped when the
-- throne is hammered or burns down (nothing is lost, ARCHITECTURE.md §1.5).

require "prefabutil"

local Thrones = require("spiderkingdom/royalty/thrones")
local Workshops = require("spiderkingdom/royalty/workshops")

-- Own model (Phase 6): bank sk_cocoon (official spider_cocoon animation names, art_src/tools/gen_cocoon.py),
-- build sk_royal_throne: frame "large" = empty throne, "cocoon_sleep_loop" = the queen resting on it.
local assets =
{
    Asset("ANIM", "anim/sk_cocoon.zip"),
    Asset("ANIM", "anim/sk_royal_throne.zip"),
    Asset("ANIM", "anim/sk_royal_throne_lunar.zip"),
    Asset("ANIM", "anim/sk_royal_throne_shadow.zip"),
}

local prefabs =
{
    "collapse_big",
    "spawn_fx_medium",
    "spiderqueen",
}

local assets_invitation =
{
    Asset("ANIM", "anim/sk_item.zip"),
    Asset("ANIM", "anim/sk_royal_invitation.zip"),
}

local SCALE = 1
local EMPTY_TINT = { 1, 1, 1, 1 }
local OCCUPIED_TINT = { 1, 1, 1, 1 }
local WORKSHOP_TINT = { 1, 0.92, 1, 1 } -- a faint hint that the workshop is open

-- Throne -----------------------------------------------------------------------------------------

local function GetIdleAnim(inst)
    return inst:HasTag(Thrones.OCCUPIED_TAG) and "cocoon_sleep_loop" or "cocoon_large"
end

-- sk_cocoon has a hit with the queen on the throne (the stock name shows the empty throne).
local function GetHitAnim(inst)
    return inst:HasTag(Thrones.OCCUPIED_TAG) and "cocoon_occupied_hit" or "cocoon_large_hit"
end

local function RefreshTint(inst)
    if inst:HasTag("burnt") then
        return
    end
    local tint = (inst:HasTag(Workshops.WORKSHOP_TAG) and WORKSHOP_TINT)
        or (inst:HasTag(Thrones.OCCUPIED_TAG) and OCCUPIED_TINT)
        or EMPTY_TINT
    inst.AnimState:SetMultColour(unpack(tint))
end

-- The queen on the throne in her ritual variant (art_src/tools/gen_throne_variants.py: drawn from her real
-- build). Server only; AnimState builds are networked.
local function RefreshBuild(inst)
    local throne = inst.components.sk_royalthrone
    local variant = throne ~= nil and throne:GetVariant() or nil
    inst.AnimState:SetBuild(variant ~= nil and ("sk_royal_throne_"..variant) or "sk_royal_throne")
end

local function RefreshVisual(inst, data)
    if inst:HasTag("burnt") then
        return
    end
    local occupied = inst:HasTag(Thrones.OCCUPIED_TAG)
    RefreshTint(inst)
    RefreshBuild(inst)

    if data ~= nil and data.instant then
        inst.AnimState:PlayAnimation(GetIdleAnim(inst), true)
    else
        inst.AnimState:PlayAnimation("cocoon_enter")
        inst.AnimState:PushAnimation(GetIdleAnim(inst), true)
        if occupied then
            inst.SoundEmitter:PlaySound("webber2/common/spiderden/in")
        else
            inst.SoundEmitter:PlaySound("dontstarve/creatures/spiderqueen/legburst")
        end
    end
end

local function ReleaseQueen(inst)
    local throne = inst.components.sk_royalthrone
    if throne ~= nil and throne:HasQueen() then
        throne:ReleaseQueen()
    end
end

-- R4: a burning or burnt throne is no longer her home (royalty/expeditions.lua FindHomeThrone).
local function ClearAway(inst)
    local throne = inst.components.sk_royalthrone
    if throne ~= nil then
        throne:ClearAway()
    end
end

-- Affinity rituals: materials offered so far come back out (components/sk_royalthrone.lua):
-- hammered, burnt or deconstructed.
local function DropRitualMaterials(inst)
    local throne = inst.components.sk_royalthrone
    if throne ~= nil then
        throne:DropRitualMaterials()
    end
end

local function OnHammered(inst)
    if inst.components.burnable ~= nil and inst.components.burnable:IsBurning() then
        inst.components.burnable:Extinguish()
    end
    ReleaseQueen(inst)
    DropRitualMaterials(inst)

    local fx = SpawnPrefab("collapse_big")
    fx.Transform:SetPosition(inst.Transform:GetWorldPosition())
    fx:SetMaterial("straw")
    inst.components.lootdropper:DropLoot()
    inst:Remove()
end

local function OnHit(inst)
    if not inst:HasTag("burnt") then
        inst.AnimState:PlayAnimation(GetHitAnim(inst))
        inst.AnimState:PushAnimation(GetIdleAnim(inst), true)
    end
end

-- R3: something was crafted at the workshop.
local function OnWorkshopActivated(inst)
    if not inst:HasTag("burnt") then
        inst.AnimState:PlayAnimation(GetHitAnim(inst))
        inst.AnimState:PushAnimation(GetIdleAnim(inst), true)
        inst.SoundEmitter:PlaySound("dontstarve/creatures/spiderqueen/givebirth_voice")
    end
end

-- The queen leaves as soon as the fire starts, not when the throne has burnt down.
local function OnIgnite(inst)
    ReleaseQueen(inst)
    ClearAway(inst)
end

local function OnBurnt(inst)
    ReleaseQueen(inst)
    ClearAway(inst)
    DropRitualMaterials(inst)
    DefaultBurntStructureFn(inst)
    -- DefaultBurntStructureFn plays "burnt", which the cocoon banks do not have.
    inst.AnimState:PlayAnimation("cocoon_dead")
    inst.AnimState:SetMultColour(unpack(EMPTY_TINT))
end

local function GetStatus(inst)
    return (inst:HasTag("burnt") and "BURNT")
        or (inst.components.burnable ~= nil and inst.components.burnable:IsBurning() and "BURNING")
        or (inst:HasTag(Workshops.WORKSHOP_TAG) and "WORKSHOP")
        or (inst:HasTag(Thrones.OCCUPIED_TAG) and "OCCUPIED")
        or (inst:HasTag(Thrones.AWAY_TAG) and "AWAY")
        or nil
end

-- Client and server.
local function GetDisplayName(inst)
    local royal = STRINGS.SK_ROYAL
    if royal == nil then
        return nil
    end
    return (inst:HasTag(Thrones.OCCUPIED_TAG) and royal.THRONE_OCCUPIED_NAME)
        or (inst:HasTag(Thrones.AWAY_TAG) and royal.THRONE_AWAY_NAME)
        or nil
end

local function OnSave(inst, data)
    if inst:HasTag("burnt") or (inst.components.burnable ~= nil and inst.components.burnable:IsBurning()) then
        data.burnt = true
    end
end

local function OnLoad(inst, data)
    if data ~= nil and data.burnt then
        -- A queen is never saved inside a burning throne (released on ignite). If a save still has
        -- one, OnBurnt releases her on the next frame, once the world has finished loading.
        local throne = inst.components.sk_royalthrone
        if throne ~= nil and throne:HasQueen() then
            inst:DoTaskInTime(0, inst.components.burnable.onburnt)
        else
            inst.components.burnable.onburnt(inst)
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
    inst.entity:AddMiniMapEntity()
    inst.entity:AddNetwork()

    inst:SetDeploySmartRadius(DEPLOYSPACING_RADIUS[DEPLOYSPACING.DEFAULT] / 2)
    inst:SetPhysicsRadiusOverride(0.7) -- as before Phase 6 (den physics 0.5 at scale 1.4)
    MakeObstaclePhysics(inst, inst.physicsradiusoverride)

    inst.MiniMapEntity:SetIcon("spiderden_3.png")

    inst.AnimState:SetBank("sk_cocoon")
    inst.AnimState:SetBuild("sk_royal_throne")
    inst.AnimState:PlayAnimation("cocoon_large", true)
    inst.AnimState:SetScale(SCALE, SCALE)
    inst.AnimState:SetMultColour(unpack(EMPTY_TINT))

    inst:AddTag("structure")
    inst:AddTag(Thrones.THRONE_TAG)

    inst.displaynamefn = GetDisplayName

    -- Owner userid for clients (Affinity rituals collector); set by sk_royalthrone:SetOwner.
    inst._sk_owner = net_string(inst.GUID, Thrones.OWNER_NETVAR)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("sk_royalthrone")

    inst:AddComponent("inspectable")
    inst.components.inspectable.getstatus = GetStatus

    inst:AddComponent("lootdropper")

    inst:AddComponent("workable")
    inst.components.workable:SetWorkAction(ACTIONS.HAMMER)
    inst.components.workable:SetWorkLeft(TUNING.SPIDERKINGDOM.ROYAL_THRONE_WORK)
    inst.components.workable:SetOnFinishCallback(OnHammered)
    inst.components.workable:SetOnWorkCallback(OnHit)

    MakeHauntableWork(inst)

    MakeLargeBurnable(inst, nil, nil, true)
    inst.components.burnable:SetOnBurntFn(OnBurnt)
    -- Deconstruction Staff: removes the throne without OnHammered / OnBurnt (prefabs/staff_common.lua
    -- pushes "ondeconstructstructure", then Remove); the queen is released by the component's onremove.
    inst:ListenForEvent("ondeconstructstructure", DropRitualMaterials)
    MakeMediumPropagator(inst)

    inst:ListenForEvent("onignite", OnIgnite)
    inst:ListenForEvent("sk_thronechanged", RefreshVisual)
    inst:ListenForEvent("sk_queenvariantchanged", function(inst)
        if not inst:HasTag("burnt") then
            RefreshBuild(inst)
            inst.AnimState:PlayAnimation(GetHitAnim(inst))
            inst.AnimState:PushAnimation(GetIdleAnim(inst), true)
        end
    end)
    inst:ListenForEvent("sk_workshopchanged", RefreshTint)
    inst:ListenForEvent("sk_workshopactivated", OnWorkshopActivated)

    inst.OnSave = OnSave
    inst.OnLoad = OnLoad

    return inst
end

-- Royal Invitation -------------------------------------------------------------------------------

local function invitationfn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    MakeInventoryPhysics(inst)

    inst.AnimState:SetBank("sk_item")
    inst.AnimState:SetBuild("sk_royal_invitation")
    inst.AnimState:PlayAnimation("idle")

    -- Client: networking/item_actions.lua offers SK_ROYALINVITE for items with this tag.
    inst:AddTag(Thrones.INVITATION_TAG)

    inst.pickupsound = "paper"

    MakeInventoryFloatable(inst, "med", nil, 0.75)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("stackable")
    inst.components.stackable.maxsize = TUNING.STACK_SIZE_SMALLITEM

    inst:AddComponent("inspectable")

    inst:AddComponent("inventoryitem")

    MakeSmallBurnable(inst, TUNING.SMALL_BURNTIME)
    MakeSmallPropagator(inst)
    MakeHauntableLaunchAndIgnite(inst)

    return inst
end

return Prefab(Thrones.THRONE_PREFAB, fn, assets, prefabs),
    MakePlacer(Thrones.THRONE_PREFAB.."_placer", "sk_cocoon", "sk_royal_throne", "cocoon_large", nil, nil, nil, nil, nil, nil, placer_postinit),
    Prefab(Thrones.INVITATION_PREFAB, invitationfn, assets_invitation)
