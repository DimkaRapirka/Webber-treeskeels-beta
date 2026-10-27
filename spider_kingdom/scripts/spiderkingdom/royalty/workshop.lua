-- R3 Royal Workshop: wiring (modimport, after colony/denroles.lua and royalty/throne.lua).
--   * the throne as a crafting place: royalty/workshops.lua adds the official prototyper component with
--     TUNING.PROTOTYPER_TREES.SPIDERCRAFT (TECH.SPIDERCRAFT_ONE) while the workshop is open. Webbers near
--     it can prototype the stock mutators without befriending each spider type first (vanilla only unlocks
--     them in prefabs/spider.lua OnStartLeashing). Like any prototyped recipe they stay learned. The R3
--     recipes (royalty/recipes.lua) are nounlock: they can only ever be crafted at an open workshop;
--   * brood composition: Webber with R3 uses a mutator on his K2 living den within range of his open
--     workshop -> SK_SETBROOD; the den raises that spider type from then on (components/sk_brood.lua).
--     The same mutator again turns it back to stock spiders (not consumed then; on a Royal Egg Sack den
--     this also ends its innate brood for good).
-- The client collector branch is Workshops.CollectDenActions, called from networking/item_actions.lua.

local _G = GLOBAL
local SKUtil = require("spiderkingdom/util")
local Thrones = require("spiderkingdom/royalty/thrones")
local Workshops = require("spiderkingdom/royalty/workshops")
local DenRoles = require("spiderkingdom/data/den_roles")

-- Strings --------------------------------------------------------------------------------------

local function GetRoyalString(key)
    local royal = _G.STRINGS.SK_ROYAL
    return royal ~= nil and royal[key] or nil
end

-- Royal Egg Sack names are built from one template per language and the brood names, unless strings.lua
-- already defines them explicitly.
local function AddEggSackStrings()
    local name_fmt = GetRoyalString("EGGSACK_NAME")
    local desc_fmt = GetRoyalString("EGGSACK_RECIPE_DESC")
    local describe = GetRoyalString("EGGSACK_DESCRIBE")
    for _, brood in ipairs(Workshops.BROODS) do
        local key = string.upper(Workshops.GetEggSackPrefab(brood))
        local broodname = Workshops.GetBroodName(brood.prefab)
        if name_fmt ~= nil and _G.STRINGS.NAMES[key] == nil then
            _G.STRINGS.NAMES[key] = string.format(name_fmt, broodname)
        end
        if desc_fmt ~= nil and _G.STRINGS.RECIPE_DESC[key] == nil then
            _G.STRINGS.RECIPE_DESC[key] = string.format(desc_fmt, broodname)
        end
        if describe ~= nil then
            for _, character in ipairs({ "GENERIC", "WEBBER" }) do
                local speech = _G.STRINGS.CHARACTERS[character]
                if speech ~= nil and speech.DESCRIBE ~= nil and speech.DESCRIBE[key] == nil then
                    speech.DESCRIBE[key] = describe
                end
            end
        end
    end
end
AddEggSackStrings()

-- A non-Webber who clicks the open workshop: builder:UsePrototyper refuses with the prototyper's
-- restrictedtag as reason (components/builder.lua) -> ACTIONFAIL.OPEN_CRAFTING.SPIDERWHISPERER.
-- Every character has its own OPEN_CRAFTING table, which does not fall back to GENERIC's.
local function AddOpenCraftingFailString()
    local text = GetRoyalString("WORKSHOP_NOTWEBBER")
    if text == nil then
        return
    end
    for _, speech in pairs(_G.STRINGS.CHARACTERS) do
        if type(speech) == "table" and type(speech.ACTIONFAIL) == "table" then
            if type(speech.ACTIONFAIL.OPEN_CRAFTING) ~= "table" then
                speech.ACTIONFAIL.OPEN_CRAFTING = {}
            end
            if speech.ACTIONFAIL.OPEN_CRAFTING.SPIDERWHISPERER == nil then
                speech.ACTIONFAIL.OPEN_CRAFTING.SPIDERWHISPERER = text
            end
        end
    end
end
AddOpenCraftingFailString()

local function Say(doer, text)
    if text ~= nil and doer ~= nil and doer:IsValid() and doer.components.talker ~= nil then
        doer.components.talker:Say(text)
    end
end

-- Crafting menu --------------------------------------------------------------------------------

-- A research-style station (like the science machines): the menu does not switch to a station tab, the
-- mutators show as "prototype" and the R3 goods as craftable in Webber's character filter. The verb on
-- the throne becomes "Use" instead of "Research at".
if _G.PROTOTYPER_DEFS ~= nil and _G.PROTOTYPER_DEFS[Thrones.THRONE_PREFAB] == nil then
    _G.PROTOTYPER_DEFS[Thrones.THRONE_PREFAB] =
    {
        icon_atlas = _G.CRAFTING_ICONS_ATLAS,
        icon_image = "station_none.tex",
        is_crafting_station = false,
        action_str = "USE",
    }
end

-- Dens -----------------------------------------------------------------------------------------

-- "spiderden" covers spiderden_2 / spiderden_3 too (SetPrefabName, see colony/denroles.lua).
AddPrefabPostInit("spiderden", function(inst)
    if not _G.TheWorld.ismastersim then
        return
    end

    inst:AddComponent("sk_brood")

    -- Only regular children asked for by childname "spider" change type: SpawnDefenders sets childname
    -- to "spider_warrior" for its warriors and back to "spider" afterwards (prefabs/spiderden.lua), and
    -- an explicit prefab argument is kept as is. Rare / foreign children (GetChildPrefab) still win.
    local childspawner = inst.components.childspawner
    if childspawner ~= nil then
        local SpawnChild = childspawner.SpawnChild
        childspawner.SpawnChild = function(self, target, prefab, ...)
            if prefab == nil and self.childname == "spider" then
                prefab = inst.components.sk_brood:GetActivePrefab()
            end
            return SpawnChild(self, target, prefab, ...)
        end
    end
end)

-- Set-brood action -----------------------------------------------------------------------------

local function IsDenUsable(den)
    return den:IsValid() and not den:HasTag("burnt")
        and not (den.components.health ~= nil and den.components.health:IsDead())
end

local SK_SETBROOD = _G.Action({ priority = 1, mount_valid = false })
SK_SETBROOD.id = "SK_SETBROOD"
SK_SETBROOD.str = _G.STRINGS.ACTIONS.SK_SETBROOD
SK_SETBROOD.fn = function(act)
    local doer, den, item = act.doer, act.target, act.invobject
    if doer == nil or den == nil or item == nil
        or den.components.sk_brood == nil or den.components.sk_denrole == nil
        or not IsDenUsable(den) then
        return false
    end
    local brood = Workshops.BROOD_BY_MUTATOR[item.prefab]
    if brood == nil or not SKUtil.HasSkill(doer, Workshops.SKILL) then
        return false
    end
    if DenRoles.GetRoleOfDen(den) ~= Workshops.LIVING_ROLE then
        return false, "NOTLIVING"
    end
    if not den.components.sk_denrole:IsOwner(doer) then
        return false, "NOTOWNER"
    end
    if Workshops.FindActiveThrone(doer.userid, den, TUNING.SPIDERKINGDOM.ROYAL_WORKSHOP_BROOD_RANGE) == nil then
        return false, "NOWORKSHOP"
    end

    local component = den.components.sk_brood
    if component:GetBrood() == brood.prefab then
        -- Same type again: back to stock spiders, the mutator is kept.
        component:Clear()
        Say(doer, GetRoyalString("BROOD_CLEARED"))
        return true
    end

    local used = item.components.stackable ~= nil and item.components.stackable:Get() or item
    used:Remove()

    -- A den planted from a Royal Egg Sack stays innate with its new type.
    component:SetBrood(brood.prefab, doer.userid, component:IsInnate())
    local fmt = GetRoyalString("BROOD_SET")
    Say(doer, fmt ~= nil and string.format(fmt, Workshops.GetBroodName(brood.prefab)) or nil)
    SKUtil.Log("Royal Workshop:", doer, "set the brood of", den, "to", brood.prefab)
    return true
end
AddAction(SK_SETBROOD)

-- Client collector: Workshops.CollectDenActions, called from networking/item_actions.lua.

AddStategraphActionHandler("wilson", _G.ActionHandler(_G.ACTIONS.SK_SETBROOD, "give"))
AddStategraphActionHandler("wilson_client", _G.ActionHandler(_G.ACTIONS.SK_SETBROOD, "give"))
