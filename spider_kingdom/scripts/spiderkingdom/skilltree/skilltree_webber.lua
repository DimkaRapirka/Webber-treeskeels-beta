-- Spider Kingdom skill tree data for Webber, in the same shape as the official
-- prefabs/skilltree_<character>.lua files: BuildSkillsData(SkillTreeFns) -> { SKILLS, ORDERS }.
-- Skill ids are part of the save format (rpc ids are assigned alphabetically). Do not rename them.

local HANDLERS = require("spiderkingdom/skilltree/handlers")

-- Skills that already have working gameplay. Others get an "in development" note.
local IMPLEMENTED =
{
    webber_sk_predator_chitin = true,
    webber_sk_predator_fangs = true,
    webber_sk_predator_molting = true,
    webber_sk_predator_reflexes = true,
    webber_sk_predator_spit = true,
    webber_sk_predator_pack = true,
    webber_sk_symbiosis_nobite = true,
    webber_sk_colony_dens = true,
    webber_sk_colony_architecture = true,
    webber_sk_colony_portable = true,
    webber_sk_colony_workers = true,
    webber_sk_colony_logistics = true,
    webber_sk_colony_heart = true,
    webber_sk_symbiosis_cozy = true,
    webber_sk_symbiosis_mail = true,
    webber_sk_symbiosis_squad = true,
    webber_sk_royal_audience = true,
    webber_sk_royal_throne = true,
    webber_sk_royal_workshop = true,
    webber_sk_royal_expedition = true,
    webber_sk_rider_groomer = true,
    webber_sk_rider_dash = true,
    webber_sk_rider_battle = true,
    webber_sk_rider_faithful = true,
    webber_sk_lunar_affinity = true,
    webber_sk_shadow_affinity = true,
}

-- Layout -------------------------------------------------------------------------------------

local GAP = 38
local HALF = GAP / 2

local TITLE_TOP = 216
local Y1, Y2, Y3 = 186, 150, 114

local TITLE_BOTTOM = 74
local YB1, YB2, YB3 = 44, 26, 8

local COLONY_X = -190
local SYMBIOSIS_X = -60
local PREDATOR_X = 80
local AFFINITY_X = 207
local RIDER_X = -190
local ROYAL_X = -60

local ORDERS =
{
    { "sk_colony",    { COLONY_X,    TITLE_TOP } },
    { "sk_symbiosis", { SYMBIOSIS_X, TITLE_TOP } },
    { "sk_predator",  { PREDATOR_X,  TITLE_TOP } },
    { "allegiance",   { AFFINITY_X,  TITLE_TOP } },
    { "sk_rider",     { RIDER_X,     TITLE_BOTTOM } },
    { "sk_royal",     { ROYAL_X,     TITLE_BOTTOM } },
}

-- Own icons (Phase 6): skilltree/icons.lua, atlas registered in spiderkingdom/visuals.lua.
local ICONS = require("spiderkingdom/skilltree/icons").BY_SKILL

--------------------------------------------------------------------------------------------------

local function BuildSkillsData(SkillTreeFns)
    local skills =
    {
        -- I. COLONY ---------------------------------------------------------------------------
        webber_sk_colony_dens = {
            pos = { COLONY_X, Y1 },
            group = "sk_colony",
            tags = { "sk_colony" },
            root = true,
            connects = { "webber_sk_colony_architecture", "webber_sk_colony_portable" },
        },
        webber_sk_colony_architecture = {
            pos = { COLONY_X - HALF, Y2 },
            group = "sk_colony",
            tags = { "sk_colony" },
            connects = { "webber_sk_colony_workers" },
        },
        webber_sk_colony_portable = {
            pos = { COLONY_X + HALF, Y2 },
            group = "sk_colony",
            tags = { "sk_colony" },
        },
        webber_sk_colony_workers = {
            pos = { COLONY_X - GAP, Y3 },
            group = "sk_colony",
            tags = { "sk_colony" },
            connects = { "webber_sk_colony_logistics" },
        },
        webber_sk_colony_logistics = {
            pos = { COLONY_X, Y3 },
            group = "sk_colony",
            tags = { "sk_colony" },
            connects = { "webber_sk_colony_heart" },
        },
        webber_sk_colony_heart = {
            pos = { COLONY_X + GAP, Y3 },
            group = "sk_colony",
            tags = { "sk_colony" },
        },

        -- II. SYMBIOSIS -----------------------------------------------------------------------
        webber_sk_symbiosis_nobite = {
            pos = { SYMBIOSIS_X, Y1 },
            group = "sk_symbiosis",
            tags = { "sk_symbiosis" },
            root = true,
            connects = { "webber_sk_symbiosis_mail", "webber_sk_symbiosis_cozy" },
        },
        webber_sk_symbiosis_mail = {
            pos = { SYMBIOSIS_X - HALF, Y2 },
            group = "sk_symbiosis",
            tags = { "sk_symbiosis" },
            connects = { "webber_sk_symbiosis_squad" },
        },
        webber_sk_symbiosis_cozy = {
            pos = { SYMBIOSIS_X + HALF, Y2 },
            group = "sk_symbiosis",
            tags = { "sk_symbiosis" },
            connects = { "webber_sk_symbiosis_squad" },
        },
        webber_sk_symbiosis_squad = {
            pos = { SYMBIOSIS_X, Y3 },
            group = "sk_symbiosis",
            tags = { "sk_symbiosis" },
        },

        -- III. PREDATOR -----------------------------------------------------------------------
        webber_sk_predator_chitin = {
            pos = { PREDATOR_X, Y1 },
            group = "sk_predator",
            tags = { "sk_predator" },
            root = true,
            defaultfocus = true,
            connects = { "webber_sk_predator_fangs", "webber_sk_predator_reflexes" },
        },
        webber_sk_predator_fangs = {
            pos = { PREDATOR_X - HALF, Y2 },
            group = "sk_predator",
            tags = { "sk_predator" },
            connects = { "webber_sk_predator_molting", "webber_sk_predator_pack" },
        },
        webber_sk_predator_reflexes = {
            pos = { PREDATOR_X + HALF, Y2 },
            group = "sk_predator",
            tags = { "sk_predator" },
            connects = { "webber_sk_predator_spit", "webber_sk_predator_pack" },
        },
        webber_sk_predator_molting = {
            pos = { PREDATOR_X - GAP, Y3 },
            group = "sk_predator",
            tags = { "sk_predator" },
        },
        webber_sk_predator_pack = {
            pos = { PREDATOR_X, Y3 },
            group = "sk_predator",
            tags = { "sk_predator" },
        },
        webber_sk_predator_spit = {
            pos = { PREDATOR_X + GAP, Y3 },
            group = "sk_predator",
            tags = { "sk_predator" },
        },

        -- IV. RIDER ---------------------------------------------------------------------------
        webber_sk_rider_groomer = {
            pos = { RIDER_X - GAP, YB2 },
            group = "sk_rider",
            tags = { "sk_rider" },
            root = true,
            connects = { "webber_sk_rider_dash", "webber_sk_rider_battle" },
        },
        webber_sk_rider_dash = {
            pos = { RIDER_X, YB1 },
            group = "sk_rider",
            tags = { "sk_rider" },
            connects = { "webber_sk_rider_faithful" },
        },
        webber_sk_rider_battle = {
            pos = { RIDER_X, YB3 },
            group = "sk_rider",
            tags = { "sk_rider" },
            connects = { "webber_sk_rider_faithful" },
        },
        webber_sk_rider_faithful = {
            pos = { RIDER_X + GAP, YB2 },
            group = "sk_rider",
            tags = { "sk_rider" },
        },

        -- V. ROYAL COURT ----------------------------------------------------------------------
        webber_sk_royal_audience = {
            pos = { ROYAL_X - GAP, YB2 },
            group = "sk_royal",
            tags = { "sk_royal" },
            root = true,
            connects = { "webber_sk_royal_throne" },
        },
        webber_sk_royal_throne = {
            pos = { ROYAL_X, YB2 },
            group = "sk_royal",
            tags = { "sk_royal" },
            connects = { "webber_sk_royal_workshop", "webber_sk_royal_expedition" },
        },
        webber_sk_royal_workshop = {
            pos = { ROYAL_X + GAP, YB1 },
            group = "sk_royal",
            tags = { "sk_royal" },
        },
        webber_sk_royal_expedition = {
            pos = { ROYAL_X + GAP, YB3 },
            group = "sk_royal",
            tags = { "sk_royal" },
        },

        -- VI. AFFINITY (same lock pattern as prefabs/skilltree_wurt.lua) ----------------------
        webber_sk_allegiance_lock_count = {
            pos = { AFFINITY_X, Y1 },
            group = "allegiance",
            tags = { "allegiance", "lock" },
            root = true,
            lock_open = function(prefabname, activatedskills, readonly)
                return SkillTreeFns.CountSkills(prefabname, activatedskills) >= TUNING.SPIDERKINGDOM.AFFINITY_SKILLS_REQUIRED
            end,
        },
        webber_sk_allegiance_lock_celestial = SkillTreeFns.MakeCelestialChampionLock(
            { pos = { AFFINITY_X - HALF, Y2 } }
        ),
        webber_sk_allegiance_lock_fuelweaver = SkillTreeFns.MakeFuelWeaverLock(
            { pos = { AFFINITY_X + HALF, Y2 } }
        ),
        webber_sk_allegiance_lock_noshadow = SkillTreeFns.MakeNoShadowLock(
            { pos = { AFFINITY_X - HALF, Y3 } }
        ),
        webber_sk_allegiance_lock_nolunar = SkillTreeFns.MakeNoLunarLock(
            { pos = { AFFINITY_X + HALF, Y3 } }
        ),

        webber_sk_lunar_affinity = {
            pos = { AFFINITY_X - HALF, YB1 },
            group = "allegiance",
            tags = { "allegiance", "lunar", "lunar_favor" },
            locks = { "webber_sk_allegiance_lock_count", "webber_sk_allegiance_lock_celestial", "webber_sk_allegiance_lock_noshadow" },
        },
        webber_sk_shadow_affinity = {
            pos = { AFFINITY_X + HALF, YB1 },
            group = "allegiance",
            tags = { "allegiance", "shadow", "shadow_favor" },
            locks = { "webber_sk_allegiance_lock_count", "webber_sk_allegiance_lock_fuelweaver", "webber_sk_allegiance_lock_nolunar" },
        },
    }

    local SKILL_STRINGS = STRINGS.SKILLTREE.WEBBER

    for name, data in pairs(skills) do
        local uppercase_name = string.upper(name)

        if not data.desc then
            data.desc = SKILL_STRINGS[uppercase_name.."_DESC"]
        end

        -- If it's not a lock.
        if not data.lock_open then
            if not data.title then
                data.title = SKILL_STRINGS[uppercase_name.."_TITLE"]
            end

            if not IMPLEMENTED[name] and data.desc ~= nil then
                data.desc = data.desc..SKILL_STRINGS.SK_IN_DEVELOPMENT
            end

            data.icon = data.icon or ICONS[name]

            local handlers = HANDLERS[name]
            if handlers ~= nil then
                data.onactivate = data.onactivate or handlers.onactivate
                data.ondeactivate = data.ondeactivate or handlers.ondeactivate
            end
        end
    end

    return {
        SKILLS = skills,
        ORDERS = ORDERS,
    }
end

return BuildSkillsData
