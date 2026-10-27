-- K1 Master of Dens: egg sacks that deploy straight into the official tier 2 / tier 3 dens
-- (spiderden_2 / spiderden_3 from prefabs/spiderden.lua). Based on the official prefabs/spidereggsack.lua.

require "prefabutil"

local assets =
{
    Asset("ANIM", "anim/spider_egg_sac.zip"), -- placer and deploy art stay the stock ones
    Asset("ANIM", "anim/sk_item.zip"),
    Asset("ANIM", "anim/sk_spidereggsack_2.zip"),
    Asset("ANIM", "anim/sk_spidereggsack_3.zip"),
    Asset("SOUND", "sound/spider.fsb"),
}

-- Own art per tier (Phase 6): bank sk_item, build sk_spidereggsack_<level> (art_src/tools/gen_items.py).

local PLACER_ANIM =
{
    [2] = "cocoon_medium",
    [3] = "cocoon_large",
}

local function MakeEggSack(level)
    local name = "sk_spidereggsack_"..level
    local denprefab = "spiderden_"..level

    local prefabs =
    {
        denprefab,
    }

    local function ondeploy(inst, pt, deployer)
        inst.SoundEmitter:PlaySound("dontstarve/creatures/spider/spider_egg_sack")
        local den = SpawnPrefab(denprefab)
        if den ~= nil then
            den.Transform:SetPosition(pt:Get())
            PreventCharacterCollisionsWithPlacedObjects(den)
            inst.components.stackable:Get():Remove()
        end
    end

    local function onpickup(inst)
        inst.SoundEmitter:PlaySound("dontstarve/creatures/spider/spider_egg_sack")
    end

    local function fn()
        local inst = CreateEntity()

        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddSoundEmitter()
        inst.entity:AddNetwork()

        MakeInventoryPhysics(inst)

        inst.AnimState:SetBank("sk_item")
        inst.AnimState:SetBuild("sk_spidereggsack_"..level)
        inst.AnimState:PlayAnimation("idle")

        inst:AddTag("cattoy")

        MakeInventoryFloatable(inst, "med", 0.05, {0.85, 0.6, 0.85})

        inst.entity:SetPristine()

        if not TheWorld.ismastersim then
            return inst
        end

        inst:AddComponent("stackable")
        inst.components.stackable.maxsize = TUNING.STACK_SIZE_LARGEITEM

        inst:AddComponent("inspectable")

        inst:AddComponent("fuel")
        inst.components.fuel.fuelvalue = TUNING.LARGE_FUEL

        MakeSmallBurnable(inst, TUNING.LARGE_BURNTIME)
        MakeSmallPropagator(inst)
        MakeHauntableLaunchAndIgnite(inst)

        inst:AddComponent("inventoryitem")
        inst.components.inventoryitem:SetOnPickupFn(onpickup)

        inst:AddComponent("deployable")
        inst.components.deployable.ondeploy = ondeploy

        return inst
    end

    local function placer_postinit(placer)
        placer.AnimState:HideSymbol("bedazzled_flare")
    end

    return Prefab(name, fn, assets, prefabs),
        MakePlacer(name.."_placer", "spider_cocoon", "spider_cocoon", PLACER_ANIM[level], nil, nil, nil, nil, nil, nil, placer_postinit)
end

local sack2, placer2 = MakeEggSack(2)
local sack3, placer3 = MakeEggSack(3)

return sack2, placer2, sack3, placer3
