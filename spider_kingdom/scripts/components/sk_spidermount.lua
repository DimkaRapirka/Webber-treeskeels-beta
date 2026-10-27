-- sk_spidermount (server only, on sk_spider_mount): M1 Spider Groomer, the mount's owner and riding rules.
--
--   * Owner = the follower leader (a player). Only he may ride, and only while he has the M1 skill:
--     rideable.canride (and so the "rideable" tag the client MOUNT collector needs) follows his skill,
--     the custom rider test (rideable:SetCustomRiderTest) checks both again on the server.
--     Respec: the mount stays his follower and keeps fighting, it just cannot be ridden; a ridden mount
--     throws him off gently.
--   * The owner's userid is saved. A mount that lost its leader (Spider Hat, reroll, a conflicting mod...)
--     goes back to its owner when he is near again, or to him when he feeds it. A mount without any saved
--     owner (e.g. spawned from the console) can be claimed the same way by a Webber with the skill.
--   * Mounting while it fights: the stock MOUNT action fails with TARGETINCOMBAT when the mount has a
--     combat target (actions.lua ACTIONS.MOUNT.fn). The owner's own MOUNT action makes it drop the target
--     first ("performaction" is pushed right before the action runs, entityscript.lua PerformBufferedAction).
--   * Death while ridden: like the beefalo (prefabs/beefalo.lua OnDeath / OnRiderChanged): the stategraph
--     is stopped while it is out of the scene, so buck the rider off and enter "death" after the dismount.
--
--   * Perks of the owner's other Rider skills (RefreshPerks, on every owner / skill / rider change):
--     M2 Cavalry Dash: "ondash_woby" (pushed on the mount by the stock dash state) starts the rider's
--       cooldown (mounts/dash.lua, mounts/mount_common.lua).
--     M3 Battle Rider: +20% on the steed's combat while its owner rides it (mounted melee damage is the
--       mount's, combat.lua CalcDamage); every MOUNT_BITE_EVERY-th mounted hit bites around the target.
--     M4 Faithful Mount: saddlebag (container, owner only through restrictedtag), regeneration out of
--       combat, +10% run speed (SetRunSpeed keeps player_classified.riderrunspeed in sync).
--
-- Shard migration, logout and save/load go through sk_spiderkeeper like every other spider of Webber;
-- the rider is dismounted by player_common OnDespawn before his session is serialized. The saddlebag's
-- items are part of the steed's save record (container OnSave) and are removed with it (they are its
-- children, EntityScript:Remove).

local MountCommon = require("spiderkingdom/mounts/mount_common")
local SKUtil = require("spiderkingdom/util")

local RECLAIM_PERIOD = 3
local REBUCK_PERIOD = 1
local BATTLE_KEY = "sk_battle_rider"

local BITE_MUST_TAGS = { "_combat", "_health" }
local BITE_CANT_TAGS = { "INLIMBO", "notarget", "noattack", "flight", "invisible", "playerghost", "wall", "structure", "companion" }

local function IsDead(inst)
    return inst.components.health ~= nil and inst.components.health:IsDead()
end

local SpiderMount = Class(function(self, inst)
    self.inst = inst
    self.owner = nil         -- player entity while he is the follower leader
    self.owner_userid = nil  -- saved
    self.reclaimtask = nil
    self.bucktask = nil
    self.regentask = nil
    self.bagtag = nil        -- container.restrictedtag while an owner is linked
    self.hits = 0            -- M3 mounted hits towards the next bite
    self.biting = false

    self._onownerskill = function(owner, data)
        if data == nil or MountCommon.RIDER_SKILLS[data.skill] then
            self:RefreshRideable(true)
        end
    end
    self._onownerskilltreeinit = function(owner)
        self:RefreshRideable(true)
    end
    self._onownerperformaction = function(owner, data)
        self:OnOwnerPerformAction(owner, data)
    end
    -- Seamless character swap (Celestial Portal, Wonkey curse): the old player entity is only hidden,
    -- it never goes through OnDespawn. Put the mount back into the world first.
    self._onownerhitother = function(owner, data)
        self:OnOwnerHitOther(owner, data)
    end
    self._onownerreroll = function(owner)
        if inst.components.rideable:GetRider() == owner and owner.components.rider ~= nil then
            owner.components.rider:ActualDismount()
        end
    end

    inst:ListenForEvent("leaderchanged", function(inst, data) self:OnLeaderChanged(data) end)
    inst:ListenForEvent("riderchanged", function(inst, data) self:OnRiderChanged(data) end)
    inst:ListenForEvent("death", function(inst, data) self:OnDeath(data) end)
    inst:ListenForEvent("ondash_woby", function(inst)
        local rider = inst.components.rideable:GetRider()
        if rider ~= nil then
            MountCommon.StartDashCooldown(rider)
        end
    end)

    -- Loaded from the world save without a leader (e.g. its owner rerolled, or a conflicting transfer mod
    -- left it in the world): look for the owner. Mounts restored by sk_spiderkeeper or just grown get
    -- their leader in the same frame, before this runs.
    inst:DoTaskInTime(0, function()
        if inst.components.follower:GetLeader() == nil then
            self:StartReclaim()
        end
    end)
end)

function SpiderMount:GetOwner()
    return self.owner
end

function SpiderMount:SetOwnerUserId(userid)
    if userid ~= nil and userid ~= "" then
        self.owner_userid = userid
    end
end

-- Server rider test (rideable:SetCustomRiderTest).
function SpiderMount:CanBeRiddenBy(rider)
    return rider ~= nil
        and rider == self.owner
        and not IsDead(self.inst)
        and SKUtil.HasSkill(rider, MountCommon.SKILL)
end

-- Mount speed for the rider (same as Woby, prefabs/wobybig.lua SetRunSpeed): rider_replica copies the
-- mount's runspeed into player_classified.riderrunspeed when he mounts, later changes need this.
-- For M4 Faithful Mount and other speed changes.
function SpiderMount:SetRunSpeed(speed)
    self.inst.components.locomotor.runspeed = speed
    local rider = self.inst.components.rideable:GetRider()
    if rider ~= nil and rider.player_classified ~= nil then
        rider.player_classified.riderrunspeed:set(speed)
    end
end

-- Owner link ------------------------------------------------------------------------------------

function SpiderMount:LinkOwner(player)
    if self.owner == player then
        return
    end
    self:UnlinkOwner()

    self.owner = player
    self:SetOwnerUserId(player.userid)
    self:StopReclaim()

    local inst = self.inst
    inst:ListenForEvent("onactivateskill_server", self._onownerskill, player)
    inst:ListenForEvent("ondeactivateskill_server", self._onownerskill, player)
    inst:ListenForEvent("ms_skilltreeinitialized", self._onownerskilltreeinit, player)
    inst:ListenForEvent("performaction", self._onownerperformaction, player)
    inst:ListenForEvent("ms_playerreroll", self._onownerreroll, player)
    inst:ListenForEvent("onhitother", self._onownerhitother, player)

    self:RestrictBag(player)
end

function SpiderMount:UnlinkOwner()
    local player = self.owner
    if player == nil then
        return
    end
    self.owner = nil

    local inst = self.inst
    inst:RemoveEventCallback("onactivateskill_server", self._onownerskill, player)
    inst:RemoveEventCallback("ondeactivateskill_server", self._onownerskill, player)
    inst:RemoveEventCallback("ms_skilltreeinitialized", self._onownerskilltreeinit, player)
    inst:RemoveEventCallback("performaction", self._onownerperformaction, player)
    inst:RemoveEventCallback("ms_playerreroll", self._onownerreroll, player)
    inst:RemoveEventCallback("onhitother", self._onownerhitother, player)

    self.hits = 0
    self:UnrestrictBag(player)
end

-- canride follows the owner and his skill. buck: the owner lost the skill (respec), so a ridden mount
-- throws him off gently. A lost leader does not buck: the mount is usually reclaimed in the next frame
-- (e.g. Spider Hat taken off while riding), and a leaving owner is dismounted by player_common OnDespawn.
function SpiderMount:RefreshRideable(buck)
    local inst = self.inst
    local rideable = inst.components.rideable
    local owner = self.owner
    local canride = owner ~= nil
        and owner:IsValid()
        and not IsDead(inst)
        and SKUtil.HasSkill(owner, MountCommon.SKILL)

    rideable.canride = canride

    if buck and not canride and rideable:IsBeingRidden() then
        rideable:Buck(true)
    end

    self:RefreshPerks()
end

-- Perks (M2-M4) -------------------------------------------------------------------------------

function SpiderMount:OwnerHasSkill(skill)
    local owner = self.owner
    return owner ~= nil and owner:IsValid() and SKUtil.HasSkill(owner, skill)
end

local function Regen(inst, self)
    local health = inst.components.health
    if health:IsDead() or health:GetPercent() >= 1 then
        return
    end
    local tuning = TUNING.SPIDERKINGDOM
    local combat = inst.components.combat
    local last = math.max(combat.lastwasattackedtime or 0, combat.laststartattacktime or 0)
    local rider = inst.components.rideable:GetRider()
    if rider ~= nil and rider.components.combat ~= nil then
        local ridercombat = rider.components.combat
        last = math.max(last, ridercombat.lastwasattackedtime or 0, ridercombat.laststartattacktime or 0)
    end
    if GetTime() - last >= tuning.MOUNT_REGEN_DELAY then
        health:DoDelta(health.maxhealth * tuning.MOUNT_REGEN_PERCENT, true, "sk_mount_regen")
    end
end

-- Idempotent; called from RefreshRideable (owner / skill changes) and OnRiderChanged.
function SpiderMount:RefreshPerks()
    local inst = self.inst
    local tuning = TUNING.SPIDERKINGDOM
    local alive = not IsDead(inst)
    local owner = self.owner

    -- M3: the bonus is only for the owner's mounted attacks.
    local combat = inst.components.combat
    if alive and owner ~= nil and inst.components.rideable:GetRider() == owner
        and self:OwnerHasSkill(MountCommon.SKILL_BATTLE) then
        combat.externaldamagemultipliers:SetModifier(inst, tuning.MOUNT_BATTLE_DAMAGE_MULT, BATTLE_KEY)
    else
        combat.externaldamagemultipliers:RemoveModifier(inst, BATTLE_KEY)
    end

    -- M4
    local faithful = alive and self:OwnerHasSkill(MountCommon.SKILL_FAITHFUL)
    local speed = tuning.MOUNT_RUN_SPEED * (faithful and tuning.MOUNT_FAITHFUL_SPEED_MULT or 1)
    if inst.components.locomotor.runspeed ~= speed then
        self:SetRunSpeed(speed)
    end

    if faithful then
        if self.regentask == nil then
            self.regentask = inst:DoPeriodicTask(tuning.MOUNT_REGEN_PERIOD, Regen, nil, self)
        end
    elseif self.regentask ~= nil then
        self.regentask:Cancel()
        self.regentask = nil
    end

    -- The bag opens for its owner with M4, and stays open to him while anything is inside (respec does
    -- not lock his items away). Never while ridden (the stock collector already refuses it then).
    local container = inst.components.container
    container.canbeopened = alive
        and owner ~= nil
        and self.bagtag ~= nil
        and not inst.components.rideable:IsBeingRidden()
        and (faithful or not container:IsEmpty())
    if not container.canbeopened then
        container:Close()
    end
end

-- container.restrictedtag: one tag per owner (userid), shared by all his steeds.
function SpiderMount:RestrictBag(player)
    if player.userid == nil or player.userid == "" then
        return
    end
    self.bagtag = MountCommon.BAG_TAG_PREFIX..player.userid
    player:AddTag(self.bagtag)
    self.inst.components.container.restrictedtag = self.bagtag
end

function SpiderMount:UnrestrictBag(player)
    local container = self.inst.components.container
    container:Close()
    container.canbeopened = false

    local tag = self.bagtag
    self.bagtag = nil
    if tag == nil or not player:IsValid() then
        return
    end
    -- Keep the tag while another steed of his still uses it.
    local leader = player.components.leader
    if leader ~= nil then
        for follower in pairs(leader.followers) do
            if follower ~= self.inst and follower.components.sk_spidermount ~= nil
                and follower.components.sk_spidermount.bagtag == tag then
                return
            end
        end
    end
    player:RemoveTag(tag)
end

-- M3: every MOUNT_BITE_EVERY-th mounted hit of the owner bites everything hostile around the target.
-- Counted once per attack:
--   * only real attacks (from_doattack); the bite's own GetAttacked has none ...
--   * ... except damage redirected to a mounted player's mount: the stock code re-runs it with
--     from_doattack = true (combat.lua GetAttacked_Internal) and redirected_from set on the mount's combat
--     meanwhile. Those second events are skipped, and nothing is counted while a bite runs.
function SpiderMount:OnOwnerHitOther(owner, data)
    local target = data ~= nil and data.target or nil
    if target == nil or not data.from_doattack or self.biting
        or (target.components.combat ~= nil and target.components.combat.redirected_from ~= nil)
        or self.inst.components.rideable:GetRider() ~= owner
        or not self:OwnerHasSkill(MountCommon.SKILL_BATTLE) then
        return
    end
    self.hits = self.hits + 1
    if self.hits < TUNING.SPIDERKINGDOM.MOUNT_BITE_EVERY then
        return
    end
    self.hits = 0
    self:Bite(owner, target, (data.damage or 0) * TUNING.SPIDERKINGDOM.MOUNT_BITE_DAMAGE_MULT)
end

-- Not the owner, his followers, other players (unless PvP) or other players' followers (T1 filter).
local function CanBite(owner, guy, pvp)
    if guy == owner or not guy:IsValid() or guy.components.health:IsDead() then
        return false
    end
    local combat = owner.components.combat
    if not combat:CanTarget(guy) or combat:IsAlly(guy) then
        return false
    end
    if guy:HasTag("player") then
        return pvp
    end
    local follower = guy.components.follower
    local leader = follower ~= nil and follower:GetLeader() or nil
    if leader ~= nil and (leader == owner or (leader:HasTag("player") and not pvp)) then
        return false
    end
    return true
end

function SpiderMount:Bite(owner, target, damage)
    if damage <= 0 or not target:IsValid() then
        return
    end
    local pvp = TheNet:GetPVPEnabled()
    local x, y, z = target.Transform:GetWorldPosition()
    local ents = TheSim:FindEntities(x, y, z, TUNING.SPIDERKINGDOM.MOUNT_BITE_RADIUS, BITE_MUST_TAGS, BITE_CANT_TAGS)
    self.biting = true
    for _, guy in ipairs(ents) do
        if guy ~= target and guy ~= self.inst and CanBite(owner, guy, pvp) then
            guy.components.combat:GetAttacked(owner, damage)
        end
    end
    self.biting = false
    if owner.SoundEmitter ~= nil then
        owner.SoundEmitter:PlaySound(self.inst:SoundPath("Attack"))
    end
end

function SpiderMount:OnLeaderChanged(data)
    local leader = data ~= nil and data.new or nil
    if leader ~= nil and leader:HasTag("player")
        and self.owner_userid ~= nil and leader.userid ~= self.owner_userid then
        -- Recruited by another player (Spider Hat, feeding a stock spider nearby: prefabs/spider.lua
        -- recruits every leaderless "spider" around): the steed stays its saved owner's. Released next
        -- frame, outside the leader's AddFollower call, then it looks for its owner again.
        self:UnlinkOwner()
        self.inst:DoTaskInTime(0, function(inst)
            local follower = inst.components.follower
            if follower ~= nil and follower:GetLeader() == leader then
                follower:SetLeader(nil)
            end
        end)
    elseif leader ~= nil and leader:HasTag("player") then
        self:LinkOwner(leader)
    else
        self:UnlinkOwner()
        if leader == nil then
            self:StartReclaim()
        end
    end
    self:RefreshRideable(false)
end

-- The owner's own MOUNT on this mount: stop fighting first, so the stock action does not fail.
function SpiderMount:OnOwnerPerformAction(owner, data)
    local act = data ~= nil and data.action or nil
    if act ~= nil
        and act.action == ACTIONS.MOUNT
        and act.target == self.inst
        and self:CanBeRiddenBy(owner)
        and self.inst.components.combat:HasTarget() then
        self.inst.components.combat:DropTarget()
    end
end

-- Reclaim -------------------------------------------------------------------------------------

-- Can this player take the mount as its leader? (his own, or an unowned mount; Webber with the skill)
function SpiderMount:CanBeClaimedBy(player)
    return player ~= nil
        and player:IsValid()
        and player:HasTag("spiderwhisperer")
        and not player:HasTag("playerghost")
        and player.components.leader ~= nil
        and not MountCommon.IsLeaving(player)
        and not IsDead(self.inst)
        and (self.owner_userid == nil or self.owner_userid == player.userid)
        and (self.owner_userid ~= nil or SKUtil.HasSkill(player, MountCommon.SKILL))
end

function SpiderMount:TryReclaim()
    local inst = self.inst
    local follower = inst.components.follower
    if IsDead(inst) or follower:GetLeader() ~= nil then
        self:StopReclaim()
        return
    end
    local player = MountCommon.FindOwner(self.owner_userid)
    -- A ridden mount is out of the scene but sits right on its rider.
    if self:CanBeClaimedBy(player)
        and (inst.components.rideable:GetRider() == player
            or (not inst:IsInLimbo() and inst:IsNear(player, TUNING.SPIDERKINGDOM.MOUNT_RECLAIM_RADIUS))) then
        player.components.leader:AddFollower(inst) -- stops this task through OnLeaderChanged
    end
end

-- First try in the next frame (never inside the leader's own follower loop), then every few seconds.
function SpiderMount:StartReclaim()
    if self.reclaimtask == nil and self.owner_userid ~= nil
        and not IsDead(self.inst) and not self.inst._sk_keeper_removed then
        self.reclaimtask = self.inst:DoPeriodicTask(RECLAIM_PERIOD, function() self:TryReclaim() end, FRAMES)
    end
end

function SpiderMount:StopReclaim()
    if self.reclaimtask ~= nil then
        self.reclaimtask:Cancel()
        self.reclaimtask = nil
    end
end

-- Feeding (trader, prefabs/sk_spider_mount.lua) -------------------------------------------------

function SpiderMount:CanTakeFoodFrom(giver)
    if giver == nil or IsDead(self.inst) then
        return false
    end
    local leader = self.inst.components.follower:GetLeader()
    if leader ~= nil then
        return leader == giver
    end
    return self:CanBeClaimedBy(giver)
end

function SpiderMount:OnFedBy(giver)
    local inst = self.inst
    inst.components.health:DoDelta(TUNING.SPIDERKINGDOM.MOUNT_FEED_HEAL, false, "sk_mount_feed")
    if inst.components.follower:GetLeader() == nil and self:CanBeClaimedBy(giver) then
        self:SetOwnerUserId(giver.userid)
        giver.components.leader:AddFollower(inst)
    end
end

-- Riding and death ----------------------------------------------------------------------------

local function Rebuck(inst, self)
    local rideable = inst.components.rideable
    if rideable:IsBeingRidden() then
        rideable:Buck(true)
    elseif self.bucktask ~= nil then
        self.bucktask:Cancel()
        self.bucktask = nil
    end
end

function SpiderMount:OnRiderChanged(data)
    self.hits = 0
    if data ~= nil and data.newrider == nil then
        if self.bucktask ~= nil then
            self.bucktask:Cancel()
            self.bucktask = nil
        end
        local inst = self.inst
        if IsDead(inst) then
            -- Died while ridden: back in the world now, drop the saddlebag here (OnDeath could not).
            inst.components.container:DropEverything()
            if inst.sg ~= nil and not inst.sg:HasStateTag("dead") and inst.sg.currentstate.name ~= "death" then
                inst.sg:GoToState("death")
            end
        end
    end
    self:RefreshPerks()
end

function SpiderMount:OnDeath(data)
    local inst = self.inst
    self:StopReclaim()
    inst.components.rideable.canride = false
    self:RefreshPerks() -- closes the bag, stops regeneration, removes the M3 bonus

    local rideable = inst.components.rideable
    if not rideable:IsBeingRidden() then
        inst.components.container:DropEverything()
    else
        -- The stategraph does not run while the mount is out of the scene: throw the rider off now,
        -- the death state starts after the dismount (OnRiderChanged). Re-buck until it worked, like the
        -- beefalo's buck timer does (Buck is only an event for the rider's stategraph).
        rideable:Buck(true)
        if self.bucktask == nil then
            self.bucktask = inst:DoPeriodicTask(REBUCK_PERIOD, Rebuck, REBUCK_PERIOD, self)
        end
    end

    -- keepdeadleader keeps dead followers on the leader's list: leave it ourselves.
    local follower = inst.components.follower
    local leader = follower:GetLeader()
    if leader ~= nil then
        if leader:HasTag("player") then
            MountCommon.Say(leader, STRINGS.SK_MOUNT.DIED)
        end
        follower:SetLeader(nil) -- sk_spiderkeeper unbonds it (persists = true) ...
    end
    inst.persists = false     -- ... but a dead mount is never saved
end

-- Save ----------------------------------------------------------------------------------------

function SpiderMount:OnSave()
    if self.owner_userid ~= nil then
        return { owner = self.owner_userid }
    end
end

function SpiderMount:OnLoad(data)
    if data ~= nil then
        self:SetOwnerUserId(data.owner)
    end
end

function SpiderMount:OnRemoveFromEntity()
    self:StopReclaim()
    if self.bucktask ~= nil then
        self.bucktask:Cancel()
        self.bucktask = nil
    end
    if self.regentask ~= nil then
        self.regentask:Cancel()
        self.regentask = nil
    end
    self:UnlinkOwner()
end

function SpiderMount:GetDebugString()
    local rideable = self.inst.components.rideable
    return string.format("owner: %s (%s), canride: %s, ridden: %s, hits: %d, regen: %s, bag: %s",
        tostring(self.owner), tostring(self.owner_userid), tostring(rideable.canride), tostring(rideable:IsBeingRidden()),
        self.hits, tostring(self.regentask ~= nil), tostring(self.inst.components.container.canbeopened))
end

return SpiderMount
