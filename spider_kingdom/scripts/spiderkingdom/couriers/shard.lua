-- T2 Spider Mail across worlds (Phase 5.5): shard RPC handlers and the world registry.
-- Protocol and guarantees: couriers/shard_common.lua. Courier side: components/sk_mailspider.lua.
--
-- Handlers run on the receiving shard's server (the official queue calls them with the sender shard id
-- first, networkclientrpc.lua HandleShardModRPC / CallShardRPC). Answers are sent a frame later.

local _G = GLOBAL
local MailShard = require("spiderkingdom/couriers/shard_common")

local COURIER_PREFAB = "sk_courierspider"

local function GetRegistry()
    return _G.TheWorld ~= nil and _G.TheWorld.ismastersim and _G.TheWorld.components.sk_mailregistry or nil
end

local function Reply(fn, world, parcel_id)
    _G.TheWorld:DoTaskInTime(0, function()
        fn(world, parcel_id)
    end)
end

AddShardModRPCHandler(MailShard.NAMESPACE, "MailParcel", function(sender, parcel_id, portal_id, record_str)
    local registry = GetRegistry()
    if registry == nil or type(parcel_id) ~= "string" or type(record_str) ~= "string" then
        return
    end
    local world = tostring(sender)

    if registry:WasRejected(parcel_id) then
        if not registry:IsRejectPending(parcel_id) then
            Reply(MailShard.SendReject, world, parcel_id) -- the first answer was lost
        end
        return -- a refusal is final; it goes out once it is saved here
    end

    if registry:WasReceived(parcel_id) then
        if not registry:IsAckPending(parcel_id) then
            Reply(MailShard.SendAck, world, parcel_id) -- the first answer was lost
        end
        return -- otherwise the answer goes out once the courier is saved here
    end

    local portal = MailShard.FindPortalById(portal_id)
    local ok, record = _G.RunInSandboxSafe(record_str)
    if portal == nil or not ok or type(record) ~= "table" or record.prefab ~= COURIER_PREFAB then
        print("[Spider Kingdom] mail parcel rejected", parcel_id, tostring(portal_id), tostring(ok))
        registry:MarkRejected(parcel_id, world)
        return
    end

    local courier = _G.SpawnSaveRecord(record)
    if courier == nil or courier.components.sk_mailspider == nil then
        if courier ~= nil then
            courier:Remove()
        end
        print("[Spider Kingdom] mail parcel could not be spawned", parcel_id)
        registry:MarkRejected(parcel_id, world)
        return
    end

    registry:MarkReceived(parcel_id, world) -- acknowledged once this is saved (sk_mailregistry)
    courier.components.sk_mailspider:Quarantine(parcel_id, portal) -- hidden until then
end)

AddShardModRPCHandler(MailShard.NAMESPACE, "MailAck", function(sender, parcel_id)
    local registry = GetRegistry()
    if registry ~= nil and type(parcel_id) == "string" then
        registry:OnAck(parcel_id)
    end
end)

AddShardModRPCHandler(MailShard.NAMESPACE, "MailReject", function(sender, parcel_id)
    local registry = GetRegistry()
    if registry ~= nil and type(parcel_id) == "string" then
        registry:OnReject(parcel_id)
    end
end)

AddShardModRPCHandler(MailShard.NAMESPACE, "MailForget", function(sender, parcel_id)
    local registry = GetRegistry()
    if registry ~= nil and type(parcel_id) == "string" then
        registry:OnForget(parcel_id)
    end
end)

AddPrefabPostInit("world", function(inst)
    if inst.ismastersim then
        inst:AddComponent("sk_mailregistry")
    end
end)

-- Per-save tokens for durable state (couriers/shard_common.lua). SaveGame is a global looked up at call
-- time by its callers (shardindex.lua ShardIndex:SaveCurrent, saveindex.lua); the game file is untouched.
-- The global table is strict (strict.lua): an undeclared name must be read and written raw.
if not _G.rawget(_G, "_sk_savegame_wrapped") then
    _G.rawset(_G, "_sk_savegame_wrapped", true)
    _G.SaveGame = MailShard.WrapSaveGame(_G.SaveGame)
end
