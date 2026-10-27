-- R4 Royal Expedition: the Spider Queen's brain while she travels with her Webber.
-- Swapped in by royalty/expeditions.lua (EntityScript:SetBrain) and swapped back to her stock brain when
-- she goes wild. Compared with the stock brains/spiderqueenbrain.lua it has no "can plant nest" (makenest
-- turns her into a den) and no "needs follower" (poop_pre -> incrementalproducer spawns wild spiders)
-- nodes, and follows her leader instead of wandering. Combat targets come from the leader
-- (components/leader.lua OnAttacked / OnNewTarget suggest them) and from the expedition retarget function.
-- Reads the expedition state from inst._sk_expedition only, so it requires nothing from the mod.

require "behaviours/chaseandattack"
require "behaviours/follow"
require "behaviours/faceentity"
require "behaviours/leash"
require "behaviours/standstill"
require "behaviours/wander"
local BrainCommon = require("brains/braincommon")

local WANDER_DIST = 8

local QueenExpeditionBrain = Class(Brain, function(self, inst)
    Brain._ctor(self, inst)
end)

local function GetLeader(inst)
    return inst.components.follower ~= nil and inst.components.follower:GetLeader() or nil
end

local function KeepFaceLeader(inst, target)
    return GetLeader(inst) == target
end

local function IsAlive(inst)
    return not (inst.components.health ~= nil and inst.components.health:IsDead())
end

-- Walking back to her throne after "Send the queen home" (royalty/expeditions.lua SendHome).
local function GetHomePos(inst)
    local expedition = inst._sk_expedition
    return expedition ~= nil and expedition.gohome ~= nil and expedition.gohome.pos or nil
end

local function IsGoingHome(inst)
    return GetHomePos(inst) ~= nil
end

local function GetWanderHome(inst)
    local leader = GetLeader(inst)
    return leader ~= nil and leader:GetPosition() or inst:GetPosition()
end

function QueenExpeditionBrain:OnStart()
    local inst = self.inst
    local tuning = TUNING.SPIDERKINGDOM

    local root = PriorityNode(
    {
        WhileNode(function() return IsAlive(inst) end, "Alive",
            PriorityNode(
            {
                BrainCommon.PanicTrigger(inst),
                BrainCommon.ElectricFencePanicTrigger(inst),

                WhileNode(function() return IsGoingHome(inst) end, "SKGoHome",
                    PriorityNode(
                    {
                        Leash(inst, GetHomePos, 1, 0.5),
                        StandStill(inst),
                    }, .25)),

                ChaseAndAttack(inst, tuning.ROYAL_EXPEDITION_CHASE_TIME),

                Follow(inst, GetLeader,
                    tuning.ROYAL_EXPEDITION_FOLLOW_MIN, tuning.ROYAL_EXPEDITION_FOLLOW_TARGET, tuning.ROYAL_EXPEDITION_FOLLOW_MAX,
                    false),
                IfNode(function() return GetLeader(inst) ~= nil end, "HasLeader",
                    FaceEntity(inst, GetLeader, KeepFaceLeader)),

                -- Only for the moment between losing her leader and royalty/expeditions.lua deciding.
                Wander(inst, GetWanderHome, WANDER_DIST),
            }, .25)),
    }, .25)

    self.bt = BT(inst, root)
end

return QueenExpeditionBrain
