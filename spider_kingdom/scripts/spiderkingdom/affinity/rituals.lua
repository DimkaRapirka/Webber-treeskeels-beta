-- Affinity rituals (Phase 5.3): wiring (modimport, after royalty/expedition.lua).
-- Rules and data: affinity/rituals_common.lua. The variant itself: components/sk_queenvariant.lua.
--
--   * Spider Queen post-init (server): every queen gets sk_queenvariant, so the variant saved in her record
--     is loaded wherever the record is spawned (throne, owner's save, migration, wild);
--   * ACTIONS.SK_QUEENRITUAL: a ritual material used on your own throne with the queen inside. The key
--     item is only checked, never spent. Each use takes min(stack, still needed); progress per side is saved
--     on the throne (components/sk_royalthrone.lua). When a side is complete: the queen becomes that variant
--     (sk_royalthrone:SetVariant writes it into her record and refreshes the R3 workshop level), the side's
--     progress resets. Webber says the progress after every offering.
--     Client collector: Rituals.CollectThroneActions (networking/item_actions.lua);
--   * refresh of the variant effects when the owner's affinity skills change: the official
--     "onactivateskill_server" / "ondeactivateskill_server" ({ skill = id }, pushed AFTER the skill state
--     changed, components/skilltreeupdater.lua:81 / :128) and "ms_skilltreeinitialized"
--     (prefabs/player_common_extensions.lua:1100) on the owner -> his thrones' workshop level
--     (royalty/workshops.lua) and his expedition queen's combat effects.
--     The other refresh points are elsewhere: ritual completion (sk_royalthrone:SetVariant), queen leaving /
--     entering the throne (sk_royalthrone OnChanged -> workshop; royalty/expeditions.lua Start / Finish ->
--     queen), owner join (his skills activate again with these events, on load too) and owner leave (R3
--     closes the workshop, royalty/workshops.lua OnOwnerGone; his expedition queen leaves with him).
--
-- Multiplayer: only the throne owner (sk_royalthrone:IsOwner, by userid) can perform the ritual.

local _G = GLOBAL
local SKUtil = require("spiderkingdom/util")
local Thrones = require("spiderkingdom/royalty/thrones")
local Workshops = require("spiderkingdom/royalty/workshops")
local Rituals = require("spiderkingdom/affinity/rituals_common")

-- Strings --------------------------------------------------------------------------------------

local function GetRitualString(key)
    local ritual = _G.STRINGS.SK_RITUAL
    return ritual ~= nil and ritual[key] or nil
end

local function Say(doer, text)
    if text ~= nil and doer ~= nil and doer:IsValid() and doer.components.talker ~= nil then
        doer.components.talker:Say(text)
    end
end

local function GetItemName(prefab)
    return _G.STRINGS.NAMES[string.upper(prefab)] or prefab
end

-- "Moon Shard 8/20, Pure Brilliance 2/5" (the item names are the game's, so they follow its language).
local function GetProgressText(throne, variant)
    local part = GetRitualString("PART") or "%s %d/%d"
    local parts = {}
    for _, prefab in ipairs(Rituals.VARIANTS[variant].materials) do
        local required = Rituals.GetRequired(variant, prefab)
        if required > 0 then
            local have = math.min(throne:GetRitualCount(variant, prefab), required)
            table.insert(parts, string.format(part, GetItemName(prefab), have, required))
        end
    end
    local list = table.concat(parts, GetRitualString("SEPARATOR") or ", ")
    local fmt = GetRitualString("PROGRESS")
    return fmt ~= nil and string.format(fmt, list) or list
end

local function IsComplete(throne, variant)
    for _, prefab in ipairs(Rituals.VARIANTS[variant].materials) do
        if throne:GetRitualCount(variant, prefab) < Rituals.GetRequired(variant, prefab) then
            return false
        end
    end
    return true
end

-- Spider Queen ---------------------------------------------------------------------------------

AddPrefabPostInit(Thrones.QUEEN_PREFAB, function(inst)
    if not _G.TheWorld.ismastersim then
        return
    end
    inst:AddComponent("sk_queenvariant")
end)

-- Owner's skills -------------------------------------------------------------------------------

local function RefreshOwner(player)
    local userid = Thrones.GetUserId(player)
    if userid == nil or player.is_snapshot_user_session then
        return
    end
    -- Thrones of this owner: the workshop level (owneractive looked up from this player).
    Workshops.RefreshOwner(userid, nil, player)
    -- His queen out on an expedition (on this shard).
    local queen = Thrones.GetExpeditionQueen(userid)
    if queen ~= nil and queen.components.sk_queenvariant ~= nil then
        queen.components.sk_queenvariant:Refresh()
    end
end

local AFFINITY_SKILLS = {}
for _, def in pairs(Rituals.VARIANTS) do
    AFFINITY_SKILLS[def.skill] = true
end

local function OnSkillChanged(inst, data)
    if data ~= nil and AFFINITY_SKILLS[data.skill] then
        RefreshOwner(inst)
    end
end

-- Only Webber has the affinity skills of this tree; thrones and expeditions belong to Webbers.
AddPrefabPostInit("webber", function(inst)
    if not _G.TheWorld.ismastersim then
        return
    end
    inst:ListenForEvent("onactivateskill_server", OnSkillChanged)
    inst:ListenForEvent("ondeactivateskill_server", OnSkillChanged)
    inst:ListenForEvent("ms_skilltreeinitialized", RefreshOwner)
end)

-- Action ---------------------------------------------------------------------------------------

-- Server: why this doer cannot offer for this side at this throne right now (nil = he can).
local function GetRefusal(doer, throne, variant)
    local component = throne.components.sk_royalthrone
    if not component:IsOwner(doer) then
        return "NOTOWNER"
    end
    if not Thrones.IsUsable(throne) then
        return "BUSY"
    end
    if not component:HasQueen() then
        return component:IsAway() and "AWAY" or "NOQUEEN"
    end
    if component:GetVariant() == variant then
        return "SAMEVARIANT"
    end
    if not Rituals.HasKey(doer, variant) then
        return "NOKEY"
    end
end

local SK_QUEENRITUAL = _G.Action({ priority = 1, mount_valid = true })
SK_QUEENRITUAL.id = "SK_QUEENRITUAL"
SK_QUEENRITUAL.str = _G.STRINGS.ACTIONS.SK_QUEENRITUAL
SK_QUEENRITUAL.fn = function(act)
    local doer, throne, item = act.doer, act.target, act.invobject
    if doer == nil or throne == nil or item == nil
        or throne.components.sk_royalthrone == nil
        or doer:HasTag("playerghost") then
        return false
    end
    local variant = Rituals.GetVariantForMaterial(item.prefab)
    if variant == nil or not SKUtil.HasSkill(doer, Rituals.VARIANTS[variant].skill) then
        return false
    end
    local reason = GetRefusal(doer, throne, variant)
    if reason ~= nil then
        return false, reason
    end

    local component = throne.components.sk_royalthrone
    local needed = Rituals.GetRequired(variant, item.prefab) - component:GetRitualCount(variant, item.prefab)
    if needed <= 0 then
        return false, "ENOUGH"
    end

    -- min(stack size, still needed); Stackable:Get(n) returns the item itself when n >= its stack
    -- (components/stackable.lua:109-116), which is then removed from the inventory with it.
    local stackable = item.components.stackable
    local count = stackable ~= nil and math.min(stackable:StackSize(), needed) or 1
    local used = stackable ~= nil and stackable:Get(count) or item
    used:Remove()
    component:AddRitualCount(variant, item.prefab, count)

    if IsComplete(component, variant) and component:SetVariant(variant) then
        component:ClearRitual(variant)
        local fx = _G.SpawnPrefab("spawn_fx_medium")
        if fx ~= nil then
            fx.Transform:SetPosition(throne.Transform:GetWorldPosition())
        end
        Say(doer, GetRitualString(variant == "lunar" and "DONE_LUNAR" or "DONE_SHADOW"))
        SKUtil.Log("Queen ritual:", doer, "made the queen in", throne, variant)
    else
        Say(doer, GetProgressText(component, variant))
    end
    return true
end
AddAction(SK_QUEENRITUAL)

-- Client collector: Rituals.CollectThroneActions, called from networking/item_actions.lua.

AddStategraphActionHandler("wilson", _G.ActionHandler(_G.ACTIONS.SK_QUEENRITUAL, "give"))
AddStategraphActionHandler("wilson_client", _G.ActionHandler(_G.ACTIONS.SK_QUEENRITUAL, "give"))
