-- sk_mailregistry (server only, on TheWorld): T2 Spider Mail across worlds (couriers/shard_common.lua).
--
-- Every irreversible step waits until the world save that contains the state before it is on disk
-- ("durable", per-save tokens: couriers/shard_common.lua MarkSave / IsDurable).
--
--   received  - parcels this shard has spawned (saved). A parcel sent again is never spawned twice; its id
--               is dropped only when the sender says its own copy is gone for good (MailForget).
--   acks      - received parcels not acknowledged yet: the acknowledgement goes out once the spawned
--               courier and its receipt are durable here (a crash before that loses both, and the
--               sender, which still has its copy, sends again). Until then the courier stays hidden
--               (sk_mailspider "quarantine", IsReceiptDurable), so nobody can take its cargo.
--   rejected  - parcels this shard refused (saved). A refusal is final: the same id is refused again
--               even if its portal comes back, and the refusal goes out only once it is durable
--               (otherwise a late refusal could release the sender's copy after a retry was accepted).
--               Dropped like a receipt, on MailForget.
--   forgets   - parcels this shard has handed over and removed, or landed here after a refusal: once that removal is durable, the
--               receiver may forget the id (a crash before that brings the sender's copy back in
--               "transit", it sends again and is only acknowledged). Sent once and not forced by a
--               save: a lost MailForget only leaves an id in the receiver's list.
--   outgoing  - couriers of this shard waiting for an answer, by parcel id (not saved: a courier in
--               "transit" registers itself again when it loads).
--
-- Waiting for the daily autosave would hold a courier up to a day, so a save is requested
-- (TheWorld "ms_save", as c_save does; a secondary shard forwards it to the master) when
-- TUNING.SPIDERKINGDOM.MAIL_SHARD_FORCE_SAVE is set.

local MailShard = require("spiderkingdom/couriers/shard_common")

local TICK_PERIOD = 2
local IsDurable = MailShard.IsDurable
local DURABLE = MailShard.DURABLE

local MailRegistry = Class(function(self, inst)
    self.inst = inst
    self.received = {}  -- id -> true
    self.acks = {}      -- id -> { world, mark }
    self.rejected = {}  -- id -> true
    self.rejects = {}   -- id -> { world, mark }
    self.forgets = {}   -- id -> { world, mark }
    self.outgoing = {}  -- id -> courier
    self.task = nil
    self.savetask = nil
end)

local function Tick(inst, self)
    local busy = false
    for id, ack in pairs(self.acks) do
        if IsDurable(ack.mark) then
            self.acks[id] = nil
            MailShard.SendAck(ack.world, id)
        else
            busy = true
        end
    end
    for id, reject in pairs(self.rejects) do
        if IsDurable(reject.mark) then
            self.rejects[id] = nil
            MailShard.SendReject(reject.world, id)
        else
            busy = true
        end
    end
    for id, forget in pairs(self.forgets) do
        if IsDurable(forget.mark) then
            self.forgets[id] = nil
            MailShard.SendForget(forget.world, id)
        else
            busy = true
        end
    end
    if not busy and self.task ~= nil then
        self.task:Cancel()
        self.task = nil
    end
end

local function StartTask(self)
    if self.task == nil then
        self.task = self.inst:DoPeriodicTask(TICK_PERIOD, Tick, TICK_PERIOD, self)
    end
end

-- Coalesces requests from several couriers into one save a few seconds later.
function MailRegistry:RequestSave()
    if not TUNING.SPIDERKINGDOM.MAIL_SHARD_FORCE_SAVE or self.savetask ~= nil then
        return
    end
    self.savetask = self.inst:DoTaskInTime(TUNING.SPIDERKINGDOM.MAIL_SHARD_SAVE_DELAY, function(inst)
        self.savetask = nil
        inst:PushEvent("ms_save")
    end)
end

-- Receiving ------------------------------------------------------------------------------------

function MailRegistry:WasReceived(id)
    return self.received[id] == true
end

-- Received but not durable yet: the acknowledgement is still to come, a repeated parcel needs no answer.
function MailRegistry:IsAckPending(id)
    return self.acks[id] ~= nil
end

-- The receipt of this parcel is on disk (or long settled): its courier may come out of quarantine.
function MailRegistry:IsReceiptDurable(id)
    local ack = self.acks[id]
    return ack == nil or IsDurable(ack.mark)
end

function MailRegistry:MarkReceived(id, world)
    self.received[id] = true
    self.acks[id] = { world = world, mark = nil }
    StartTask(self)
    self:RequestSave()
end

function MailRegistry:WasRejected(id)
    return self.rejected[id] == true
end

function MailRegistry:IsRejectPending(id)
    return self.rejects[id] ~= nil
end

function MailRegistry:MarkRejected(id, world)
    self.rejected[id] = true
    self.rejects[id] = { world = world, mark = nil }
    StartTask(self)
    self:RequestSave()
end

function MailRegistry:OnForget(id)
    if self.acks[id] == nil then
        self.received[id] = nil
    end
    if self.rejects[id] == nil then
        self.rejected[id] = nil
    end
end

-- Sending --------------------------------------------------------------------------------------

function MailRegistry:Register(id, courier)
    self.outgoing[id] = courier
end

function MailRegistry:Unregister(id)
    self.outgoing[id] = nil
end

-- The courier of this parcel was removed after the acknowledgement.
function MailRegistry:AddForget(id, world)
    self.forgets[id] = { world = world, mark = nil }
    StartTask(self)
end

local function GetCourier(self, id)
    local courier = self.outgoing[id]
    if courier ~= nil and courier:IsValid() and courier.components.sk_mailspider ~= nil then
        return courier.components.sk_mailspider
    end
    self.outgoing[id] = nil
end

function MailRegistry:OnAck(id)
    local courier = GetCourier(self, id)
    if courier ~= nil then
        courier:OnShipped(id)
    end
end

function MailRegistry:OnReject(id)
    local courier = GetCourier(self, id)
    if courier ~= nil then
        courier:OnShipRejected(id)
    end
end

-- Save -----------------------------------------------------------------------------------------

local function SaveList(list)
    local out = {}
    for id, entry in pairs(list) do
        entry.mark = MailShard.MarkSave(entry.mark) -- this save holds it
        table.insert(out, { id = id, world = entry.world })
    end
    return #out > 0 and out or nil
end

function MailRegistry:OnSave()
    local received, rejected = {}, {}
    for id in pairs(self.received) do
        table.insert(received, id)
    end
    for id in pairs(self.rejected) do
        table.insert(rejected, id)
    end
    local data =
    {
        received = #received > 0 and received or nil,
        rejected = #rejected > 0 and rejected or nil,
        acks = SaveList(self.acks),
        rejects = SaveList(self.rejects),
        forgets = SaveList(self.forgets),
    }
    if next(data) ~= nil then
        return data
    end
end

function MailRegistry:OnLoad(data)
    if data == nil then
        return
    end
    for _, id in ipairs(data.received or {}) do
        self.received[id] = true
    end
    for _, entry in ipairs(data.acks or {}) do
        self.received[entry.id] = true
        self.acks[entry.id] = { world = entry.world, mark = DURABLE }
    end
    for _, id in ipairs(data.rejected or {}) do
        self.rejected[id] = true
    end
    for _, entry in ipairs(data.rejects or {}) do
        self.rejected[entry.id] = true
        self.rejects[entry.id] = { world = entry.world, mark = DURABLE }
    end
    for _, entry in ipairs(data.forgets or {}) do
        self.forgets[entry.id] = { world = entry.world, mark = DURABLE }
    end
    if next(self.acks) ~= nil or next(self.rejects) ~= nil or next(self.forgets) ~= nil then
        StartTask(self)
    end
end

function MailRegistry:GetDebugString()
    local function count(t)
        local n = 0
        for _ in pairs(t) do
            n = n + 1
        end
        return n
    end
    return string.format("received: %d, acks: %d, rejected: %d, rejects: %d, forgets: %d, outgoing: %d",
        count(self.received), count(self.acks), count(self.rejected), count(self.rejects), count(self.forgets), count(self.outgoing))
end

return MailRegistry
