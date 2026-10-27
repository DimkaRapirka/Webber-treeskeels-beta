-- T2 Spider Mail across worlds (Phase 5.5): portals and shard messages. Server only.
-- Plain module: require("spiderkingdom/couriers/shard_common"). Handlers: couriers/shard.lua.
--
-- A courier sent to a map point next to an open world portal (cave entrance, sinkhole, stairs: anything
-- with the official worldmigrator) flies there and crosses to the linked shard. Crossing is a mod shard
-- RPC carrying the courier's save record (like the official SyncWorldSettings, which also sends a
-- DataDumper string between shards; shardnetworking.lua Shard_SyncWorldSettings):
--
--   source: courier hidden in phase "transit"; once that state is on disk -> MailParcel(id, portal,
--           record), again every MAIL_SHARD_RESEND seconds while the target shard is connected;
--   target: spawns the record next to the paired portal and remembers the parcel id; once both are on
--           disk -> MailAck(id). A repeated parcel is never spawned again (acknowledged if already durable);
--   source: on MailAck removes its hidden copy; once that removal is on disk -> MailForget(id), and the
--           target drops the id. On MailReject (no paired portal, bad record) it lands here instead; the
--           target saves a refusal before sending it and refuses that id ever after (until MailForget).
--
-- "On disk" = the world save containing the state has finished (DURABLE below). Every message only
-- reports durable state, and an arrived courier stays hidden ("quarantine") until its receipt is on
-- disk, so a lost message, a shard that is down or a crash of either shard only delays the trip.
-- Remaining assumption: shards roll back together. DST keeps their snapshots in step (a secondary that
-- is ahead of the master truncates back to the master's snapshot, components/autosaver.lua); a manual
-- rollback of the cluster restores both sides of a trip to the same save round.
-- Portal pairing as in the official migration: the target portal is the one whose id is the source
-- portal's receivedPortal (components/worldmigrator.lua, playerspawner.lua).

local MailShard = {}

MailShard.NAMESPACE = "SpiderKingdom"

-- Durable state ----------------------------------------------------------------------------------
-- Each world save gets a token: components mark their pending step with the token of the save that is
-- collecting them (OnSave runs synchronously inside SaveGame, mainfunctions.lua), and the token is
-- done when that very save has been written (SaveGame's callback, after SerializeWorldSession and the
-- index files). Overlapping saves cannot confuse it, unlike a snapshot counter. A step whose save never
-- completes is marked again by the next save. Installed by couriers/shard.lua (WrapSaveGame).

MailShard.DURABLE = { done = true } -- mark of anything loaded from disk

local collecting = nil

function MailShard.WrapSaveGame(SaveGame_old)
    return function(isshutdown, cb, ...)
        local token = { done = false }
        collecting = token
        SaveGame_old(isshutdown, function(...)
            token.done = true
            if cb ~= nil then
                return cb(...)
            end
        end, ...)
        collecting = nil
    end
end

-- From OnSave: the mark to keep (an unfinished mark moves to the save collecting now).
function MailShard.MarkSave(mark)
    if (mark == nil or not mark.done) and collecting ~= nil then
        return collecting
    end
    return mark
end

function MailShard.IsDurable(mark)
    return mark ~= nil and mark.done
end

local function GetRPC(name)
    return GetShardModRPC(MailShard.NAMESPACE, name)
end

-- Portals ---------------------------------------------------------------------------------------

-- An open portal to another, connected shard (official migration would work through it right now).
function MailShard.IsPortalOpen(portal)
    local migrator = portal ~= nil and portal:IsValid() and portal.components.worldmigrator or nil
    return migrator ~= nil
        and migrator:IsBound()
        and migrator:IsActive()
        and migrator.linkedWorld ~= TheShard:GetShardId()
        and Shard_IsWorldAvailable(migrator.linkedWorld)
end

function MailShard.FindPortalById(id)
    if id == nil then
        return nil
    end
    for _, portal in ipairs(ShardPortals) do
        if portal:IsValid() and portal.components.worldmigrator ~= nil and portal.components.worldmigrator.id == id then
            return portal
        end
    end
end

-- The nearest open portal within radius of pt.
function MailShard.FindPortalNear(pt, radius)
    local best, bestdsq = nil, radius * radius
    for _, portal in ipairs(ShardPortals) do
        if MailShard.IsPortalOpen(portal) then
            local x, _, z = portal.Transform:GetWorldPosition()
            local dsq = math2d.DistSq(x, z, pt.x, pt.z)
            if dsq <= bestdsq then
                best, bestdsq = portal, dsq
            end
        end
    end
    return best
end

-- An open portal to the given world, preferably the one with this id.
function MailShard.FindPortalTo(world, preferred_id)
    local preferred = MailShard.FindPortalById(preferred_id)
    if MailShard.IsPortalOpen(preferred) and preferred.components.worldmigrator.linkedWorld == world then
        return preferred
    end
    for _, portal in ipairs(ShardPortals) do
        if MailShard.IsPortalOpen(portal) and portal.components.worldmigrator.linkedWorld == world then
            return portal
        end
    end
end

-- Messages --------------------------------------------------------------------------------------

function MailShard.NewParcelId()
    return string.format("%s:%d:%d", tostring(TheShard:GetShardId()), os.time(), math.random(1, 999999999))
end

function MailShard.SendParcel(world, parcel_id, portal_id, record)
    SendModRPCToShard(GetRPC("MailParcel"), world, parcel_id, portal_id, DataDumper(record, nil, true))
end

function MailShard.SendAck(world, parcel_id)
    SendModRPCToShard(GetRPC("MailAck"), world, parcel_id)
end

function MailShard.SendReject(world, parcel_id)
    SendModRPCToShard(GetRPC("MailReject"), world, parcel_id)
end

function MailShard.SendForget(world, parcel_id)
    SendModRPCToShard(GetRPC("MailForget"), world, parcel_id)
end

return MailShard
