-- Ownership registry (server, per shard): which dens / portable cocoons belong to which player.
-- While the owner is online with a skill, his structures carry that skill's networked tag:
--   sk_cozy      (T3 Cozy Place)  - allies may sleep in them (networking/sleep_actions.lua);
--   sk_workforce (K3 Worker Brood) - lumber / farm dens raise and run worker spiders (colony/workers.lua);
--   sk_logistics (K4 Web Logistics) - storage dens raise and run hauler spiders (components/sk_worker.lua);
--   sk_heartlink (K6 Colony Heart)  - the Colony Heart links its owner's dens (colony/network.lua).
-- A tag marked "explicit" only goes to entities registered with it by name (sk_heartlink: hearts only).
-- Plain module: require("spiderkingdom/colony/ownership"). Tags are not saved; they are rebuilt
-- when the structure loads and when the owner's skill activates (also on login, fromload).

local Ownership = {}

-- tag -> { skill, explicit }
local SKILL_TAGS =
{
    sk_cozy = { skill = "webber_sk_symbiosis_cozy" },
    sk_workforce = { skill = "webber_sk_colony_workers" },
    sk_logistics = { skill = "webber_sk_colony_logistics" },
    sk_heartlink = { skill = "webber_sk_colony_heart", explicit = true },
}

local registry = {} -- [userid] = weak map entity -> true (every non-explicit tag) or a set of tags

local function FindPlayer(userid)
    for _, player in ipairs(AllPlayers) do
        if player.userid == userid then
            return player
        end
    end
end

local function OwnerHasSkill(userid, skill)
    local player = FindPlayer(userid)
    local updater = player ~= nil and player.components.skilltreeupdater or nil
    return updater ~= nil and updater:IsActivated(skill)
end

local function SetTag(ent, tag, on)
    if on then
        ent:AddTag(tag)
    else
        ent:RemoveTag(tag)
    end
end

local function Applies(filter, tag)
    if filter == true then
        return not SKILL_TAGS[tag].explicit
    end
    return filter[tag] == true
end

-- tags: optional set { [tag] = true } limiting which skill tags this entity carries; by default it
-- gets every tag that is not explicit.
function Ownership.Register(ent, userid, tags)
    if userid == nil then
        return
    end
    local set = registry[userid]
    if set == nil then
        set = setmetatable({}, { __mode = "k" })
        registry[userid] = set
    end
    local filter = tags or true
    set[ent] = filter
    for tag, data in pairs(SKILL_TAGS) do
        if Applies(filter, tag) then
            SetTag(ent, tag, OwnerHasSkill(userid, data.skill))
        end
    end
end

-- The entity changed owner or is going away. Its tags stay as they are (the caller decides).
function Ownership.Unregister(ent, userid)
    local set = userid ~= nil and registry[userid] or nil
    if set ~= nil then
        set[ent] = nil
    end
end

-- Called by the skill handlers when the owner's skill changes, and when the owner leaves.
function Ownership.SetOwnerTag(userid, tag, on)
    local set = userid ~= nil and registry[userid] or nil
    if set == nil then
        return
    end
    for ent, filter in pairs(set) do
        if ent:IsValid() and Applies(filter, tag) then
            SetTag(ent, tag, on)
        end
    end
end

function Ownership.SetOwnerCozy(userid, cozy)
    Ownership.SetOwnerTag(userid, "sk_cozy", cozy)
end

-- The owner left the shard (logout, migration, reroll): his structures lose the skill tags.
-- They come back when the skills re-activate on his next login (fromload).
local function OnOwnerRemoved(inst)
    -- A snapshot copy of the session (mainfunctions.lua RestoreSnapshotUserSession) is not the owner leaving.
    if not inst.is_snapshot_user_session then
        for tag in pairs(SKILL_TAGS) do
            Ownership.SetOwnerTag(inst.userid, tag, false)
        end
    end
end

local function MakeSkillHandler(tag)
    return
    {
        Enable = function(inst)
            inst:RemoveEventCallback("onremove", OnOwnerRemoved)
            inst:ListenForEvent("onremove", OnOwnerRemoved)
            Ownership.SetOwnerTag(inst.userid, tag, true)
        end,
        Disable = function(inst)
            Ownership.SetOwnerTag(inst.userid, tag, false)
        end,
    }
end

-- Handler modules (Enable / Disable) for skilltree/handlers.lua.
Ownership.Cozy = MakeSkillHandler("sk_cozy")
Ownership.Workforce = MakeSkillHandler("sk_workforce")
Ownership.Logistics = MakeSkillHandler("sk_logistics")
Ownership.HeartLink = MakeSkillHandler("sk_heartlink") -- used through Network.HeartSkill (colony/network.lua)

-- Server, per player (from networking/sleep_actions.lua): the "tent" state asks IsNearDanger before it
-- hides the sleeper, so the permission is re-checked here at execution time, and wild den spiders
-- are ignored for cozy guests the same way they are for Webber (IsNearDanger skips spiders for
-- "spiderdisguise"). Attackers, other monsters, hounds and fire still count as danger.
local function NeedsPermission(bag)
    return bag:HasTag("spiderden") or bag:HasTag("sk_portablecocoon")
end

-- True if this non-Webber may no longer sleep in this bag (used again right before sleep commits).
function Ownership.IsSleepForbidden(player, bag)
    return bag ~= nil and bag:IsValid()
        and not player:HasTag("spiderwhisperer")
        and NeedsPermission(bag)
        and not bag:HasTag("sk_cozy")
end

function Ownership.WrapIsNearDanger(player)
    local IsNearDanger = player.IsNearDanger
    if IsNearDanger == nil then
        return
    end
    player.IsNearDanger = function(inst, ...)
        if not inst:HasTag("spiderwhisperer") then
            local act = inst:GetBufferedAction()
            local bag = act ~= nil and act.action == ACTIONS.SLEEPIN and act.target or inst.sleepingbag
            if bag ~= nil and bag:IsValid() and NeedsPermission(bag) then
                if not bag:HasTag("sk_cozy") then
                    return true -- no longer allowed: refuse like the stock danger check
                end
                if not inst:HasTag("spiderdisguise") then
                    inst:AddTag("spiderdisguise")
                    local danger = IsNearDanger(inst, ...)
                    inst:RemoveTag("spiderdisguise")
                    return danger
                end
            end
        end
        return IsNearDanger(inst, ...)
    end
end

return Ownership
