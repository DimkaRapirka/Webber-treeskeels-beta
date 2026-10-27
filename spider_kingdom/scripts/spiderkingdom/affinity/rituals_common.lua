-- Affinity rituals: shared rules. Plain module: require("spiderkingdom/affinity/rituals_common").
-- Client-safe: the client part only reads tags, replicas and the throne's owner netvar.
--
-- The ritual (Phase 5.3): at his OWN Royal Throne (R2) while the queen is INSIDE (not out on an R4
-- expedition), a Webber with Lunar or Shadow Affinity uses ritual materials on the throne
-- (ACTIONS.SK_QUEENRITUAL, affinity/rituals.lua). The side's key item must be in his inventory (also a
-- backpack or worn): it is shown, never spent. Each offering takes min(stack size, still needed) from the
-- stack; the progress per side is saved on the throne (components/sk_royalthrone.lua). When every material
-- of a side is in, the queen becomes that variant and the progress of that side resets.
--   * offering for the side the queen already has is refused (SAMEVARIANT);
--   * a queen of the other side can be turned over with a full new ritual.
--
-- The variant is stored by the queen herself (components/sk_queenvariant.lua): as a component it is part of
-- her save record, so it follows her into the throne record, the owner's save on an R4 expedition and
-- shard migration. Its effects are ACTIVE only while her owner (throne owner / expedition leader) currently
-- has the matching affinity skill (respec keeps the variant, effects off):
--   * on an R4 expedition: planar damage, a damage bonus vs the opposite alignment and a resistance vs her
--     own alignment (components/sk_queenvariant.lua);
--   * at the throne: the R3 workshop provides SPIDERCRAFT level 2 instead of 1 (royalty/workshops.lua),
--     which the affinity gear recipes need.
--
-- Data: VARIANTS below; material counts live in TUNING.SPIDERKINGDOM.QUEEN_RITUAL_LUNAR / _SHADOW.

local SKUtil = require("spiderkingdom/util")
local Thrones = require("spiderkingdom/royalty/thrones")

local Rituals = {}

Rituals.SPIDERWHISPERER_TAG = "spiderwhisperer"

-- One entry per side. Material lists are ordered (progress line order); the counts are in TUNING.
--   key:       prefab that must be held (Enlightened Crown = MakeHat("alterguardian") -> "alterguardianhat",
--              prefabs/hats.lua:16-20 and :7899; Possessed Shadow Atrium, prefabs/shadowheart_infused.lua:167)
--   player_tag: added by the affinity skill (affinity/affinity.lua), the client hint
--   alignment / opposite: official alignment tags of creatures (damagetyperesist / damagetypebonus keys)
Rituals.VARIANTS =
{
    lunar =
    {
        skill = "webber_sk_lunar_affinity",
        player_tag = "player_lunar_aligned",
        key = "alterguardianhat",
        materials = { "moonglass", "purebrilliance" },
        tuning = "QUEEN_RITUAL_LUNAR",
        alignment = "lunar_aligned",
        opposite = "shadow_aligned",
        build = "sk_spider_queen_lunar",  -- anim/sk_spider_queen_lunar.zip: spider_queen_build recoloured (art_src/tools)
    },
    shadow =
    {
        skill = "webber_sk_shadow_affinity",
        player_tag = "player_shadow_aligned",
        key = "shadowheart_infused",
        materials = { "horrorfuel", "nightmarefuel" },
        tuning = "QUEEN_RITUAL_SHADOW",
        alignment = "shadow_aligned",
        opposite = "lunar_aligned",
        build = "sk_spider_queen_shadow", -- black silhouette, white eyes, salmon-pink claws and fangs
    },
}

-- material prefab -> variant (the two sides share no material)
Rituals.VARIANT_BY_MATERIAL = {}
for variant, def in pairs(Rituals.VARIANTS) do
    for _, prefab in ipairs(def.materials) do
        Rituals.VARIANT_BY_MATERIAL[prefab] = variant
    end
end

function Rituals.IsValidVariant(variant)
    return variant ~= nil and Rituals.VARIANTS[variant] ~= nil
end

function Rituals.GetVariantForMaterial(prefab)
    return prefab ~= nil and Rituals.VARIANT_BY_MATERIAL[prefab] or nil
end

-- How many of this material the ritual of this side needs (0 if it is not one of its materials).
function Rituals.GetRequired(variant, prefab)
    local def = Rituals.VARIANTS[variant]
    local counts = def ~= nil and TUNING.SPIDERKINGDOM[def.tuning] or nil
    return counts ~= nil and counts[prefab] or 0
end

-- Client and server: doer holds the side's key in his inventory, backpack or an equip slot. Server: the
-- inventory component; client: its replica (components/inventory_replica.lua:386 Has, :324 GetEquippedItem
-- forward to the component on the server and read inventory_classified on a client). Inventory:Has does not
-- look at equipped items (components/inventory.lua:1507), so a worn crown is checked separately.
function Rituals.HasKey(doer, variant)
    local def = Rituals.VARIANTS[variant]
    if def == nil or doer == nil then
        return false
    end
    local inventory = doer.components.inventory or doer.replica.inventory
    if inventory == nil then
        return false
    end
    if inventory:Has(def.key, 1) then
        return true
    end
    for _, slot in pairs(EQUIPSLOTS) do
        local item = inventory:GetEquippedItem(slot)
        if item ~= nil and item.prefab == def.key then
            return true
        end
    end
    return false
end

-- Server: the variant's effects are on for this owner (player entity) right now.
function Rituals.IsVariantActive(variant, owner)
    local def = variant ~= nil and Rituals.VARIANTS[variant] or nil
    return def ~= nil and owner ~= nil and owner:IsValid() and SKUtil.HasSkill(owner, def.skill)
end

-- Client and server: USEITEM "inventoryitem" branch for target:HasTag(Thrones.THRONE_TAG), called from
-- networking/item_actions.lua next to Expeditions.CollectThroneActions. Only the owner of a throne with the
-- queen inside sees it, and only with a material of his own side and its key. The server re-checks all of
-- it in ACTIONS.SK_QUEENRITUAL.fn (affinity/rituals.lua), plus the skill and "same variant".
function Rituals.CollectThroneActions(inst, doer, target, actions, right)
    if right
        or target:HasTag("burnt")
        or not target:HasTag(Thrones.OCCUPIED_TAG)
        or not doer:HasTag(Rituals.SPIDERWHISPERER_TAG) then
        return
    end
    local variant = Rituals.GetVariantForMaterial(inst.prefab)
    if variant == nil or not doer:HasTag(Rituals.VARIANTS[variant].player_tag) then
        return
    end
    local owner = Thrones.GetOwnerId(target)
    if owner == nil or owner ~= doer.userid then
        return
    end
    if Rituals.HasKey(doer, variant) then
        table.insert(actions, ACTIONS.SK_QUEENRITUAL)
    end
end

return Rituals
