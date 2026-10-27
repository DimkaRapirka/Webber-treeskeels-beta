-- sk_spiderkeeper (server only): carries Webber's befriended spiders through shard migration
-- (surface <-> caves) and reconnects.
--
-- Same approach as the official components/petleash.lua and Walter's Woby (prefabs/walter.lua):
--   * bonded spiders have persists = false, so the world never saves them;
--   * their save records live in the player's save (this component's OnSave);
--   * OnLoad respawns them and pushes them into inst.migrationpets, so playerspawner
--     teleports them to the arrival portal after a migration;
--   * when the player entity is removed (after SerializeUserSession), the spiders are removed too.
--
-- Spiders held in an inventory are NOT bonded: inventory:OnSave skips items with persists = false,
-- and held items already travel with the player.
--
-- R4 Royal Expedition: the Spider Queen out with Webber is a second, separate kind ("queen", at most one).
-- She is never bonded through the follower hooks (CanBond excludes "spiderqueen"); royalty/expeditions.lua
-- bonds her explicitly with BondQueen. Same rules as the spiders (persists = false, record in the player's
-- save, removed with the player, pushed into migrationpets on load), plus her expedition data. Restoring,
-- reroll and passive mode are handed to royalty/expeditions.lua. The spider code paths are unchanged.

local Expeditions = require("spiderkingdom/royalty/expeditions")

local function IsHeld(spider)
    return spider.components.inventoryitem ~= nil and spider.components.inventoryitem:IsHeld()
end

local function DoSpawnFx(spider)
    if spider:IsValid() then
        local fx = SpawnPrefab("spawn_fx_small")
        if fx ~= nil then
            fx.Transform:SetPosition(spider.Transform:GetWorldPosition())
        end
    end
end

local SpiderKeeper = Class(function(self, inst)
    self.inst = inst
    self.spiders = {} -- [spider] = "bonded" | "held"
    self.queen = nil  -- R4: the Spider Queen out with this player (bonded, not in self.spiders)
    self.despawning = false
    self.released = false

    self._onspiderremoved = function(spider) self:Unbond(spider) end
    self._onqueenremoved = function(queen) self:UnbondQueen(queen) end
    self._onspiderputininventory = function(spider) self:SetHeld(spider, true) end
    self._onspiderdropped = function(spider) self:SetHeld(spider, false) end

    -- player_common OnDespawn pushes this right before leader:RemoveAllFollowers().
    -- From here on, keep the spiders bonded so OnSave (SerializeUserSession) still records them.
    self._onplayerdespawn = function() self.despawning = true end
    inst:ListenForEvent("player_despawn", self._onplayerdespawn)

    -- Celestial portal / seamless character swap: the old player entity goes away for good.
    self._onplayerreroll = function() self:ReleaseAll() end
    inst:ListenForEvent("ms_playerreroll", self._onplayerreroll)
end)

-- Passive mode (a conflicting spider-transfer mod is enabled): OnLoad still restores records saved
-- earlier, but the spiders stay normal persistent followers and no new spiders are bonded.
function SpiderKeeper:SetPassive(passive)
    self.passive = passive or nil
end

function SpiderKeeper:CanBond(spider)
    return not self.released
        and not self.passive
        and spider:IsValid()
        and spider:HasTag("spider")
        and not spider:HasTag("spiderqueen")
        and not spider:HasTag("sk_nokeeper")
        and not spider:HasTag("sk_away") -- a T2 courier away on a delivery persists in the world
        and spider.components.follower ~= nil
        and spider.components.health ~= nil
        and not spider.components.health:IsDead()
end

function SpiderKeeper:IsBonded(spider)
    return self.spiders[spider] ~= nil
end

function SpiderKeeper:Bond(spider)
    if self.spiders[spider] ~= nil or not self:CanBond(spider) then
        return false
    end

    self.inst:ListenForEvent("onremove", self._onspiderremoved, spider)
    self.inst:ListenForEvent("onputininventory", self._onspiderputininventory, spider)
    self.inst:ListenForEvent("ondropped", self._onspiderdropped, spider)

    if IsHeld(spider) then
        self.spiders[spider] = "held"
        spider.persists = true
    else
        self.spiders[spider] = "bonded"
        spider.persists = false
    end
    return true
end

function SpiderKeeper:Unbond(spider)
    if self.spiders[spider] == nil then
        return
    end

    self.spiders[spider] = nil
    self.inst:RemoveEventCallback("onremove", self._onspiderremoved, spider)
    self.inst:RemoveEventCallback("onputininventory", self._onspiderputininventory, spider)
    self.inst:RemoveEventCallback("ondropped", self._onspiderdropped, spider)

    if spider:IsValid() then
        spider.persists = true
    end
end

function SpiderKeeper:SetHeld(spider, held)
    if self.spiders[spider] == nil then
        return
    end
    if held then
        self.spiders[spider] = "held"
        spider.persists = true
    elseif spider.components.follower ~= nil and spider.components.follower:GetLeader() == self.inst then
        self.spiders[spider] = "bonded"
        spider.persists = false
    else
        self:Unbond(spider)
    end
end

-- Hooked into the player's leader through inst.additional_OnFollowerAdded / _Removed (player_common.lua).
function SpiderKeeper:OnFollowerAdded(follower)
    self:Bond(follower)
end

function SpiderKeeper:OnFollowerRemoved(follower)
    if not self.despawning then
        self:Unbond(follower)
    end
end

function SpiderKeeper:ReleaseAll()
    self.released = true
    local toremove = {}
    for spider in pairs(self.spiders) do
        table.insert(toremove, spider)
    end
    for _, spider in ipairs(toremove) do
        self:Unbond(spider)
    end

    -- R4: the queen goes home now if she can, otherwise she stays in the world as a wild queen.
    local queen = self.queen
    if queen ~= nil and queen:IsValid() then
        Expeditions.OnKeeperReleased(queen)
    end
    self:UnbondQueen(queen)
end

-- R4 Royal Expedition: the queen kind ------------------------------------------------------------

function SpiderKeeper:CanBondQueen()
    return not self.released and not self.passive
end

function SpiderKeeper:GetQueen()
    return self.queen ~= nil and self.queen:IsValid() and self.queen or nil
end

-- Called by royalty/expeditions.lua when the expedition starts (also after a restore).
function SpiderKeeper:BondQueen(queen)
    if not self:CanBondQueen() or queen == nil or not queen:IsValid() then
        return false
    end
    if self.queen == queen then
        return true
    end
    if self.queen ~= nil then
        self:UnbondQueen(self.queen)
    end
    self.queen = queen
    queen.persists = false
    self.inst:ListenForEvent("onremove", self._onqueenremoved, queen)
    return true
end

-- Ends the bond: she is saved by the world again (wild), or is about to be removed (throne, death).
function SpiderKeeper:UnbondQueen(queen)
    if queen == nil or self.queen ~= queen then
        return
    end
    self.queen = nil
    self.inst:RemoveEventCallback("onremove", self._onqueenremoved, queen)
    if queen:IsValid() then
        queen.persists = true
    end
end

-- The keeper does not tell a despawn from a real loss of the leader; royalty/expeditions.lua asks.
function SpiderKeeper:IsDespawning()
    return self.despawning
end

function SpiderKeeper:CountBonded()
    local count = 0
    for spider, state in pairs(self.spiders) do
        if state == "bonded" then
            count = count + 1
        end
    end
    return count
end

function SpiderKeeper:OnSave()
    if self.released then
        return
    end

    local records = {}
    for spider, state in pairs(self.spiders) do
        if state == "bonded" and spider:IsValid() and not spider.components.health:IsDead() then
            spider.temp_save_platform_pos = true
            local record = spider:GetSaveRecord()
            spider.temp_save_platform_pos = nil
            table.insert(records, record)
        end
    end

    -- R4: the queen out with us. A dead one is not saved (the corpse belongs to the world).
    local queenrecord = nil
    local queen = self:GetQueen()
    if queen ~= nil and not (queen.components.health ~= nil and queen.components.health:IsDead()) then
        queen.temp_save_platform_pos = true
        queenrecord = { record = queen:GetSaveRecord(), expedition = Expeditions.GetSaveData(queen) }
        queen.temp_save_platform_pos = nil
    end

    if #records > 0 or queenrecord ~= nil then
        return { spiders = #records > 0 and records or nil, queen = queenrecord }
    end
end

-- R4: respawns the queen out with us; royalty/expeditions.lua resumes the expedition (or, in passive
-- mode, sends her home / lets her go wild).
function SpiderKeeper:LoadQueen(data)
    local record = data.record
    if type(record) ~= "table" or record.prefab == nil then
        return
    end
    local is_snapshot = self.inst.is_snapshot_user_session

    record.is_snapshot_save_record = is_snapshot
    local queen = SpawnSaveRecord(record)
    record.is_snapshot_save_record = nil

    if queen == nil then
        -- Never lose her (same rule as the throne): a fresh queen next to us, her saved state is lost.
        queen = SpawnPrefab(record.prefab)
        if queen == nil then
            print("[SpiderKingdom] sk_spiderkeeper: failed to restore the Spider Queen.")
            return
        end
        local x, y, z = self.inst.Transform:GetWorldPosition()
        queen.Transform:SetPosition(x, 0, z)
    end

    local resumed = Expeditions.Restore(queen, self.inst, data.expedition)

    -- Still in the world (with us, or wild when the expedition could not resume and she could not go
    -- home): after a migration playerspawner moves her to the arrival portal like the spiders.
    if queen:IsValid() then
        if self.inst.migrationpets ~= nil then
            table.insert(self.inst.migrationpets, queen)
        end
        if resumed and not is_snapshot then
            queen:DoTaskInTime(0, DoSpawnFx)
        end
    end
end

function SpiderKeeper:OnLoad(data)
    if data == nil then
        return
    end
    if type(data.queen) == "table" then
        self:LoadQueen(data.queen)
    end
    if data.spiders == nil then
        return
    end

    local leader = self.inst.components.leader
    local is_snapshot = self.inst.is_snapshot_user_session

    -- Lets follower callbacks (e.g. sk_spidercommander) tell a restore from a new recruit.
    self.inst._sk_restoring_followers = true
    for _, record in ipairs(data.spiders) do
        record.is_snapshot_save_record = is_snapshot
        local spider = SpawnSaveRecord(record)
        record.is_snapshot_save_record = nil

        if spider ~= nil then
            if leader ~= nil then
                leader:AddFollower(spider) -- bonds through additional_OnFollowerAdded
            end
            self:Bond(spider) -- in case the hook was replaced by another mod; no-op in passive mode

            -- The record carries the old player-leader cache; the spider is already following us again.
            spider.components.follower:ClearCachedPlayerLeader()

            if self.passive then
                spider.persists = true
            end

            if self.inst.migrationpets ~= nil then
                table.insert(self.inst.migrationpets, spider)
            end

            if not is_snapshot then
                -- Delayed in case playerspawner relocates the spider to the migration portal.
                spider:DoTaskInTime(0, DoSpawnFx)
            end
        end
    end
    self.inst._sk_restoring_followers = nil
end

-- The player entity is removed after its session was serialized (logout, migration)
-- or after a snapshot restore. Remove the spiders with it, like petleash does with pets.
function SpiderKeeper:OnRemoveEntity()
    if self.released then
        return
    end

    local toremove = {}
    for spider, state in pairs(self.spiders) do
        if state == "bonded" then
            table.insert(toremove, spider)
        end
    end
    for _, spider in ipairs(toremove) do
        self:Unbond(spider)
        if spider:IsValid() then
            -- Its state (e.g. a courier's parcel) is already in the player's save.
            spider._sk_keeper_removed = true
            spider:Remove()
        end
    end

    -- R4: the queen too; she is in the player's save and her throne keeps its "away" mark.
    local queen = self.queen
    if queen ~= nil then
        self:UnbondQueen(queen)
        if queen:IsValid() then
            queen._sk_keeper_removed = true
            queen:Remove()
        end
    end
end

function SpiderKeeper:GetDebugString()
    local held = 0
    for spider, state in pairs(self.spiders) do
        if state == "held" then
            held = held + 1
        end
    end
    return string.format("bonded: %d, held: %d, queen: %s, despawning: %s, released: %s", self:CountBonded(), held,
        tostring(self:GetQueen()), tostring(self.despawning), tostring(self.released))
end

return SpiderKeeper
