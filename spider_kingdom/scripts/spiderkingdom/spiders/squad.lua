-- T4 Shared Squad. Webber with the skill lends up to SQUAD_MAX_GUARDS of his spiders to another player:
--   * right click another player with the stock Spider Whistle on the cursor: "Lend bodyguards" - his nearest
--     idle spiders within SQUAD_LEND_RADIUS (not couriers, workers or held spiders) follow and defend that player;
--   * the same on that player again: "Recall bodyguards" - they come back to Webber.
-- They stay Webber's: they return to him when the guarded player leaves the shard, migrates, dies, uses a
-- repellent, hits them or loses them to someone else, and on respec. With Webber away they wait in the world
-- store and come back when he is next on this shard (components/sk_squadstore.lua). Per-spider logic:
-- components/sk_guardian.lua; shared helpers: spiders/squad_common.lua; client collector branch:
-- Squad.CollectPlayerActions, called from networking/item_actions.lua.
--
-- Instance-level wrappers on every spider (chained after T1, courier and stance wrappers):
--   * combat SetTarget / CanTarget / CanHitTarget / keeptargetfn - never the owner or the guarded player,
--     other players and their friends only while provoking (T1 rules, see sk_guardian.lua);
--   * follower SetLeader - counts switches to a real leader, so sk_guardian can tell a lost leader from the
--     inner SetLeader(nil) of a leader change;
--   * OnEntitySleep - a guardian waiting for the store does not walk into its den (prefabs/spider.lua DoReturn);
--   * trader test - a non-owner cannot feed a mutator to a guardian (see also the spidermutator post-init);
--   * sanityaura aurafn - no negative aura while lent;
--   * halloweenmoonmutable Mutate - no moon potion mutation while lent.
-- An owner who migrates recalls his loans first (world listener below).

local _G = GLOBAL
local SKUtil = require("spiderkingdom/util")
local Squad = require("spiderkingdom/spiders/squad_common")

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
}

local function Say(doer, str)
    if doer.components.talker ~= nil and str ~= nil then
        doer.components.talker:Say(str)
    end
end

local function IsGuarding(inst)
    local guardian = inst.components.sk_guardian
    return guardian ~= nil and guardian:IsGuarding()
end

-- Spiders -------------------------------------------------------------------------------------

for _, prefab in ipairs(SPIDER_PREFABS) do
    AddPrefabPostInit(prefab, function(inst)
        -- Owner userid while lent (empty otherwise); clients use it for the Lend / Recall label.
        inst._sk_guardowner = _G.net_string(inst.GUID, "sk_guardian._owner")

        if not _G.TheWorld.ismastersim then
            return
        end

        inst:AddComponent("sk_guardian")
        local guardian = inst.components.sk_guardian

        local combat = inst.components.combat
        local SetTarget = combat.SetTarget
        combat.SetTarget = function(self, target, ...)
            if target ~= nil and guardian:ShouldIgnoreTarget(target) then
                return
            end
            return SetTarget(self, target, ...)
        end

        local CanTarget = combat.CanTarget
        combat.CanTarget = function(self, target, ...)
            if target ~= nil and guardian:IsProtected(target) then
                return false
            end
            return CanTarget(self, target, ...)
        end

        local CanHitTarget = combat.CanHitTarget
        combat.CanHitTarget = function(self, target, ...)
            if target ~= nil and guardian:IsProtected(target) then
                return false
            end
            return CanHitTarget(self, target, ...)
        end

        local keeptargetfn = combat.keeptargetfn
        combat.keeptargetfn = function(inst, target, ...)
            if target ~= nil and guardian:IsProtected(target) then
                return false
            end
            if keeptargetfn ~= nil then
                return keeptargetfn(inst, target, ...)
            end
            return true
        end

        -- Stock SetLeader nests and the outer call overwrites what an inner event handler did: sk_guardian only
        -- notes leader changes and decides once the outermost call has returned.
        local follower = inst.components.follower
        local SetLeader = follower.SetLeader
        follower.SetLeader = function(self, new_leader, ...)
            guardian.setleader_depth = guardian.setleader_depth + 1
            SetLeader(self, new_leader, ...)
            guardian.setleader_depth = guardian.setleader_depth - 1
            if guardian.setleader_depth == 0 then
                guardian:OnLeaderSettled()
            end
        end

        -- Stock suppression of the negative aura needs a spiderwhisperer leader (prefabs/spider.lua CalcSanityAura);
        -- a lent spider stays harmless to the guarded player and everyone around.
        local sanityaura = inst.components.sanityaura
        if sanityaura ~= nil then
            local aurafn = sanityaura.aurafn
            sanityaura.aurafn = function(inst, observer, ...)
                if guardian:IsGuarding() then
                    return 0
                end
                if aurafn ~= nil then
                    return aurafn(inst, observer, ...)
                end
                return inst.components.sanityaura.aura
            end
        end

        -- Moon potion (halloweenpotionmoon -> Mutate): the moon spider would follow the current leader without
        -- the loan. While lent nothing happens (the stock potion is still used up).
        local moonmutable = inst.components.halloweenmoonmutable
        if moonmutable ~= nil then
            local Mutate = moonmutable.Mutate
            moonmutable.Mutate = function(self, ...)
                if guardian:IsGuarding() then
                    return nil
                end
                return Mutate(self, ...)
            end
        end

        local OnEntitySleep = inst.OnEntitySleep
        if OnEntitySleep ~= nil then
            inst.OnEntitySleep = function(inst, ...)
                if guardian:BlocksGoHome() then
                    return
                end
                return OnEntitySleep(inst, ...)
            end
        end

        local trader = inst.components.trader
        if trader ~= nil and trader.test ~= nil then
            local test = trader.test
            trader.test = function(inst, item, giver, ...)
                if guardian:IsGuarding() and item ~= nil and item.components.spidermutator ~= nil
                    and not (giver ~= nil and giver.userid ~= nil and giver.userid == guardian.owner) then
                    return false
                end
                return test(inst, item, giver, ...)
            end
        end
    end)
end

-- Mutating replaces the spider with a new entity that follows the current leader (SGspider "mutate"):
-- a lent spider would silently become the guarded player's. Recall it first.
AddComponentPostInit("spidermutator", function(self)
    local CanMutate = self.CanMutate
    self.CanMutate = function(self, spider, ...)
        if spider ~= nil and IsGuarding(spider) then
            return false
        end
        return CanMutate(self, spider, ...)
    end
end)

-- Players: leaving players are never given spiders back (sk_guardian / sk_squadstore check this flag).
AddPlayerPostInit(function(inst)
    if not _G.TheWorld.ismastersim then
        return
    end
    local function OnLeaving(inst)
        inst._sk_despawning = true
    end
    inst:ListenForEvent("player_despawn", OnLeaving)
    inst:ListenForEvent("ms_playerreroll", OnLeaving)
end)

-- World: the store for spiders whose owner is away.
AddPrefabPostInit("world", function(inst)
    if not inst.ismastersim then
        return
    end
    inst:AddComponent("sk_squadstore")

    -- An owner who migrates takes his loan count with him: recall his bodyguards here, so the cap
    -- (SQUAD_MAX_GUARDS) holds on every shard. He is leaving, so they go into the world store and come back
    -- to him when he returns to this shard. A plain logout keeps them guarding (he comes back to this shard).
    inst:ListenForEvent("ms_playerdespawnandmigrate", function(world, data)
        local player = data ~= nil and data.player or nil
        if player ~= nil and player.userid ~= nil and player.userid ~= "" then
            player._sk_despawning = true
            Squad.Recall(player)
        end
    end)
end)

-- Action ---------------------------------------------------------------------------------------

local SK_SQUAD = _G.Action({ priority = 1, rmb = true, mount_valid = true })
SK_SQUAD.id = "SK_SQUAD"
SK_SQUAD.str = _G.STRINGS.ACTIONS.SK_SQUAD
SK_SQUAD.strfn = function(act)
    return Squad.HasGuardiansOn(act.doer, act.target) and "RECALL" or "LEND"
end
SK_SQUAD.fn = function(act)
    local doer, target, item = act.doer, act.target, act.invobject
    if doer == nil or target == nil or item == nil or item.prefab ~= "spider_whistle"
        or not SKUtil.HasSkill(doer, Squad.SKILL)
        or target == doer or not target:HasTag("player") or target.components.leader == nil
        or doer.components.leader == nil then
        return false
    end

    local strings = _G.STRINGS.SK_SQUAD

    -- Again on the same player: call them back.
    if Squad.CountLent(doer, target) > 0 then
        Squad.Recall(doer, target)
        Say(doer, strings ~= nil and strings.RECALLED or nil)
        return true
    end

    if not Squad.IsAvailable(target) then
        return false
    end

    local lent = Squad.Lend(doer, target)
    if lent == nil then
        return false, "LIMIT"
    elseif lent == 0 then
        return false, "NOSPIDERS"
    end
    Say(doer, strings ~= nil and strings.LENT ~= nil and string.format(strings.LENT, target.name or "?") or nil)
    return true
end
AddAction(SK_SQUAD)

AddStategraphActionHandler("wilson", _G.ActionHandler(_G.ACTIONS.SK_SQUAD, "give"))
AddStategraphActionHandler("wilson_client", _G.ActionHandler(_G.ACTIONS.SK_SQUAD, "give"))
