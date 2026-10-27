-- sk_guardian (server only): T4 Shared Squad. One of Webber's spiders lent to another player as a bodyguard.
--
-- While guarding:
--   * the follower leader is the guarded player: stock follow / defend behaviour and stock leashing;
--   * the owner (Webber) is remembered by userid (also networked as spider._sk_guardowner for the action label);
--   * tags "sk_guardian" and "sk_nokeeper": no sk_spiderkeeper bonds it, so it never travels with the guarded
--     player or ends up in his save;
--   * persists = false: the world store (components/sk_squadstore.lua) writes its save record under the owner's
--     userid instead, so after a world reload it comes back to the owner, never to the guarded player;
--   * it cannot be picked up (it would leave the shard in the guarded player's inventory);
--   * T1-style protection: it never fights the owner or the guarded player, and fights other players, companions
--     and players' followers only while they are provoking (a deliberate PvP hit on it or on the guarded player).
--
-- Whenever the guarded player stops being its leader (logout, migration, death, repellent, he hits it, his
-- entity is removed) or someone else takes it over, it goes back to the owner. If the owner is not available
-- (offline, on another shard, a ghost, leaving) it goes into the world store until he is back on this shard.
--
-- The combat / follower / sleep wrappers that call into this component are in spiders/squad.lua.

local Squad = require("spiderkingdom/spiders/squad_common")
local NoBite = require("spiderkingdom/spiders/nobite_common")

local function SetNetOwner(inst, userid)
    if inst._sk_guardowner ~= nil then
        inst._sk_guardowner:set(userid or "")
    end
end

local function IsFriendOfPlayers(target)
    if target:HasTag("player") or target:HasTag("companion") then
        return true
    end
    local follower = target.components.follower
    local targetleader = follower ~= nil and follower:GetLeader() or nil
    return targetleader ~= nil and targetleader:HasTag("player")
end

local UNTRAPPABLE_TAG = "untrappable"         -- traps ignore it (components/trap.lua TRAP_NO_TAGS)

-- Stock ways to replace the spider by a new entity that follows the current leader, or to remove it, are
-- switched off while lent and restored afterwards:
--   * traps (they ignore canbepickedup);
--   * lunar corpse mutation (SGspider corpse -> mutated spider follows the remembered leader);
--   (the moon potion is blocked by the halloweenmoonmutable Mutate wrapper in squad.lua).
local function ApplyLoanFlags(self)
    local inst = self.inst
    self.added_untrappable = not inst:HasTag(UNTRAPPABLE_TAG)
    if self.added_untrappable then
        inst:AddTag(UNTRAPPABLE_TAG)
    end
    if inst.sg ~= nil then
        self.prev_nolunarmutate = inst.sg.mem.nolunarmutate or false
        inst.sg.mem.nolunarmutate = true
    end
end

local function RestoreLoanFlags(self)
    local inst = self.inst
    if self.added_untrappable then
        inst:RemoveTag(UNTRAPPABLE_TAG)
    end
    self.added_untrappable = nil
    if self.prev_nolunarmutate ~= nil and inst.sg ~= nil then
        -- A spider that died while lent keeps it: its corpse copies the flag (componentutil.lua) and
        -- would otherwise come back as a mutant following the guarded player.
        if not (inst.components.health ~= nil and inst.components.health:IsDead()) then
            inst.sg.mem.nolunarmutate = self.prev_nolunarmutate or nil
        end
    end
    self.prev_nolunarmutate = nil
end

local Guardian = Class(function(self, inst)
    self.inst = inst
    self.owner = nil        -- userid of the Webber who lent it
    self.guarded = nil      -- userid of the guarded player
    self.guarded_inst = nil
    self.provokers = nil
    self.transferring = false
    self.setleader_depth = 0 -- follower:SetLeader calls in progress (wrapper in spiders/squad.lua)
    self.leader_dirty = false -- the leader changed while lent; decided once every SetLeader has unwound
    self.return_task = nil
    self.store_task = nil

    self._onleaderchanged = function(inst, data)
        self:OnLeaderChanged(data ~= nil and data.new or nil)
    end
    inst:ListenForEvent("leaderchanged", self._onleaderchanged)

    -- The stock spider becomes pickable when it starts leashing to a player or falls asleep
    -- (prefabs/spider.lua OnStartLeashing / OnGoToSleep). These listeners run after the stock ones.
    self._keepunpickable = function() self:KeepUnpickable() end
    inst:ListenForEvent("startleashing", self._keepunpickable)
    inst:ListenForEvent("gotosleep", self._keepunpickable)
    inst:ListenForEvent("onwakeup", self._keepunpickable)

    inst:ListenForEvent("attacked", function(inst, data)
        self:RecordDeliberateHit(inst, data ~= nil and data.attacker or nil)
    end)
    self._onguardedattacked = function(player, data)
        self:RecordDeliberateHit(player, data ~= nil and data.attacker or nil)
    end

    inst:ListenForEvent("onremove", function() Squad.Unregister(inst) end)
end)

function Guardian:IsGuarding()
    return self.owner ~= nil
end

function Guardian:GetGuardedPlayer()
    local player = self.guarded_inst
    return player ~= nil and player:IsValid() and player or nil
end

function Guardian:KeepUnpickable()
    if self:IsGuarding() and self.inst.components.inventoryitem ~= nil then
        self.inst.components.inventoryitem.canbepickedup = false
    end
end

-- owner, guarded: player entities. The spider must be following the owner.
function Guardian:Start(owner, guarded)
    local inst = self.inst
    local follower = inst.components.follower
    local leader = guarded.components.leader
    if self:IsGuarding() or follower == nil or leader == nil
        or owner.userid == nil or owner.userid == "" or guarded.userid == nil or guarded.userid == "" then
        return false
    end

    self.owner = owner.userid
    self.guarded = guarded.userid
    self.guarded_inst = guarded
    self.provokers = nil

    inst:AddTag(Squad.GUARDIAN_TAG)
    self.added_nokeeper = not inst:HasTag(Squad.NOKEEPER_TAG)
    if self.added_nokeeper then
        inst:AddTag(Squad.NOKEEPER_TAG)
    end
    SetNetOwner(inst, self.owner)
    ApplyLoanFlags(self)
    Squad.Register(inst)

    -- Leaving the owner: his sk_spiderkeeper unbonds it (persists = true), his commander clears its stance.
    self.transferring = true
    leader:AddFollower(inst)
    self.transferring = false

    if follower:GetLeader() ~= guarded then
        -- Not expected. Undo and hand it back if it ended up without a leader.
        self:Stop()
        if follower:GetLeader() == nil and Squad.IsAvailable(owner) then
            owner.components.leader:AddFollower(inst)
        end
        return false
    end

    inst.persists = false
    self:KeepUnpickable()
    inst:ListenForEvent("attacked", self._onguardedattacked, guarded)
    return true
end

-- Clears the loan. The caller decides where the spider goes.
function Guardian:Stop()
    if not self:IsGuarding() then
        return
    end
    local inst = self.inst

    if self.guarded_inst ~= nil then
        inst:RemoveEventCallback("attacked", self._onguardedattacked, self.guarded_inst)
    end
    if self.return_task ~= nil then
        self.return_task:Cancel()
        self.return_task = nil
    end
    if self.store_task ~= nil then
        self.store_task:Cancel()
        self.store_task = nil
    end

    self.owner = nil
    self.guarded = nil
    self.guarded_inst = nil
    self.provokers = nil

    inst:RemoveTag(Squad.GUARDIAN_TAG)
    if self.added_nokeeper then
        inst:RemoveTag(Squad.NOKEEPER_TAG)
    end
    self.added_nokeeper = nil
    RestoreLoanFlags(self)
    SetNetOwner(inst, "")
    Squad.Unregister(inst)
    self.leader_dirty = false

    if inst:IsValid() then
        inst.persists = true
        if inst.components.inventoryitem ~= nil then
            -- Same rule as the courier and the stock spider: pickable while it has a leader.
            local follower = inst.components.follower
            inst.components.inventoryitem.canbepickedup = follower ~= nil and follower:GetLeader() ~= nil
        end
    end
end

-- Back to the owner if he is here, otherwise into the world store (next frame: not inside event dispatch).
function Guardian:ReturnToOwner()
    if not self:IsGuarding() then
        return
    end
    local inst = self.inst

    if inst.components.health ~= nil and inst.components.health:IsDead() then
        self:Stop()
        return
    end

    local owner = Squad.FindPlayer(self.owner)
    if Squad.IsAvailable(owner) then
        self:Stop() -- removes sk_nokeeper first, so the owner's sk_spiderkeeper bonds it again
        owner.components.leader:AddFollower(inst)
        if inst.components.follower:GetLeader() == owner then
            return
        end
        -- Not expected: the owner's leader refused it. It is an ordinary world spider now.
        return
    end

    -- Stays a protected guardian until the store takes it (squad.lua also blocks the stock "go home on sleep").
    if self.store_task == nil then
        self.store_task = inst:DoTaskInTime(0, function()
            self.store_task = nil
            self:StoreNow()
        end)
    end
end

function Guardian:StoreNow()
    local inst = self.inst
    if not inst:IsValid() or not self:IsGuarding() then
        return
    end
    if inst.components.health ~= nil and inst.components.health:IsDead() then
        self:Stop()
        return
    end

    local userid = self.owner
    local owner = Squad.FindPlayer(userid)
    if Squad.IsAvailable(owner) then
        -- He came back (or was revived) in the meantime.
        self:ReturnToOwner()
        return
    end

    local store = TheWorld.components.sk_squadstore
    if store == nil then
        -- No store (should not happen): leave it as an ordinary world spider rather than lose it.
        self:Stop()
        return
    end

    -- Leave whoever it follows now (e.g. a player who fed it), then pack it.
    self.transferring = true
    inst.components.follower:SetLeader(nil)
    self.transferring = false
    self:Stop()
    store:Keep(userid, inst, owner)
end

-- "leaderchanged" on the spider. Only noted here: stock Follower:SetLeader nests (SetLeader(x) -> old leader's
-- RemoveFollower -> SetLeader(nil), and SetLeader(nil) from the follower itself nests the same way) and the outer
-- call still writes self.leader after the inner event. Acting inside the event would be overwritten, so the
-- decision is made in OnLeaderSettled, after the outermost SetLeader has returned.
function Guardian:OnLeaderChanged(new_leader)
    if not self:IsGuarding() or self.transferring then
        return
    end
    self.leader_dirty = true
    if self.setleader_depth <= 0 then
        -- Not from inside a SetLeader (not expected): decide now.
        self:OnLeaderSettled()
    end
end

-- Called by the SetLeader wrapper (spiders/squad.lua) when the outermost call returns.
function Guardian:OnLeaderSettled()
    if not self.leader_dirty then
        return
    end
    self.leader_dirty = false
    if not self:IsGuarding() or self.transferring then
        return
    end

    local inst = self.inst
    local follower = inst.components.follower
    local leader = follower ~= nil and follower:GetLeader() or nil

    if leader == nil then
        -- Lost the guarded player: logout / migration (player_common OnDespawn caches the player leader first),
        -- death, repellent, hit by him, removed. Never re-follow him from that cache.
        if follower ~= nil then
            follower:ClearCachedPlayerLeader()
        end
        self:ReturnToOwner()

    elseif leader == self.guarded_inst then
        -- Still (or again) guarding the same player.

    elseif leader.userid ~= nil and leader.userid == self.owner then
        -- The owner took it back himself (e.g. fed it): an ordinary follower again. Stopping removes sk_nokeeper
        -- before his leader's onfolloweradded runs; bond here as well in case that hook was replaced.
        self:Stop()
        local keeper = leader.components.sk_spiderkeeper
        if keeper ~= nil then
            keeper:Bond(inst)
        end

    elseif self.return_task == nil then
        -- Taken over by someone else (e.g. another Webber fed it). Wait until that leader's AddFollower has
        -- finished (its callbacks still run after SetLeader), then go back.
        self.return_task = inst:DoTaskInTime(0, function()
            self.return_task = nil
            if self:IsGuarding() and inst.components.follower:GetLeader() ~= self.guarded_inst then
                self:ReturnToOwner()
            end
        end)
    end
end

-- Server spider OnEntitySleep: the stock spider walks into its den when it falls asleep by day without a
-- leader (prefabs/spider.lua DoReturn). A guardian waiting for the store must not.
function Guardian:BlocksGoHome()
    local follower = self.inst.components.follower
    return self:IsGuarding() and (follower == nil or follower:GetLeader() == nil)
end

-- Combat protection ----------------------------------------------------------------------------

local function IsProvoking(self, target)
    local expires = self.provokers ~= nil and self.provokers[target] or nil
    return expires ~= nil and expires > GetTime()
end

local function MarkProvoker(self, attacker)
    local now = GetTime()
    if self.provokers == nil then
        self.provokers = setmetatable({}, { __mode = "k" })
    else
        for ent, expires in pairs(self.provokers) do
            if expires <= now then
                self.provokers[ent] = nil
            end
        end
    end
    self.provokers[attacker] = now + TUNING.SPIDERKINGDOM.NOBITE_PROVOKE_TIME
end

-- Never these two, whatever happens.
function Guardian:IsSacred(target)
    return target == self.guarded_inst
        or (target.userid ~= nil and (target.userid == self.owner or target.userid == self.guarded))
end

-- True if this guardian must not fight this target now.
function Guardian:IsProtected(target)
    if not self:IsGuarding() or target == nil or not target:IsValid() then
        return false
    end
    if self:IsSacred(target) then
        return true
    end
    return IsFriendOfPlayers(target) and not IsProvoking(self, target)
end

-- combat:SetTarget wrapper: a deliberate PvP attack on the spider or on the guarded player provokes.
function Guardian:ShouldIgnoreTarget(target)
    if not self:IsProtected(target) then
        return false
    end
    if self:IsSacred(target) then
        return true
    end
    local guarded = self:GetGuardedPlayer()
    if NoBite.IsDeliberatePvPAttack(target, self.inst)
        or (guarded ~= nil and NoBite.IsDeliberatePvPAttack(target, guarded)) then
        MarkProvoker(self, target)
        return false
    end
    return true
end

-- "attacked" on the spider or on the guarded player: every deliberate PvP hit (re)starts provocation.
function Guardian:RecordDeliberateHit(victim, attacker)
    if self:IsGuarding() and attacker ~= nil and attacker:IsValid() and not self:IsSacred(attacker)
        and NoBite.IsDeliberatePvPAttack(attacker, victim) then
        MarkProvoker(self, attacker)
    end
end

-- Saving: never through the entity (persists = false while guarding). components/sk_squadstore.lua saves
-- lent spiders under their owner, so this component has nothing to write into a save record.
function Guardian:OnSave()
    return nil
end

function Guardian:OnRemoveFromEntity()
    self:Stop()
end

function Guardian:GetDebugString()
    if not self:IsGuarding() then
        return "not lent"
    end
    return string.format("owner: %s, guarding: %s (%s), store pending: %s",
        tostring(self.owner), tostring(self.guarded), tostring(self:GetGuardedPlayer()), tostring(self.store_task ~= nil))
end

return Guardian
