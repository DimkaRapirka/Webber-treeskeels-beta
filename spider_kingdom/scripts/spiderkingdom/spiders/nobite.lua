-- T1 We Don't Bite (server). Applies only to spiders whose leader carries the "sk_nobite" tag
-- (set by the skill's onactivate, see spiders/nobite_common.lua).
--
-- Already vanilla, so nothing to do here:
--   * the sanity aura is 0 when the leader is a spiderwhisperer (prefabs/spider.lua CalcSanityAura);
--   * without PvP, other players and their followers count as allies (components/combat_replica.lua CanBeAlly).
-- What this file adds:
--   * no retaliation, pack sharing or leader assistance against an ally who hits the spider or Webber,
--     e.g. with splash damage; the spider keeps its current enemy;
--   * with PvP on, the spiders still leave players alone unless a player deliberately attacks
--     the spider or its leader (then that player is "provoking" for a short time).
--
-- Instance-level wrappers on the spider's combat component (the class is untouched):
--   * SetTarget  - every path that assigns a target goes through it (SuggestTarget, ShareTarget, OnAttacked);
--   * CanTarget  - used by the spider's FindTarget candidate filter and attack validity checks;
--   * CanHitTarget - checked when a swing actually lands;
--   * an "attacked" listener refreshes provocation on every deliberate PvP hit;
--   * keeptargetfn - drops a target once its provocation expires.

local _G = GLOBAL
local NoBite = require("spiderkingdom/spiders/nobite_common")

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
    "sk_spider_mount",  -- M1 Spider Steed
}

for _, prefab in ipairs(SPIDER_PREFABS) do
    AddPrefabPostInit(prefab, function(inst)
        if not _G.TheWorld.ismastersim then
            return
        end

        local combat = inst.components.combat

        local old_SetTarget = combat.SetTarget
        combat.SetTarget = function(self, target, ...)
            if target ~= nil and NoBite.ShouldIgnoreTarget(self.inst, target) then
                return
            end
            return old_SetTarget(self, target, ...)
        end

        local old_CanTarget = combat.CanTarget
        combat.CanTarget = function(self, target, ...)
            if target ~= nil and NoBite.IsProtected(self.inst, target) then
                return false
            end
            return old_CanTarget(self, target, ...)
        end

        -- Hit execution (SGspider attack states keep their target even after DropTarget).
        local old_CanHitTarget = combat.CanHitTarget
        combat.CanHitTarget = function(self, target, ...)
            if target ~= nil and NoBite.IsProtected(self.inst, target) then
                return false
            end
            return old_CanHitTarget(self, target, ...)
        end

        inst:ListenForEvent("attacked", function(inst, data)
            NoBite.RecordDeliberateHit(NoBite.GetNoBiteLeader(inst), inst, data ~= nil and data.attacker or nil)
        end)

        local old_keeptargetfn = combat.keeptargetfn
        combat.keeptargetfn = function(inst, target, ...)
            if NoBite.IsProtected(inst, target) then
                return false
            end
            if old_keeptargetfn ~= nil then
                return old_keeptargetfn(inst, target, ...)
            end
            return true
        end
    end)
end
