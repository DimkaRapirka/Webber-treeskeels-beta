-- sk_grooming (server only, on every stock spider_warrior): M1 Spider Groomer progress.
-- Every piece of meat-type food a Webber with the skill gives to his own Spider Warrior (stock GIVE,
-- counted by the trader wrapper in mounts/groomer.lua) adds one meal. With MOUNT_FEED_NEEDED meals and
-- at least MOUNT_MIN_DAYS world days since the first one, the warrior grows into sk_spider_mount: a new
-- entity spawned in its place, like the T2 courier kit does it (couriers/mail.lua).
--
-- Progress is saved with the spider, so it survives save/load and travels inside sk_spiderkeeper's save
-- records. The day count uses the world clock (TheWorld.state.cycles + time), which the caves share with
-- the surface (components/shard_clock.lua). A mutation (Switcherdoodle, moon) makes a new spider entity
-- and starts over.

local MountCommon = require("spiderkingdom/mounts/mount_common")
local SKUtil = require("spiderkingdom/util")

local GROW_DELAY = 1      -- after the last meal: let the stock "eat" animation play first
local RETRY_PERIOD = 10   -- ready but cannot grow right now (held, in limbo, owner away...)
local MAX_WAIT_STEP = 30  -- re-check the clock at least this often (sleeping skips world time)

local function CurrentDay()
    return TheWorld.state.cycles + TheWorld.state.time
end

local Grooming = Class(function(self, inst)
    self.inst = inst
    self.meals = 0
    self.firstday = nil
    self.task = nil
end)

function Grooming:IsFull()
    return self.meals >= TUNING.SPIDERKINGDOM.MOUNT_FEED_NEEDED
end

-- World days still to wait before a full spider may grow (0 when it may grow now).
function Grooming:GetDaysLeft()
    if self.firstday == nil then
        return TUNING.SPIDERKINGDOM.MOUNT_MIN_DAYS
    end
    return math.max(0, self.firstday + TUNING.SPIDERKINGDOM.MOUNT_MIN_DAYS - CurrentDay())
end

-- The follower leader if he can raise a mount from this spider now.
function Grooming:GetGroomer()
    local inst = self.inst
    local follower = inst.components.follower
    local leader = follower ~= nil and follower:GetLeader() or nil
    if leader ~= nil
        and leader:IsValid()
        and leader:HasTag("player")
        and not leader:HasTag("playerghost")
        and not MountCommon.IsLeaving(leader)
        and leader.components.leader ~= nil
        and SKUtil.HasSkill(leader, MountCommon.SKILL) then
        return leader
    end
end

-- Spiders that must not count meals or grow: lent T4 bodyguards (their leader is not their owner),
-- K3 workers (stock "spider", never warriors, checked anyway), dead ones.
function Grooming:CanBeGroomed()
    local inst = self.inst
    return inst:IsValid()
        and inst.prefab == MountCommon.GROOM_PREFAB
        and not inst:HasTag("sk_guardian")
        and not inst:HasTag("sk_worker")
        and not (inst.components.health ~= nil and inst.components.health:IsDead())
end

-- Not while held in an inventory, out of the scene, mutating or being removed.
function Grooming:CanGrowNow()
    local inst = self.inst
    return self:CanBeGroomed()
        and not inst:IsInLimbo()
        and not (inst.components.inventoryitem ~= nil and inst.components.inventoryitem:IsHeld())
        and inst.mutation_target == nil
        and not (inst.sg ~= nil and inst.sg:HasStateTag("mutating"))
end

-- Called by the trader wrapper (mounts/groomer.lua) after the stock spider accepted a meat meal from giver.
function Grooming:OnFed(giver)
    if giver == nil or not self:CanBeGroomed() or self:GetGroomer() ~= giver then
        return
    end

    local needed = TUNING.SPIDERKINGDOM.MOUNT_FEED_NEEDED
    if self.firstday == nil then
        self.firstday = CurrentDay()
    end
    if self.meals < needed then
        self.meals = self.meals + 1
    end

    if not self:IsFull() then
        MountCommon.Say(giver, string.format(STRINGS.SK_MOUNT.PROGRESS, self.meals, needed))
        return
    end

    if self:GetDaysLeft() > 0 then
        MountCommon.Say(giver, STRINGS.SK_MOUNT.FULL_WAIT)
    end
    self:Schedule(GROW_DELAY)
end

function Grooming:Schedule(delay)
    if self.task ~= nil then
        self.task:Cancel()
    end
    self.task = self.inst:DoTaskInTime(delay, function() self.task = nil self:TryGrow() end)
end

function Grooming:TryGrow()
    if not self:IsFull() then
        return
    end

    local daysleft = self:GetDaysLeft()
    if daysleft > 0 then
        self:Schedule(math.min(MAX_WAIT_STEP, math.max(1, daysleft * TUNING.TOTAL_DAY_TIME)))
        return
    end

    local owner = self:GetGroomer()
    if owner == nil or not self:CanGrowNow() then
        self:Schedule(RETRY_PERIOD)
        return
    end

    self:Grow(owner)
end

-- Replaces the warrior with a mount that follows owner. Returns the mount.
function Grooming:Grow(owner)
    local inst = self.inst
    local mount = SpawnPrefab(MountCommon.MOUNT_PREFAB)
    if mount == nil then
        return nil
    end

    local x, y, z = inst.Transform:GetWorldPosition()
    mount.Transform:SetPosition(x, y, z)
    mount.Transform:SetRotation(inst.Transform:GetRotation())
    if inst.components.health ~= nil and mount.components.health ~= nil then
        mount.components.health:SetPercent(inst.components.health:GetPercent())
    end
    -- Its hat (anything it carried) stays on the ground.
    if inst.components.inventory ~= nil then
        inst.components.inventory:DropEverything()
    end
    mount.components.sk_spidermount:SetOwnerUserId(owner.userid)

    if self.task ~= nil then
        self.task:Cancel()
        self.task = nil
    end
    inst:Remove()

    -- Bonded by sk_spiderkeeper through the follower hooks; links the owner in sk_spidermount.
    owner.components.leader:AddFollower(mount)

    local fx = SpawnPrefab("spider_mutate_fx")
    if fx ~= nil then
        fx.Transform:SetPosition(x, y, z)
    end
    MountCommon.Say(owner, STRINGS.SK_MOUNT.GROWN)
    return mount
end

function Grooming:OnSave()
    if self.meals > 0 then
        return { meals = self.meals, firstday = self.firstday }
    end
end

function Grooming:OnLoad(data)
    if data == nil then
        return
    end
    self.meals = math.min(data.meals or 0, TUNING.SPIDERKINGDOM.MOUNT_FEED_NEEDED)
    self.firstday = data.firstday
    if self:IsFull() then
        -- The leader is attached after the load (sk_spiderkeeper / follower cache): try a bit later.
        self:Schedule(RETRY_PERIOD)
    end
end

function Grooming:OnRemoveFromEntity()
    if self.task ~= nil then
        self.task:Cancel()
        self.task = nil
    end
end

function Grooming:GetDebugString()
    return string.format("meals: %d/%d, days left: %.2f", self.meals, TUNING.SPIDERKINGDOM.MOUNT_FEED_NEEDED, self:GetDaysLeft())
end

return Grooming
