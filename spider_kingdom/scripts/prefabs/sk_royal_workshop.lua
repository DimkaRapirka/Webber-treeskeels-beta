-- R3 Royal Workshop goods, crafted only at an active Royal Throne (royalty/recipes.lua, nounlock):
--   * Brood Jelly: food. Webber gets a modest snack; a spider fed with it (the stock GIVE to a spider,
--     prefabs/spider.lua OnGetItemFromPlayer -> eater:Eat) heals completely. Official royal_jelly art, tinted.
--   * Royal Egg Sacks, one per brood type (royalty/workshops.lua BROODS): deploy into a tier 1 den that
--     always raises that spider type (components/sk_brood.lua "innate" brood). Based on the official
--     prefabs/spidereggsack.lua and the K1 egg sacks (prefabs/sk_spidereggsacks.lua).

require "prefabutil"

local Workshops = require("spiderkingdom/royalty/workshops")


-- Brood Jelly -------------------------------------------------------------------------------------

local jelly_assets =
{
    Asset("ANIM", "anim/sk_item.zip"),
    Asset("ANIM", "anim/sk_brood_jelly.zip"),
}

local jelly_prefabs =
{
    "spoiled_food",
    "spider_heal_target_fx",
}

local function OnJellyEaten(inst, eater)
    if eater == nil or not eater:IsValid() or eater:HasTag("player") or not eater:HasTag("spider") then
        return
    end
    local health = eater.components.health
    if health == nil or health:IsDead() then
        return
    end
    health:DoDelta(health.maxhealth, false, inst.prefab)

    -- Same effect the nurse spider uses on the spiders it heals (prefabs/spider.lua SpawnHealFx).
    local fx = SpawnPrefab("spider_heal_target_fx")
    if fx ~= nil then
        fx.Transform:SetNoFaced()
        fx.Transform:SetPosition(eater.Transform:GetWorldPosition())
    end
end

local function jellyfn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    MakeInventoryPhysics(inst)

    inst.AnimState:SetBank("sk_item")
    inst.AnimState:SetBuild("sk_brood_jelly")
    inst.AnimState:PlayAnimation("idle")

    MakeInventoryFloatable(inst, "small", nil, 0.8)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    -- MEAT: the stock spider diet, so Webber can hand it to any spider (and spiders pick it up to eat).
    inst:AddComponent("edible")
    inst.components.edible.foodtype = FOODTYPE.MEAT
    inst.components.edible.healthvalue = TUNING.SPIDERKINGDOM.BROOD_JELLY_HEALTH
    inst.components.edible.hungervalue = TUNING.SPIDERKINGDOM.BROOD_JELLY_HUNGER
    inst.components.edible.sanityvalue = TUNING.SPIDERKINGDOM.BROOD_JELLY_SANITY
    inst.components.edible:SetOnEatenFn(OnJellyEaten)

    -- The stock "Give" to a spider in the world comes from tradable (componentactions.lua).
    inst:AddComponent("tradable")

    inst:AddComponent("stackable")
    inst.components.stackable.maxsize = TUNING.STACK_SIZE_SMALLITEM

    inst:AddComponent("perishable")
    inst.components.perishable:SetPerishTime(TUNING.PERISH_MED)
    inst.components.perishable:StartPerishing()
    inst.components.perishable.onperishreplacement = "spoiled_food"

    inst:AddComponent("inspectable")

    inst:AddComponent("inventoryitem")

    MakeHauntableLaunch(inst)

    return inst
end

-- Royal Egg Sacks ---------------------------------------------------------------------------------

local eggsack_assets =
{
    Asset("ANIM", "anim/sk_item.zip"),
    Asset("ANIM", "anim/sk_royal_eggsack.zip"), -- one picture, tinted per brood (own icon per brood)
    Asset("SOUND", "sound/spider.fsb"),
}

local function MakeRoyalEggSack(brood)
    local name = Workshops.GetEggSackPrefab(brood)

    local prefabs =
    {
        "spiderden",
        brood.prefab,
    }

    local function ondeploy(inst, pt, deployer)
        inst.SoundEmitter:PlaySound("dontstarve/creatures/spider/spider_egg_sack")
        local den = SpawnPrefab("spiderden")
        if den ~= nil then
            den.Transform:SetPosition(pt:Get())
            PreventCharacterCollisionsWithPlacedObjects(den)
            if den.components.sk_brood ~= nil then
                den.components.sk_brood:SetBrood(brood.prefab, deployer ~= nil and deployer.userid or nil, true)
            end
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
        inst.AnimState:SetBuild("sk_royal_eggsack")
        inst.AnimState:PlayAnimation("idle")
        inst.AnimState:SetMultColour(unpack(brood.colour))

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

    return Prefab(name, fn, eggsack_assets, prefabs),
        MakePlacer(name.."_placer", "spider_cocoon", "spider_cocoon", "cocoon_small", nil, nil, nil, nil, nil, nil, placer_postinit)
end

local result = { Prefab(Workshops.JELLY_PREFAB, jellyfn, jelly_assets, jelly_prefabs) }
for _, brood in ipairs(Workshops.BROODS) do
    local sack, placer = MakeRoyalEggSack(brood)
    table.insert(result, sack)
    table.insert(result, placer)
end

return unpack(result)
