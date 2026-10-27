-- M1 Spider Groomer: brain of the Spider Steed (prefabs/sk_spider_mount.lua) while nobody rides it
-- (a ridden mount's brain is hibernated by components/rider.lua). Modelled on brains/spiderbrain.lua,
-- reduced to: panic -> stand and face the owner while he is trying to mount it -> fight -> stand still while
-- its bag is open (M4) -> follow the owner -> face him -> wander near him / where it stands.
-- It is a separate brain on purpose: the mod's spiderbrain post-inits (courier wait, Stay order) and the
-- stock den / food / investigate logic do not apply to a mount.

require("behaviours/chaseandattack")
require("behaviours/follow")
require("behaviours/faceentity")
require("behaviours/standstill")
require("behaviours/wander")

local BrainCommon = require("brains/braincommon")

local MIN_FOLLOW_DIST = 2.5
local TARGET_FOLLOW_DIST = 5
local MAX_FOLLOW_DIST = 9

local MAX_CHASE_TIME = 10
local MAX_CHASE_DIST = 20

local MAX_WANDER_DIST = 8

local SpiderMountBrain = Class(Brain, function(self, inst)
    Brain._ctor(self, inst)
end)

local function GetLeader(inst)
    return inst.components.follower ~= nil and inst.components.follower:GetLeader() or nil
end

local function KeepFaceLeader(inst, target)
    return GetLeader(inst) == target
end

local function IsBagOpen(inst)
    return inst.components.container ~= nil and inst.components.container:IsOpen()
end

-- The owner walking up to mount: his buffered action, or on a client-predicted server the remote
-- interaction (same test as Woby, brains/wobycommon.lua GetPerformerActionOnMe). Without this the steed
-- keeps following and walks away from him, so he never reaches it.
local function IsMountingMe(inst, performer)
    if performer == nil or not performer:IsValid() then
        return false
    end
    local act = performer:GetBufferedAction()
    local action, target
    if act ~= nil then
        action, target = act.action, act.target
    elseif performer.components.playercontroller ~= nil then
        action, target = performer.components.playercontroller:GetRemoteInteraction()
    end
    return target == inst and action == ACTIONS.MOUNT
end

local function GetRider(inst)
    local leader = GetLeader(inst)
    return IsMountingMe(inst, leader) and leader or nil
end

local function KeepRider(inst, target)
    return IsMountingMe(inst, target)
end

local function GetWanderHome(inst)
    local leader = GetLeader(inst)
    if leader ~= nil and leader:IsValid() then
        return leader:GetPosition()
    end
    return inst.components.knownlocations:GetLocation("home")
end

function SpiderMountBrain:OnStart()
    local inst = self.inst

    local root = PriorityNode(
    {
        BrainCommon.PanicTrigger(inst),
        BrainCommon.ElectricFencePanicTrigger(inst),

        -- The owner walking up to mount it wins over fighting, otherwise a chase carries it away from him.
        FaceEntity(inst, GetRider, KeepRider),

        -- Spider Whistle recall (spider_whistle_buff sets no_targeting) also calls the mount back.
        WhileNode(function() return not inst.no_targeting end, "CanFight",
            ChaseAndAttack(inst, MAX_CHASE_TIME, MAX_CHASE_DIST)),

        WhileNode(function() return IsBagOpen(inst) end, "BagOpen",
            StandStill(inst)),


        Follow(inst, GetLeader, MIN_FOLLOW_DIST, TARGET_FOLLOW_DIST, MAX_FOLLOW_DIST),

        IfNode(function() return GetLeader(inst) ~= nil end, "HasLeader",
            FaceEntity(inst, GetLeader, KeepFaceLeader)),

        Wander(inst, GetWanderHome, MAX_WANDER_DIST),
    }, .25)

    self.bt = BT(inst, root)
end

function SpiderMountBrain:OnInitializationComplete()
    self.inst.components.knownlocations:RememberLocation("home", self.inst:GetPosition(), true)
end

return SpiderMountBrain
