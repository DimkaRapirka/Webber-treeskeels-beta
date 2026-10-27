-- T2 Spider Mail: the courier spider and the kit that makes one.
--   sk_courier_kit   - crafted with the skill; used on one of your own spiders, it turns it into a courier.
--   sk_courierspider - the stock "spider" (built by its own prefab fn, so brain, stategraph and art are
--                      vanilla) plus a 6-slot container and the official mapdeliverable component, like
--                      the WX-78 delivery drone: right click "Send", pick a point on the map, it flies
--                      there, waits as an open container, then comes back (components/sk_mailspider.lua).
-- Visuals: stock spider with the courier cap in its hat slot (anim/sk_spider_hats.zip); own art for the kit.

local assets =
{
    Asset("ANIM", "anim/ui_tacklecontainer_3x2.zip"),
    Asset("ANIM", "anim/sk_spider_hats.zip"),
}

local prefabs =
{
    "spider",
    "spawn_fx_small",
}

local HAT_BUILD, HAT_SYMBOL = "sk_spider_hats", "swap_hat_courier"

-- The courier cap sits in the stock hat slot; a hat given to it replaces the cap, taking it off brings it back
-- (the stock hat unequip clears "swap_hat", prefabs/hats.lua).
local function ShowCap(inst)
    if inst.components.inventory == nil or inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HEAD) == nil then
        inst.AnimState:OverrideSymbol("swap_hat", HAT_BUILD, HAT_SYMBOL)
        inst.AnimState:Show("hat")
    end
end

-- Client and server: the official mapdeliverable collector (componentactions.lua) asks this
-- before offering STARTMAPDELIVER.
local function CanMapDeliver(inst, doer)
    local follower = inst.replica.follower
    return doer:HasTag("sk_mailer")
        and follower ~= nil and follower:GetLeader() == doer
        and not inst:HasTag("sk_away")
end

-- Map action handshake, as the WX-78 drone does it: closing the map interrupts the player's
-- continuous action, whose end ("stopcontinuousaction") clears mapdeliverable's buffered map action,
-- otherwise every later StartMapAction would fail until a reload.
local function OnStartMapAction(inst, doer)
    return inst.components.sk_mailspider:CanStartMapAction(doer)
end

local function OnCancelMapAction(inst, doer)
    if doer ~= nil then
        doer:PushEvent("interruptcontinuousaction", inst)
    end
end

local function OnStopContinuousAction(inst, doer)
    if not inst.components.mapdeliverable:IsDelivering() then
        inst.components.mapdeliverable:CancelMapAction()
    end
end

local function IsAway(inst)
    return inst.components.sk_mailspider ~= nil and inst.components.sk_mailspider:IsAway()
end

-- Away from the pack (flying or waiting at the destination) a courier does not fight.
local function WrapCombat(inst)
    local combat = inst.components.combat
    local SetTarget = combat.SetTarget
    combat.SetTarget = function(self, target, ...)
        if target ~= nil and IsAway(self.inst) then
            return
        end
        return SetTarget(self, target, ...)
    end
    local CanTarget = combat.CanTarget
    combat.CanTarget = function(self, target, ...)
        if IsAway(self.inst) then
            return false
        end
        return CanTarget(self, target, ...)
    end
    local CanHitTarget = combat.CanHitTarget
    combat.CanHitTarget = function(self, target, ...)
        if IsAway(self.inst) then
            return false
        end
        return CanHitTarget(self, target, ...)
    end
end

local function OnPreLoad(inst, data, ...)
    if inst._sk_spider_OnPreLoad ~= nil then
        inst._sk_spider_OnPreLoad(inst, data, ...)
    end
    if data ~= nil and data.sk_mailspider ~= nil then
        inst.components.sk_mailspider:OnLoad(data.sk_mailspider)
    end
end

local function fn()
    local inst = Prefabs.spider.fn(TheSim)

    inst:AddTag("sk_courierspider")
    -- Traps remove the spider without a death and keep only its prefab name: cargo and courier state
    -- would be lost (components/trap.lua).
    inst:RemoveTag("canbetrapped")
    inst.AnimState:OverrideSymbol("swap_hat", HAT_BUILD, HAT_SYMBOL)
    inst.AnimState:Show("hat")
    inst.canmapdeliver = CanMapDeliver

    if not TheWorld.ismastersim then
        return inst
    end

    -- Still during construction on the server: the "_container" tag reaches clients with the first
    -- snapshot, so they create the container replica (same as the K2 den container).
    inst:ListenForEvent("unequip", function(inst, data)
        if data ~= nil and data.eslot == EQUIPSLOTS.HEAD then
            inst:DoTaskInTime(0, ShowCap)
        end
    end)

    inst:AddComponent("container")
    inst.components.container:WidgetSetup("sk_courierspider")

    local courier = inst:AddComponent("sk_mailspider")

    inst:AddComponent("mapdeliverable")
    inst.components.mapdeliverable:SetDeliveryTimeFn(function(inst, dest) return courier:CalcDeliveryTime(dest) end)
    inst.components.mapdeliverable:SetOnStartDeliveryFn(function(inst, pt, doer) return courier:OnStartDelivery(pt, doer) end)
    inst.components.mapdeliverable:SetOnDeliveryProgressFn(function(inst, t, len, origin, dest) courier:OnDeliveryProgress(t, len, origin, dest) end)
    inst.components.mapdeliverable:SetOnStopDeliveryFn(function(inst) courier:OnStopDelivery() end)
    inst.components.mapdeliverable:SetOnStartMapActionFn(OnStartMapAction)
    inst.components.mapdeliverable:SetOnCancelMapActionFn(OnCancelMapAction)
    inst:ListenForEvent("stopcontinuousaction", OnStopContinuousAction)

    WrapCombat(inst)

    inst._sk_spider_OnPreLoad = inst.OnPreLoad
    inst.OnPreLoad = OnPreLoad

    -- Turning into another spider would drop the courier state and its cargo
    -- (moon potion / full moon, lunar corpse; mutators are blocked in colony/workers.lua).
    if inst.components.halloweenmoonmutable ~= nil then
        inst:RemoveComponent("halloweenmoonmutable")
    end
    if inst.sg ~= nil then
        inst.sg.mem.nolunarmutate = true
    end

    return inst
end

-- Kit -----------------------------------------------------------------------------------------


local function kitfn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    MakeInventoryPhysics(inst)

    inst.AnimState:SetBank("sk_item")
    inst.AnimState:SetBuild("sk_courier_kit")
    inst.AnimState:PlayAnimation("idle")

    inst:AddTag("sk_courier_kit")

    MakeInventoryFloatable(inst, "med", 0.05, {0.85, 0.6, 0.85})

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("inspectable")

    inst:AddComponent("inventoryitem")

    inst:AddComponent("stackable")
    inst.components.stackable.maxsize = TUNING.STACK_SIZE_LARGEITEM

    MakeSmallBurnable(inst)
    MakeSmallPropagator(inst)
    MakeHauntableLaunch(inst)

    return inst
end

return Prefab("sk_courierspider", fn, assets, prefabs),
    Prefab("sk_courier_kit", kitfn, { Asset("ANIM", "anim/sk_item.zip"), Asset("ANIM", "anim/sk_courier_kit.zip") })
