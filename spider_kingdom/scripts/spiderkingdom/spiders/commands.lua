-- Basic spider commands (no Insight cost) with the stock Spider Whistle, until a command UI exists:
--   * use the whistle from the inventory: stock HERD_FOLLOWERS (summon + 10 s passive buff), unchanged;
--   * use the whistle on one of your spiders: SK_SPIDERSTANCE cycles the orders of all your spiders,
--     follow -> attack -> defend -> passive -> stay (inventory tiles cannot tell left from right
--     click, so the stock whistle action stays on the tile);
--   * use the whistle on a spider den: SK_SENDHOME, nearby spiders return home: each to its own den,
--     homeless ones into this den (they become den children again, like spiders going home in vanilla).
-- See spiders/stances.lua and components/sk_spidercommander.lua. Client collectors: networking/item_actions.lua.

local _G = GLOBAL
local Stances = require("spiderkingdom/spiders/stances")

_G.require("behaviours/leash")
_G.require("behaviours/standstill")

local SPIDER_PREFABS =
{
    "spider",
    "spider_warrior",
    "spider_hider",
    "spider_spitter",
    "spider_dropper",
    "spider_moon",
    "spider_healer",
    "spider_water",
    "sk_courierspider", -- T2 courier (stock spider fn under its own prefab name)
}

local function Say(doer, str)
    if doer.components.talker ~= nil and str ~= nil then
        doer.components.talker:Say(str)
    end
end

-- Webber -------------------------------------------------------------------------------------

AddPrefabPostInit("webber", function(inst)
    if not _G.TheWorld.ismastersim then
        return
    end

    inst:AddComponent("sk_spidercommander")

    -- Official per-character follower hooks (prefabs/player_common.lua); chain earlier ones (sk_spiderkeeper).
    local old_added = inst.additional_OnFollowerAdded
    local old_removed = inst.additional_OnFollowerRemoved
    inst.additional_OnFollowerAdded = function(inst, follower)
        if old_added ~= nil then
            old_added(inst, follower)
        end
        inst.components.sk_spidercommander:OnFollowerAdded(follower)
    end
    inst.additional_OnFollowerRemoved = function(inst, follower)
        if old_removed ~= nil then
            old_removed(inst, follower)
        end
        inst.components.sk_spidercommander:OnFollowerRemoved(follower)
    end
end)

-- Spiders: stance-aware combat (instance wrappers, chained after T1 / courier wrappers) ---------

for _, prefab in ipairs(SPIDER_PREFABS) do
    AddPrefabPostInit(prefab, function(inst)
        if not _G.TheWorld.ismastersim then
            return
        end
        local combat = inst.components.combat

        local old_targetfn = combat.targetfn
        if old_targetfn ~= nil then
            combat.targetfn = function(inst, ...)
                if Stances.BlocksRetarget(inst) then
                    return nil
                end
                return old_targetfn(inst, ...)
            end
        end

        local SetTarget = combat.SetTarget
        combat.SetTarget = function(self, target, ...)
            if target ~= nil and Stances.BlocksAllTargets(self.inst) then
                return
            end
            return SetTarget(self, target, ...)
        end

        local CanHitTarget = combat.CanHitTarget
        combat.CanHitTarget = function(self, target, ...)
            if Stances.BlocksAllTargets(self.inst) then
                return false
            end
            return CanHitTarget(self, target, ...)
        end
    end)
end

-- Stay: inserted right after the stock attack nodes (found by the ChaseAndAttack node's name), so a
-- staying spider still fights but holds its spot instead of following.
local function ContainsNamed(node, name)
    if node.name == name then
        return true
    end
    if node.children ~= nil then
        for _, child in ipairs(node.children) do
            if ContainsNamed(child, name) then
                return true
            end
        end
    end
    return false
end

AddBrainPostInit("spiderbrain", function(brain)
    local inst = brain.inst
    local root = brain.bt ~= nil and brain.bt.root or nil
    if root == nil or root.children == nil then
        return
    end

    local index = #root.children
    for i, child in ipairs(root.children) do
        if ContainsNamed(child, "ChaseAndAttack") then
            index = i + 1
            break
        end
    end

    local node = _G.WhileNode(function() return Stances.IsStaying(inst) end, "SKStay",
        _G.PriorityNode({
            _G.Leash(inst, function() return Stances.GetStayAnchor(inst) end, 3, 1.5),
            _G.StandStill(inst),
        }, .25))
    node.parent = root
    table.insert(root.children, index, node)
end)

-- Actions ------------------------------------------------------------------------------------

local SK_SPIDERSTANCE = _G.Action({ priority = 1, mount_valid = true })
SK_SPIDERSTANCE.id = "SK_SPIDERSTANCE"
SK_SPIDERSTANCE.str = _G.STRINGS.ACTIONS.SK_SPIDERSTANCE
SK_SPIDERSTANCE.fn = function(act)
    local doer, spider, item = act.doer, act.target, act.invobject
    local commander = doer ~= nil and doer.components.sk_spidercommander or nil
    if commander == nil or item == nil or item.prefab ~= "spider_whistle"
        or spider == nil or spider.components.follower == nil or spider.components.follower:GetLeader() ~= doer then
        return false
    end
    local stance = commander:CycleStance()
    Say(doer, _G.STRINGS.SK_STANCES[string.upper(stance)])
    return true
end
AddAction(SK_SPIDERSTANCE)

local function IsDenUsable(den)
    return den ~= nil and den:IsValid() and den.components.childspawner ~= nil
        and not den:HasTag("burnt")
        and not (den.components.health ~= nil and den.components.health:IsDead())
end

local function GetHomeSpawner(spider)
    local home = spider.components.homeseeker ~= nil and spider.components.homeseeker.home or nil
    return home, IsDenUsable(home) and home.components.childspawner or nil
end

local function IsOwnedBy(childspawner, spider)
    return childspawner.childrenoutside[spider] ~= nil or childspawner.emergencychildrenoutside[spider] ~= nil
end

-- Pool a new (homeless) spider would join in this den, if there is room: "regular" first (also when
-- warriors are disabled and both names are "spider"), then "emergency". Other mutations would lose
-- their type in the den (childspawner otherchildreninside double-counts), so they are not admitted.
local function GetAdmitPool(childspawner, spider)
    if spider.prefab == childspawner.childname
        and childspawner.childreninside + childspawner.numchildrenoutside < childspawner.maxchildren then
        return "regular"
    end
    if spider.prefab == childspawner.emergencychildname
        and childspawner:NumEmergencyChildren() < childspawner.maxemergencychildren then
        return "emergency"
    end
    return nil
end

-- pool: nil when the spider is already owned by this den.
local function SendIntoDen(spider, childspawner, pool)
    spider.components.follower:StopFollowing()
    if pool == "emergency" then
        childspawner:TakeEmergencyOwnership(spider)
    elseif pool == "regular" then
        childspawner:TakeOwnership(spider)
    end
    local fx = _G.SpawnPrefab("spawn_fx_small")
    if fx ~= nil then
        fx.Transform:SetPosition(spider.Transform:GetWorldPosition())
    end
    childspawner:GoHome(spider) -- the den's ongohome drops a worn hat (prefabs/spiderden.lua OnGoHome)
end

local SK_SENDHOME = _G.Action({ priority = 1 })
SK_SENDHOME.id = "SK_SENDHOME"
SK_SENDHOME.str = _G.STRINGS.ACTIONS.SK_SENDHOME
SK_SENDHOME.fn = function(act)
    local doer, den = act.doer, act.target
    if doer == nil or den == nil or not doer:HasTag("spiderwhisperer") or doer.components.leader == nil
        or den.components.childspawner == nil or den:HasTag("burnt")
        or (den.components.health ~= nil and den.components.health:IsDead()) then
        return false
    end

    local childspawner = den.components.childspawner
    local radius_sq = TUNING.SPIDERKINGDOM.COMMAND_HOME_RADIUS * TUNING.SPIDERKINGDOM.COMMAND_HOME_RADIUS
    local spiders = {}
    for follower in pairs(doer.components.leader.followers) do
        if follower:IsValid() and follower:HasTag("spider") and not follower:HasTag("spiderqueen")
            and not follower:HasTag("sk_worker") and not Stances.IsCouriering(follower)
            and not follower:HasTag("sk_guardian") -- a borrowed T4 bodyguard is not yours to send home
            and not follower:HasTag("sk_mount") -- M1 Spider Steed does not live in a den
            and not (follower.components.health ~= nil and follower.components.health:IsDead())
            and follower:GetDistanceSqToInst(doer) <= radius_sq then
            table.insert(spiders, follower)
        end
    end
    if #spiders == 0 then
        return false, "NOSPIDERS"
    end

    local sent = 0
    for _, spider in ipairs(spiders) do
        local home, homespawner = GetHomeSpawner(spider)
        if home ~= nil then
            -- Back to its own den: it is already counted there, no capacity check.
            -- A dead or burnt home would just consume the spider: it stays with Webber then.
            if homespawner ~= nil and IsOwnedBy(homespawner, spider) then
                SendIntoDen(spider, homespawner, nil)
                sent = sent + 1
            end
        else
            local pool = GetAdmitPool(childspawner, spider)
            if pool ~= nil then
                SendIntoDen(spider, childspawner, pool)
                sent = sent + 1
            end
        end
    end

    if sent == 0 then
        return false, "FULL"
    end
    return true
end
AddAction(SK_SENDHOME)

AddStategraphActionHandler("wilson", _G.ActionHandler(_G.ACTIONS.SK_SPIDERSTANCE, "give"))
AddStategraphActionHandler("wilson_client", _G.ActionHandler(_G.ACTIONS.SK_SPIDERSTANCE, "give"))
AddStategraphActionHandler("wilson", _G.ActionHandler(_G.ACTIONS.SK_SENDHOME, "give"))
AddStategraphActionHandler("wilson_client", _G.ActionHandler(_G.ACTIONS.SK_SENDHOME, "give"))
