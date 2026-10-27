-- K3 Worker Brood: wiring for components/sk_workerhive.lua (dens) and components/sk_worker.lua (spiders).
-- Workers are stock "spider" prefabs led by their den. This file keeps them out of fights, trades,
-- mutations and sanity auras, and adds the brain node that walks them to their current target.
-- K4 haulers are the same workers with the profession "hauler" (storage dens), so all of this applies.

local _G = GLOBAL

_G.require("behaviours/follow")
_G.require("behaviours/standstill")

local function IsWorker(inst)
    return inst.components.sk_worker ~= nil and inst.components.sk_worker:IsActive()
end

-- Dens ---------------------------------------------------------------------------------------

AddPrefabPostInit("spiderden", function(inst)
    if _G.TheWorld.ismastersim then
        inst:AddComponent("sk_workerhive")
    end
end)

-- Workers ------------------------------------------------------------------------------------

AddPrefabPostInit("spider", function(inst)
    if not _G.TheWorld.ismastersim then
        return
    end

    inst:AddComponent("sk_worker")

    -- No fighting (instance wrappers chain any earlier ones: T1, courier, commands).
    local combat = inst.components.combat
    local SetTarget = combat.SetTarget
    combat.SetTarget = function(self, target, ...)
        if target ~= nil and IsWorker(self.inst) then
            return
        end
        return SetTarget(self, target, ...)
    end
    local CanTarget = combat.CanTarget
    combat.CanTarget = function(self, target, ...)
        if IsWorker(self.inst) then
            return false
        end
        return CanTarget(self, target, ...)
    end
    local CanHitTarget = combat.CanHitTarget
    combat.CanHitTarget = function(self, target, ...)
        if IsWorker(self.inst) then
            return false
        end
        return CanHitTarget(self, target, ...)
    end

    -- No sanity drain on players around the colony (the stock aura is only 0 for Webber's followers).
    local sanityaura = inst.components.sanityaura
    if sanityaura ~= nil then
        local aurafn = sanityaura.aurafn
        sanityaura.aurafn = function(inst, observer, ...)
            if IsWorker(inst) then
                return 0
            end
            return aurafn ~= nil and aurafn(inst, observer, ...) or sanityaura.aura
        end
    end

    -- Not befriendable or dressable: feeding would make it leave its den (and vanish without a home).
    local trader = inst.components.trader
    if trader ~= nil then
        local test, abletest = trader.test, trader.abletoaccepttest
        trader:SetAcceptTest(function(inst, ...)
            if IsWorker(inst) then
                return false
            end
            return test == nil or test(inst, ...)
        end)
        trader:SetAbleToAcceptTest(function(inst, ...)
            if IsWorker(inst) then
                return false
            end
            if abletest ~= nil then
                return abletest(inst, ...)
            end
            return true
        end)
    end
end)

-- A mutation replaces the spider entity and would drop the worker state (and a T2 courier's
-- container and delivery state).
local function IsProtectedFromMutation(spider)
    return IsWorker(spider) or spider:HasTag("sk_courierspider")
end

AddComponentPostInit("spidermutator", function(self)
    local Mutate = self.Mutate
    self.Mutate = function(self, spider, ...)
        if spider ~= nil and IsProtectedFromMutation(spider) then
            return false
        end
        return Mutate(self, spider, ...)
    end
    local CanMutate = self.CanMutate
    if CanMutate ~= nil then
        self.CanMutate = function(self, spider, ...)
            if spider ~= nil and IsProtectedFromMutation(spider) then
                return false
            end
            return CanMutate(self, spider, ...)
        end
    end
end)

-- Brain: walk to sk_worker:GetMoveTarget(). Inserted right after the stock panic nodes
-- (brains/spiderbrain.lua root = { pre_nodes, hider_nodes, attack_nodes, follow_nodes, post_nodes }).
AddBrainPostInit("spiderbrain", function(brain)
    local inst = brain.inst
    local root = brain.bt ~= nil and brain.bt.root or nil
    local worker = inst.components.sk_worker
    if root == nil or root.children == nil or worker == nil then
        return
    end

    -- Dens (home, deposit, K4 fetch / deliver) are kept at a den's distance, trees and items closer.
    local function AtHome()
        return worker:IsGoingToDen()
    end

    local node = _G.WhileNode(function() return worker:IsActive() end, "SKWorker",
        _G.PriorityNode({
            _G.IfNode(function() return worker:GetMoveTarget() ~= nil end, "HasWorkTarget",
                _G.Follow(inst, function() return worker:GetMoveTarget() end,
                    0,
                    function() return AtHome() and 2.5 or 1 end,
                    function() return AtHome() and 3 or 1.5 end,
                    true)),
            _G.StandStill(inst),
        }, .25))
    node.parent = root
    table.insert(root.children, math.min(2, #root.children + 1), node)
end)
