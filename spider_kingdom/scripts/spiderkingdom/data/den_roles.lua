-- K2 Spider Architecture: den roles. Shared by server and client (action collection, display name, slots).
--   item    : marker item Webber gives the den to assign the role (temporary UI until Phase 6)
--   slots   : usable container slots (the container always has 9; extra slots are locked by itemtestfn)
--   build   : own model of that den (bank sk_cocoon, anim/<build>.zip; art_src/tools/gen_cocoon.py)
--   extra_children / defender_mult : living / guard bonuses applied on top of the official stage values

local ROLES =
{
    storage = { item = "boards",      slots = 9, build = "sk_cocoon_storage" },
    living  = { item = "monstermeat", slots = 4, build = "sk_cocoon_living", extra_children = 1 },
    lumber  = { item = "log",         slots = 4, build = "sk_cocoon_lumber" },
    farm    = { item = "seeds",       slots = 4, build = "sk_cocoon_farm" },
    guard   = { item = "stinger",     slots = 4, build = "sk_cocoon_guard", defender_mult = 1.5 },
}

-- An owned den without a role (role taken away) and the shared bank of all role models.
local BASE_BUILD = "sk_cocoon_base"
local BANK = "sk_cocoon"
local STOCK_BANK, STOCK_BUILD = "spider_cocoon", "spider_cocoon" -- prefabs/spiderden.lua

local ROLE_BY_ITEM = {}
for role, data in pairs(ROLES) do
    ROLE_BY_ITEM[data.item] = role
end

local TAG_PREFIX = "sk_denrole_"

-- Works on server and client: reads the networked role tag.
local function GetRoleOfDen(den)
    for role in pairs(ROLES) do
        if den:HasTag(TAG_PREFIX..role) then
            return role
        end
    end
end

return
{
    ROLES = ROLES,
    ROLE_BY_ITEM = ROLE_BY_ITEM,
    TAG_PREFIX = TAG_PREFIX,
    CONTAINER_SLOTS = 9,
    GetRoleOfDen = GetRoleOfDen,
    BANK = BANK,
    BASE_BUILD = BASE_BUILD,
    STOCK_BANK = STOCK_BANK,
    STOCK_BUILD = STOCK_BUILD,
}
