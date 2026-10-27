-- R3 Royal Workshop: shared rules. Plain module: require("spiderkingdom/royalty/workshops").
--   * the workshop state of a throne (server): while the throne holds a queen and its owner is online on
--     this shard with R3, the throne carries the official prototyper component with the SPIDERCRAFT tree
--     (TUNING.PROTOTYPER_TREES.SPIDERCRAFT = TECH.SPIDERCRAFT_ONE, which no vanilla structure provides)
--     and the networked tag WORKSHOP_TAG. Nothing of it is saved: it is rebuilt when the queen moves in or
--     out (components/sk_royalthrone.lua) and when the owner's R3 activates (also on login, fromload);
--   * the brood types a living den can be set to (mutator item -> spider prefab) and the Royal Egg Sacks;
--   * the R3 skill handler (Enable / Disable) for skilltree/handlers.lua;
--   * the client collector branch for SK_SETBROOD, called from networking/item_actions.lua.
-- Affinity rituals (affinity/rituals_common.lua): while the queen inside has a variant whose effects are
-- active (her owner has the matching affinity skill), the open workshop provides SPIDERCRAFT level 2
-- (VARIANT_TREES) instead of TUNING.PROTOTYPER_TREES.SPIDERCRAFT; the affinity gear recipes need it.
-- Changing prototyper.trees on an open workshop needs no refresh: every builder re-reads the trees of the
-- nearest prototyper each frame (components/builder.lua:37 StartUpdatingComponent, :132-133 OnUpdate ->
-- EvaluateTechTrees, :274 CopyTechTrees(prototyper.trees, ...), :412-414 pushes "techtreechange").
-- The den side is components/sk_brood.lua, the wiring royalty/workshop.lua.

local SKUtil = require("spiderkingdom/util")
local Thrones = require("spiderkingdom/royalty/thrones")
local DenRoles = require("spiderkingdom/data/den_roles")
local Rituals = require("spiderkingdom/affinity/rituals_common")
local TechTree = require("techtree")

local Workshops = {}

Workshops.SKILL = "webber_sk_royal_workshop"
Workshops.ARTISAN_TAG = "sk_royalartisan"     -- player with R3 (client hint for SK_SETBROOD)
Workshops.WORKSHOP_TAG = "sk_royalworkshop"   -- throne whose workshop is active right now
Workshops.LIVING_ROLE = "living"              -- K2 role whose brood can be chosen
Workshops.JELLY_PREFAB = "sk_brood_jelly"
Workshops.EGGSACK_PREFIX = "sk_royal_eggsack_"

-- Affinity rituals: the tree of an open workshop whose queen has an active variant (techtree.lua:72 Create
-- fills every other tech with 0, like TUNING.PROTOTYPER_TREES.SPIDERCRAFT in tuning.lua:1434).
Workshops.VARIANT_TREES = TechTree.Create({ SPIDERCRAFT = 2 })

-- Brood types. Sea Striders (mutator_water) are left out on purpose: their brain expects water around
-- them, which a den on land does not give.
Workshops.BROODS =
{
    { key = "warrior", mutator = "mutator_warrior", prefab = "spider_warrior", colour = { 1, 0.8, 0.7, 1 } },
    { key = "hider",   mutator = "mutator_hider",   prefab = "spider_hider",   colour = { 0.75, 0.75, 0.75, 1 } },
    { key = "spitter", mutator = "mutator_spitter", prefab = "spider_spitter", colour = { 0.75, 0.9, 0.7, 1 } },
    { key = "dropper", mutator = "mutator_dropper", prefab = "spider_dropper", colour = { 0.95, 0.95, 1, 1 } },
    { key = "healer",  mutator = "mutator_healer",  prefab = "spider_healer",  colour = { 1, 0.85, 0.95, 1 } },
    { key = "moon",    mutator = "mutator_moon",    prefab = "spider_moon",    colour = { 0.75, 0.9, 1, 1 } },
}

Workshops.BROOD_BY_MUTATOR = {}
Workshops.BROOD_BY_PREFAB = {}
for _, brood in ipairs(Workshops.BROODS) do
    Workshops.BROOD_BY_MUTATOR[brood.mutator] = brood
    Workshops.BROOD_BY_PREFAB[brood.prefab] = brood
end

function Workshops.GetEggSackPrefab(brood)
    return Workshops.EGGSACK_PREFIX..brood.key
end

-- Client and server: display name of a brood type (STRINGS.SK_ROYAL.BROOD_NAMES, then the vanilla name).
function Workshops.GetBroodName(prefab)
    local key = string.upper(prefab)
    local royal = STRINGS.SK_ROYAL
    return (royal ~= nil and royal.BROOD_NAMES ~= nil and royal.BROOD_NAMES[key])
        or STRINGS.NAMES[key]
        or prefab
end

-- Server: workshop state ----------------------------------------------------------------------------

local function FindPlayer(userid)
    for _, player in ipairs(AllPlayers) do
        if player.userid == userid then
            return player
        end
    end
end

local function OnActivate(inst, doer, recipe)
    inst:PushEvent("sk_workshopactivated", { doer = doer, recipe = recipe })
end

-- trees: the tech tree while on (TUNING.PROTOTYPER_TREES.SPIDERCRAFT or VARIANT_TREES).
local function SetActive(throne, on, trees)
    local was = throne.components.prototyper ~= nil
    if on and was then
        -- Already open: only the level may change (read by builders every frame, see the header).
        throne.components.prototyper.trees = trees
    elseif on and not was then
        local prototyper = throne:AddComponent("prototyper")
        prototyper.trees = trees
        -- Only Webbers: for anyone else the builder skips the throne and keeps using the next
        -- machine (components/builder.lua EvaluateTechTrees), so the throne never "steals" science.
        prototyper.restrictedtag = "spiderwhisperer"
        prototyper.onactivate = OnActivate
        throne:AddTag(Workshops.WORKSHOP_TAG)
    elseif not on and was then
        -- Prototyper:OnRemoveFromEntity removes the "prototyper" tag and turns it off for every user.
        throne:RemoveComponent("prototyper")
        throne:RemoveTag(Workshops.WORKSHOP_TAG)
    end
    if on ~= was then
        throne:PushEvent("sk_workshopchanged", { on = on })
    end
end

-- owneractive: nil = look the owner up now; true / false = the caller already knows (skill handler,
-- owner leaving the shard).
-- owner: the owner's player entity if the caller has it (skill events), otherwise looked up by userid.
function Workshops.RefreshThrone(throne, owneractive, owner)
    if throne == nil or not throne:IsValid() then
        return
    end
    local component = throne.components.sk_royalthrone
    if component == nil then
        SetActive(throne, false)
        return
    end
    local userid = component:GetOwner()
    if owner == nil and userid ~= nil then
        owner = FindPlayer(userid)
    end
    if owneractive == nil then
        owneractive = userid ~= nil and SKUtil.HasSkill(owner, Workshops.SKILL)
    end
    local on = owneractive and component:HasQueen() and Thrones.IsUsable(throne)
    -- Affinity rituals: the queen's variant raises the level while its effects are active.
    local trees = on and Rituals.IsVariantActive(component:GetVariant(), owner)
        and Workshops.VARIANT_TREES
        or TUNING.PROTOTYPER_TREES.SPIDERCRAFT
    SetActive(throne, on, trees)
end

function Workshops.RefreshOwner(userid, owneractive, owner)
    for _, throne in ipairs(Thrones.GetAllThrones(userid)) do
        Workshops.RefreshThrone(throne, owneractive, owner)
    end
end

-- Server: an active workshop throne of this player within range of ent, or nil.
function Workshops.FindActiveThrone(userid, ent, range)
    local rangesq = range * range
    for _, throne in ipairs(Thrones.GetThrones(userid)) do
        if throne:HasTag(Workshops.WORKSHOP_TAG) and ent:GetDistanceSqToInst(throne) <= rangesq then
            return throne
        end
    end
end

-- R3 skill handler (skilltree/handlers.lua: Wrap(Workshops)) -----------------------------------------

-- The owner left the shard (logout, migration, reroll) or turned into another character (Wonkey:
-- CommonSeamlessPlayerSwap clears inst.userid first, so the id is remembered at Enable). Deferred one
-- frame: removing the prototyper inside "onremove" would let its own copied onremove callback run on a
-- cleared component (entityscript.lua PushEvent copies the callbacks first). By then the leaving entity
-- is out of AllPlayers, so the lookup sees whoever really owns the id now (e.g. the restored Webber).
local function OnOwnerGone(inst)
    -- A snapshot copy of the session (mainfunctions.lua RestoreSnapshotUserSession) is not the owner leaving.
    local userid = inst._sk_workshop_userid
    if userid == nil or userid == "" or inst.is_snapshot_user_session then
        return
    end
    TheWorld:DoTaskInTime(0, function()
        Workshops.RefreshOwner(userid)
    end)
end

function Workshops.Enable(inst)
    inst:AddTag(Workshops.ARTISAN_TAG)
    inst._sk_workshop_userid = inst.userid
    inst:RemoveEventCallback("onremove", OnOwnerGone)
    inst:RemoveEventCallback("seamlessplayerswap", OnOwnerGone)
    inst:ListenForEvent("onremove", OnOwnerGone)
    inst:ListenForEvent("seamlessplayerswap", OnOwnerGone)
    Workshops.RefreshOwner(inst.userid, true, inst)
end

-- Respec: the throne, the queen and every brood choice stay; the workshop just closes.
function Workshops.Disable(inst)
    inst:RemoveTag(Workshops.ARTISAN_TAG)
    inst:RemoveEventCallback("onremove", OnOwnerGone)
    inst:RemoveEventCallback("seamlessplayerswap", OnOwnerGone)
    Workshops.RefreshOwner(inst.userid, false, inst)
end

-- Client and server: SK_SETBROOD collector branch ----------------------------------------------------

local WORKSHOP_MUST_TAGS = { Thrones.THRONE_TAG, Workshops.WORKSHOP_TAG }

-- Client and server. Any active workshop counts here; the server checks that it is the doer's own.
function Workshops.IsNearActiveWorkshop(ent)
    local x, y, z = ent.Transform:GetWorldPosition()
    return #TheSim:FindEntities(x, y, z, TUNING.SPIDERKINGDOM.ROYAL_WORKSHOP_BROOD_RANGE, WORKSHOP_MUST_TAGS) > 0
end

-- USEITEM "inventoryitem" branch for a spider den (networking/item_actions.lua CollectDenActions, before
-- the STORE suppression; SK_SETBROOD is in its DEN_ITEM_ACTIONS). Only offered when it can make sense, so
-- a mutator can still be stored in a living den away from the workshop.
function Workshops.CollectDenActions(inst, doer, target, actions, right)
    if not right
        and Workshops.BROOD_BY_MUTATOR[inst.prefab] ~= nil
        and doer:HasTag(Workshops.ARTISAN_TAG)
        and DenRoles.GetRoleOfDen(target) == Workshops.LIVING_ROLE
        and Workshops.IsNearActiveWorkshop(target) then
        table.insert(actions, ACTIONS.SK_SETBROOD)
    end
end

return Workshops
