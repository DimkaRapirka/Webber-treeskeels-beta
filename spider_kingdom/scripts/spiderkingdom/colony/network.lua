-- K4 Web Logistics / K6 Colony Heart: shared rules. Plain module: require("spiderkingdom/colony/network").
--   * which dens a hauler serves (server). A hauler lives in a storage den (K2 role "storage") and
--     serves its owner's production dens (lumber / farm) and storage dens within LOGISTICS_RADIUS of
--     that den. If the den is within HEART_RADIUS of its owner's linked Colony Heart, the hauler also
--     serves every den of that owner within HEART_RADIUS of the heart (the network);
--   * where a stack goes: Woby's courier rule (prefabs/wobycommon.lua WobyCourier_FindValidContainerForItem);
--   * per-shard heart registry owner userid -> hearts (server), "one heart per player" check, network
--     pause switch and the inspect summary;
--   * the client collector branch for twigs used on a heart, called from networking/item_actions.lua.
-- Nothing here is saved: the network is computed on demand from den roles, owners and positions, so it
-- needs no rebuild after a load and falls back to the local radius as soon as the heart is gone.
-- The heart itself is components/sk_colonyheart.lua + prefabs/sk_colony_heart.lua; the action, the
-- recipe and tuning defaults are in colony/logistics.lua; haulers are components/sk_worker.lua.

local Ownership = require("spiderkingdom/colony/ownership")

local Network = {}

Network.LOGISTICS_SKILL = "webber_sk_colony_logistics"
Network.HEART_SKILL = "webber_sk_colony_heart"
Network.HEART_PREFAB = "sk_colony_heart"
Network.TOGGLE_ITEM = "twigs"

Network.HEART_TAG = "sk_colonyheart"   -- the heart structure (client: action collection)
Network.PAUSED_TAG = "sk_heartpaused"  -- heart whose network's workers are resting (client: action name)
Network.LINK_TAG = "sk_heartlink"      -- heart whose owner is online with K6 (colony/ownership.lua)
Network.KEEPER_TAG = "sk_heartkeeper"  -- player with K6 (client hint only; the server re-checks)

local STORAGE_ROLE = "storage"
local SOURCE_ROLES = { lumber = true, farm = true }

local DEN_MUST = { "spiderden" }
local DEN_CANT = { "burnt", "INLIMBO" }
local SOURCE_ONEOF = { "sk_denrole_lumber", "sk_denrole_farm" }
local STORAGE_ONEOF = { "sk_denrole_storage" }

-- Dens -------------------------------------------------------------------------------------------

function Network.GetDenOwner(den)
    local denrole = den.components.sk_denrole
    return denrole ~= nil and denrole.owner_userid or nil
end

local function GetDenRole(den)
    local denrole = den.components.sk_denrole
    return denrole ~= nil and denrole:GetRole() or nil
end

-- A den whose container can be used right now (colony/denroles.lua refuses inserts into dead dens).
local function IsLiveDen(den)
    return den ~= nil and den:IsValid()
        and den.prefab == "spiderden"
        and den.components.container ~= nil
        and den.components.sk_denrole ~= nil
        and not den._sk_dead
        and not den:HasTag("burnt")
        and not (den.components.health ~= nil and den.components.health:IsDead())
end

-- owner == nil: any owner.
function Network.IsStorage(den, owner)
    return IsLiveDen(den) and GetDenRole(den) == STORAGE_ROLE
        and (owner == nil or Network.GetDenOwner(den) == owner)
end

function Network.IsSource(den, owner)
    return IsLiveDen(den) and SOURCE_ROLES[GetDenRole(den)] == true
        and (owner == nil or Network.GetDenOwner(den) == owner)
end

-- Hearts -----------------------------------------------------------------------------------------

local hearts = {} -- [userid] = weak set of hearts

function Network.RegisterHeart(heart, userid)
    if userid == nil then
        return
    end
    local set = hearts[userid]
    if set == nil then
        set = setmetatable({}, { __mode = "k" })
        hearts[userid] = set
    end
    set[heart] = true
end

function Network.UnregisterHeart(heart, userid)
    local set = userid ~= nil and hearts[userid] or nil
    if set ~= nil then
        set[heart] = nil
    end
end

-- Not burnt and not burning: only such a heart links dens (a burnt one may be rebuilt).
function Network.IsHeartStanding(heart)
    return heart ~= nil and heart:IsValid()
        and heart.components.sk_colonyheart ~= nil
        and not heart:HasTag("burnt")
        and not (heart.components.burnable ~= nil and heart.components.burnable:IsBurning())
end

-- Standing and its owner is online with K6: only then does it link dens.
function Network.IsHeartLinked(heart)
    return Network.IsHeartStanding(heart) and heart:HasTag(Network.LINK_TAG)
end

-- One-per-player limit: a burning heart still counts (it may be put out, Burnable:Extinguish).
function Network.HasHeart(userid)
    local set = userid ~= nil and hearts[userid] or nil
    if set ~= nil then
        for heart in pairs(set) do
            if heart:IsValid() and heart.components.sk_colonyheart ~= nil and not heart:HasTag("burnt") then
                return true
            end
        end
    end
    return false
end

-- The linked heart whose network contains this den, or nil. Cheap: one table lookup per owner.
function Network.GetHeartOf(den)
    local owner = Network.GetDenOwner(den)
    local set = owner ~= nil and hearts[owner] or nil
    if set == nil then
        return nil
    end
    local radius = TUNING.SPIDERKINGDOM.HEART_RADIUS
    for heart in pairs(set) do
        if Network.IsHeartLinked(heart) and den:GetDistanceSqToInst(heart) <= radius * radius then
            return heart
        end
    end
end

-- K6 switch: workers and haulers of a paused network wait at their dens (sk_workerhive:IsWorking).
function Network.IsPaused(den)
    local heart = Network.GetHeartOf(den)
    return heart ~= nil and heart.components.sk_colonyheart:IsPaused()
end

-- Dens a hauler serves -----------------------------------------------------------------------------

local function CollectDens(result, seen, center, radius, owner, oneof, test)
    local x, y, z = center.Transform:GetWorldPosition()
    for _, den in ipairs(TheSim:FindEntities(x, 0, z, radius, DEN_MUST, DEN_CANT, oneof)) do
        if not seen[den] and test(den, owner) then
            seen[den] = true
            table.insert(result, den)
        end
    end
end

-- Local area of the hauler's den, plus the whole network if that den is linked to a heart.
local function GetServedDens(home, oneof, test)
    local result = {}
    local owner = Network.GetDenOwner(home)
    if owner == nil then
        return result
    end
    local seen = {}
    CollectDens(result, seen, home, TUNING.SPIDERKINGDOM.LOGISTICS_RADIUS, owner, oneof, test)
    local heart = Network.GetHeartOf(home)
    if heart ~= nil then
        CollectDens(result, seen, heart, TUNING.SPIDERKINGDOM.HEART_RADIUS, owner, oneof, test)
    end
    return result
end

function Network.GetSources(home)
    return GetServedDens(home, SOURCE_ONEOF, Network.IsSource)
end

function Network.GetStorages(home)
    return GetServedDens(home, STORAGE_ONEOF, Network.IsStorage)
end

-- Where a stack goes --------------------------------------------------------------------------------

local function StackSize(item)
    return item.components.stackable ~= nil and item.components.stackable:StackSize() or 1
end

-- How many of this item the den's container takes right now (storage dens may use all 9 slots, so the
-- stock count agrees with the K2 GiveItem wrapper there).
function Network.GetRoomFor(den, item)
    return den.components.container:CanAcceptCount(item)
end

-- Woby's courier rule: a storage den that already holds this item and takes the whole stack, then any
-- that takes the whole stack, then any that takes part of it; the closest one within a tier.
-- Returns den, count (how many it takes) or nil. allow(den) optionally skips dens.
function Network.ChooseStorage(storages, item, from, allow)
    local size = StackSize(item)
    local best, best_tier, best_dsq, best_count = nil, nil, nil, nil
    for _, den in ipairs(storages) do
        if IsLiveDen(den) and (allow == nil or allow(den)) then
            local count = Network.GetRoomFor(den, item)
            if count > 0 then
                local tier = (count >= size and den.components.container:Has(item.prefab, 1) and 1)
                    or (count >= size and 2)
                    or 3
                local dsq = from:GetDistanceSqToInst(den)
                if best == nil or tier < best_tier or (tier == best_tier and dsq < best_dsq) then
                    best, best_tier, best_dsq, best_count = den, tier, dsq, count
                end
            end
        end
    end
    return best, best_count
end

function Network.FindStorageFor(home, item, from, allow)
    return Network.ChooseStorage(Network.GetStorages(home), item, from, allow)
end

-- First slot of a production den holding something a storage den takes right now: slot, den, count.
local function FindTakeable(source, storages, from, allow)
    local container = source.components.container
    for slot = 1, container:GetNumSlots() do
        local item = container:GetItemInSlot(slot)
        if item ~= nil then
            local dest, count = Network.ChooseStorage(storages, item, from, allow)
            if dest ~= nil then
                return slot, dest, count
            end
        end
    end
end

local function HasFreeSlot(den)
    local container = den.components.container
    for slot = 1, den.components.sk_denrole:GetAllowedSlots() do
        if container:GetItemInSlot(slot) == nil then
            return true
        end
    end
    return false
end

-- The production den this hauler should empty next, or nil. Full dens first (their workers are
-- waiting), then the closest; only dens holding something a storage den takes right now.
-- allow(den) lets the caller skip dens (another hauler is heading there, it could not be reached...);
-- it is applied to production and storage dens alike.
function Network.FindHaulJob(home, hauler, allow)
    local storages = Network.GetStorages(home)
    if #storages == 0 then
        return nil
    end
    local best, best_full, best_dsq = nil, nil, nil
    for _, den in ipairs(Network.GetSources(home)) do
        if allow(den) then
            local full = not HasFreeSlot(den)
            local dsq = hauler:GetDistanceSqToInst(den)
            local better = best == nil
                or (full and not best_full)
                or (full == best_full and dsq < best_dsq)
            if better and FindTakeable(den, storages, hauler, allow) ~= nil then
                best, best_full, best_dsq = den, full, dsq
            end
        end
    end
    return best
end

-- Takes one stack (or the part of it a storage den has room for) out of a production den.
-- Returns the item (no longer in any container) and the storage den it is meant for, or nil.
-- Items are moved, never copied: the whole stack leaves its slot, or a split leaves the rest there.
function Network.TakeStack(source, home, hauler, allow)
    local slot, dest, count = FindTakeable(source, Network.GetStorages(home), hauler, allow)
    if slot == nil then
        return nil
    end
    local container = source.components.container
    local item = container:GetItemInSlot(slot)
    local taken
    if count >= StackSize(item) then
        taken = container:RemoveItemBySlot(slot)
    else
        taken = item.components.stackable:Get(count)
    end
    return taken, dest
end

-- Inspect summary --------------------------------------------------------------------------------

-- Dens of the heart's owner in its network, their workers and haulers, and free storage slots.
function Network.GetSummary(heart)
    local summary = { dens = 0, workers = 0, haulers = 0, free = 0 }
    local owner = heart.components.sk_colonyheart:GetOwner()
    if owner == nil then
        return summary
    end
    local x, y, z = heart.Transform:GetWorldPosition()
    for _, den in ipairs(TheSim:FindEntities(x, 0, z, TUNING.SPIDERKINGDOM.HEART_RADIUS, DEN_MUST, DEN_CANT)) do
        if IsLiveDen(den) and Network.GetDenOwner(den) == owner then
            summary.dens = summary.dens + 1

            local hive = den.components.sk_workerhive
            local hauling = hive ~= nil and hive:GetProfession() == "hauler"
            local leader = den.components.leader
            if leader ~= nil then
                for follower in pairs(leader.followers) do
                    local worker = follower.components.sk_worker
                    if worker ~= nil and worker:IsActive() and not worker.retiring then
                        if hauling then
                            summary.haulers = summary.haulers + 1
                        else
                            summary.workers = summary.workers + 1
                        end
                    end
                end
            end

            if GetDenRole(den) == STORAGE_ROLE then
                local container = den.components.container
                for slot = 1, den.components.sk_denrole:GetAllowedSlots() do
                    if container:GetItemInSlot(slot) == nil then
                        summary.free = summary.free + 1
                    end
                end
            end
        end
    end
    return summary
end

-- Skill handler (skilltree/handlers.lua: Wrap(Network.HeartSkill)) ---------------------------------

Network.HeartSkill =
{
    Enable = function(inst)
        inst:AddTag(Network.KEEPER_TAG)
        Ownership.HeartLink.Enable(inst)
    end,
    Disable = function(inst)
        inst:RemoveTag(Network.KEEPER_TAG)
        Ownership.HeartLink.Disable(inst)
    end,
}

-- Client and server: USEITEM "inventoryitem" branch for target:HasTag(Network.HEART_TAG), called from
-- networking/item_actions.lua. The server re-checks the skill and the owner in ACTIONS.SK_HEARTTOGGLE.fn.
function Network.CollectHeartActions(inst, doer, target, actions, right)
    if not right
        and inst.prefab == Network.TOGGLE_ITEM
        and doer:HasTag(Network.KEEPER_TAG)
        and not target:HasTag("burnt") then
        table.insert(actions, ACTIONS.SK_HEARTTOGGLE)
    end
end

return Network
