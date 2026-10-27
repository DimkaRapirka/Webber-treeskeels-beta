-- K4 Web Logistics / K6 Colony Heart wiring (modimport, client and server).
--   * K4 needs no wiring of its own: haulers are K3 workers of storage dens (components/sk_workerhive.lua,
--     components/sk_worker.lua), switched on by the "sk_logistics" owner tag (colony/ownership.lua);
--   * K6: the Colony Heart recipe (one standing heart per player per shard) and the twigs action that
--     pauses / resumes every worker and hauler of the heart's network.
-- Rules shared with the client collector live in colony/network.lua; the collector branch is
-- Network.CollectHeartActions, called from networking/item_actions.lua.

local _G = GLOBAL
local SKUtil = require("spiderkingdom/util")
local Network = require("spiderkingdom/colony/network")

-- Tuning defaults, only for keys spiderkingdom/tuning.lua does not define yet.
local TUNING_DEFAULTS =
{
    LOGISTICS_RADIUS = 20,           -- K4: dens a hauler serves around its storage den
    HAULERS_PER_STAGE = { 1, 1, 2 }, -- K4: haulers per storage den, by den stage
    LOGISTICS_SEARCH_PERIOD = 5,     -- K4: seconds between searches after finding nothing to move
    LOGISTICS_TRIP_TIME = 40,        -- K4: a den not reached in this many seconds is skipped for twice as long
    HEART_RADIUS = 30,               -- K6: dens of the owner this close to the heart form its network
    HEART_WORK = 4,                  -- K6: hammer hits
}
for key, value in pairs(TUNING_DEFAULTS) do
    if _G.TUNING.SPIDERKINGDOM[key] == nil then
        _G.TUNING.SPIDERKINGDOM[key] = value
    end
end

-- Strings --------------------------------------------------------------------------------------

-- English fallback for the action name, in case strings.lua does not have it yet.
if _G.STRINGS.ACTIONS.SK_HEARTTOGGLE == nil then
    _G.STRINGS.ACTIONS.SK_HEARTTOGGLE = { GENERIC = "Toggle workers", PAUSE = "Let workers rest", RESUME = "Wake workers" }
end

-- The recipe's canbuild refusal is read from ACTIONFAIL.BUILD[reason]. Webber has his own BUILD
-- table, which does not fall back to the generic one, so the line goes into both.
local function AddBuildFailString()
    local heart = _G.STRINGS.SK_COLONYHEART
    local text = heart ~= nil and heart.BUILD_HASHEART or nil
    if text == nil then
        return
    end
    for _, character in ipairs({ "GENERIC", "WEBBER" }) do
        local speech = _G.STRINGS.CHARACTERS[character]
        if speech ~= nil and speech.ACTIONFAIL ~= nil then
            if type(speech.ACTIONFAIL.BUILD) ~= "table" then
                speech.ACTIONFAIL.BUILD = {}
            end
            speech.ACTIONFAIL.BUILD.SK_HASHEART = text
        end
    end
end
AddBuildFailString()

local function Say(doer, key)
    local heart = _G.STRINGS.SK_COLONYHEART
    local text = heart ~= nil and heart[key] or nil
    if text ~= nil and doer ~= nil and doer:IsValid() and doer.components.talker ~= nil then
        doer.components.talker:Say(text)
    end
end

-- K6 recipe ------------------------------------------------------------------------------------

-- canbuild runs on the server only (builder:DoBuild), before any ingredient is taken.
-- A burnt heart does not count: hammer it or build a new one.
AddCharacterRecipe(Network.HEART_PREFAB,
    {
        _G.Ingredient("silk", 20),
        _G.Ingredient("spidergland", 10),
        _G.Ingredient("livinglog", 2),
        _G.Ingredient("cutstone", 6),
    },
    _G.TECH.NONE,
    {
        builder_skill = Network.HEART_SKILL,
        placer = Network.HEART_PREFAB.."_placer",
        canbuild = function(recipe, builder, pt, rotation, station, skin)
            return not Network.HasHeart(builder.userid), "SK_HASHEART"
        end,
    },
    { "STRUCTURES" }
)

-- K6 pause / resume: twigs on the heart (the twig is not used up) ------------------------------

local SK_HEARTTOGGLE = _G.Action({ priority = 1, mount_valid = false })
SK_HEARTTOGGLE.id = "SK_HEARTTOGGLE"
SK_HEARTTOGGLE.str = _G.STRINGS.ACTIONS.SK_HEARTTOGGLE
SK_HEARTTOGGLE.strfn = function(act)
    return act.target ~= nil and act.target:HasTag(Network.PAUSED_TAG) and "RESUME" or "PAUSE"
end
SK_HEARTTOGGLE.fn = function(act)
    local doer, heart, item = act.doer, act.target, act.invobject
    if doer == nil or heart == nil or item == nil
        or item.prefab ~= Network.TOGGLE_ITEM
        or heart.components.sk_colonyheart == nil then
        return false
    end
    if not SKUtil.HasSkill(doer, Network.HEART_SKILL) then
        return false
    end
    if not Network.IsHeartStanding(heart) then
        return false, "DORMANT"
    end
    local comp = heart.components.sk_colonyheart
    if not comp:IsOwner(doer) then
        return false, "NOTOWNER"
    end
    if comp:GetOwner() == nil and doer.userid ~= nil then
        comp:SetOwner(doer.userid)
    end

    local paused = comp:TogglePaused()
    Say(doer, paused and "PAUSED" or "RESUMED")
    SKUtil.Log("Colony Heart:", doer, paused and "paused" or "resumed", heart)
    return true
end
AddAction(SK_HEARTTOGGLE)

-- Client collector: Network.CollectHeartActions, called from networking/item_actions.lua.

AddStategraphActionHandler("wilson", _G.ActionHandler(_G.ACTIONS.SK_HEARTTOGGLE, "give"))
AddStategraphActionHandler("wilson_client", _G.ActionHandler(_G.ACTIONS.SK_HEARTTOGGLE, "give"))
