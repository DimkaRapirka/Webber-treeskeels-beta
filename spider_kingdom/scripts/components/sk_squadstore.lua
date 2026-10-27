-- sk_squadstore (server only, on TheWorld): T4 Shared Squad. Lent spiders always belong to their owner:
--   * a spider whose loan ended while its owner was not available (offline, on another shard, a ghost, leaving)
--     is kept here as a save record (like petleash / sk_spiderkeeper keep pets) and removed from the world;
--   * every spider still lent out has persists = false and is written into this component's save instead of
--     the world's entity list, under its owner's userid.
-- The records come back as the owner's followers when he is next on this shard and alive (the owner's
-- sk_spiderkeeper bonds them again through the follower hooks). Nothing is ever given to the guarded player.
-- One copy at any time: a record exists only while its spider entity does not.

local Squad = require("spiderkingdom/spiders/squad_common")

local function DoSpawnFx(spider)
    if spider:IsValid() then
        local fx = SpawnPrefab("spawn_fx_small")
        if fx ~= nil then
            fx.Transform:SetPosition(spider.Transform:GetWorldPosition())
        end
    end
end

local function PlaceNear(spider, player)
    local pos = player:GetPosition()
    local offset = FindWalkableOffset(pos, math.random() * TWOPI, 2, 8, true, false)
    if offset ~= nil then
        pos = pos + offset
    end
    if spider.Physics ~= nil then
        spider.Physics:Teleport(pos.x, 0, pos.z)
    else
        spider.Transform:SetPosition(pos.x, 0, pos.z)
    end
end

local SquadStore = Class(function(self, inst)
    self.inst = inst
    self.records = {} -- [owner userid] = { save records }
    self.waiting = setmetatable({}, { __mode = "k" }) -- ghost owners we listen to for a revival

    self._onplayerjoined = function(world, player) self:ScheduleRelease(player) end
    inst:ListenForEvent("ms_playerjoined", self._onplayerjoined)

    self._onrespawned = function(player)
        self:StopWaiting(player)
        self:ScheduleRelease(player)
    end
end)

function SquadStore:HasRecords(userid)
    return userid ~= nil and self.records[userid] ~= nil
end

-- spider: a valid spider entity, already detached from any leader and no longer lent (sk_guardian:Stop).
-- owner: the owner's entity if he is on this shard (e.g. a ghost), else nil.
function SquadStore:Keep(userid, spider, owner)
    local record = spider:GetSaveRecord()
    local records = self.records[userid]
    if records == nil then
        records = {}
        self.records[userid] = records
    end
    table.insert(records, record)

    DoSpawnFx(spider)
    spider._sk_keeper_removed = true -- its state is saved elsewhere (see components/sk_courier.lua)
    spider:Remove()

    if owner ~= nil and owner:IsValid() then
        self:WaitFor(owner)
    end
end

function SquadStore:WaitFor(player)
    if self.waiting[player] == nil then
        self.waiting[player] = true
        self.inst:ListenForEvent("ms_respawnedfromghost", self._onrespawned, player)
    end
end

function SquadStore:StopWaiting(player)
    if self.waiting[player] ~= nil then
        self.waiting[player] = nil
        self.inst:RemoveEventCallback("ms_respawnedfromghost", self._onrespawned, player)
    end
end

-- Delayed: on joining (also after a migration) the player may still be moved to his spawn point.
function SquadStore:ScheduleRelease(player)
    if player == nil or not self:HasRecords(player.userid) then
        return
    end
    self.inst:DoTaskInTime(TUNING.SPIDERKINGDOM.SQUAD_RELEASE_DELAY, function()
        self:Release(player)
    end)
end

function SquadStore:Release(player)
    if not player:IsValid() or not self:HasRecords(player.userid) then
        return
    end
    if not Squad.IsAvailable(player) then
        -- A ghost: wait for the revival. Leaving: the next join on this shard releases them.
        if player:HasTag("playerghost") or (player.components.health ~= nil and player.components.health:IsDead()) then
            self:WaitFor(player)
        end
        return
    end

    local records = self.records[player.userid]
    self.records[player.userid] = nil

    local leader = player.components.leader
    for _, record in ipairs(records) do
        local spider = SpawnSaveRecord(record)
        if spider ~= nil then
            PlaceNear(spider, player)
            if spider.components.follower ~= nil then
                -- The record still names the player it guarded last.
                spider.components.follower:ClearCachedPlayerLeader()
                leader:AddFollower(spider) -- bonds through sk_spiderkeeper (Webber), stance from the commander
            end
            spider:DoTaskInTime(0, DoSpawnFx)
        end
    end
end

function SquadStore:OnSave()
    local byowner = {}
    for userid, records in pairs(self.records) do
        local list = {}
        for _, record in ipairs(records) do
            table.insert(list, record)
        end
        byowner[userid] = list
    end

    -- Spiders still lent out (persists = false) are saved here, under their owner.
    Squad.ForEachGuardian(function(spider, guardian)
        if spider.components.health == nil or not spider.components.health:IsDead() then
            local list = byowner[guardian.owner]
            if list == nil then
                list = {}
                byowner[guardian.owner] = list
            end
            table.insert(list, spider:GetSaveRecord())
        end
    end)

    local owners = {}
    for userid, list in pairs(byowner) do
        if #list > 0 then
            table.insert(owners, { userid = userid, records = list })
        end
    end
    if #owners > 0 then
        return { owners = owners }
    end
end

function SquadStore:OnLoad(data)
    if data == nil or data.owners == nil then
        return
    end
    for _, entry in ipairs(data.owners) do
        if entry.userid ~= nil and entry.records ~= nil and #entry.records > 0 then
            local records = self.records[entry.userid]
            if records == nil then
                records = {}
                self.records[entry.userid] = records
            end
            for _, record in ipairs(entry.records) do
                table.insert(records, record)
            end
        end
    end

    -- Players normally join after the world has loaded; this only covers a reload with players present.
    self.inst:DoTaskInTime(TUNING.SPIDERKINGDOM.SQUAD_RELEASE_DELAY, function()
        for _, player in ipairs(AllPlayers) do
            self:ScheduleRelease(player)
        end
    end)
end

function SquadStore:GetDebugString()
    local owners, spiders = 0, 0
    for _, records in pairs(self.records) do
        owners = owners + 1
        spiders = spiders + #records
    end
    return string.format("stored spiders: %d (owners: %d)", spiders, owners)
end

return SquadStore
