-- sk_queenvariant (server only): the Affinity variant of a Spider Queen ("lunar" / "shadow" or none),
-- won by the queen ritual at the Royal Throne (affinity/rituals.lua). Added to every "spiderqueen" by
-- affinity/rituals.lua, so it exists wherever her save record is spawned.
--
-- Storage: OnSave puts { variant = v } into her save record (entityscript.lua:1906 GetPersistData collects
-- every component's OnSave under data[<component name>]; :248 GetSaveRecord stores it as record.data, :313;
-- mainfunctions.lua:464 SpawnSaveRecord -> entityscript.lua:1957 SetPersistData calls OnLoad with it). So the
-- variant travels with her by itself: into the throne's record (sk_royalthrone StoreQueen / ReleaseQueen),
-- the owner's save on an R4 expedition and shard migration (sk_spiderkeeper saves her GetSaveRecord()).
-- While she sits in the throne as a record, sk_royalthrone:Get/SetVariant read and write
-- record.data.sk_queenvariant directly (the same table this OnSave produces).
--
-- Look: the variant's own build (Rituals.VARIANTS[v].build, recoloured spider_queen_build with the same
-- symbols, so every stock "spider_queen" bank animation works), set whenever the variant is set or loaded.
-- Kept on a wild queen too. AnimState is networked, clients see it without extra code.
--
-- Effects (Refresh): only on an R4 expedition (inst._sk_expedition, royalty/expeditions.lua) and only while
-- her leader currently has the matching affinity skill (respec keeps the variant, effects off):
--   * planardamage bonus TUNING.SPIDERKINGDOM.QUEEN_VARIANT_PLANAR (components/planardamage.lua AddBonus;
--     planar damage is collected from the attacker's own component when she attacks without a weapon,
--     components/combat.lua CalcDamage -> SpDamageUtil.CollectSpDamage, spdamageutil.lua:22-25);
--   * damagetypebonus vs the opposite alignment tag (QUEEN_VARIANT_BONUS, a damage multiplier,
--     components/damagetypebonus.lua GetBonus);
--   * damagetyperesist vs her own alignment tag (QUEEN_VARIANT_RESIST, a damage-taken multiplier,
--     components/damagetyperesist.lua GetResist; read by components/combat.lua:645 in GetAttacked_Internal).
-- The stock queen has none of these components (prefabs/spiderqueen.lua); they are added on first use and
-- left in place (empty modifier lists change nothing). Every modifier uses this component's key.
-- Refreshed by: SetVariant / OnLoad, expedition start and end (royalty/expeditions.lua), and the owner's
-- affinity skill events (affinity/rituals.lua).

local Rituals = require("spiderkingdom/affinity/rituals_common")

local EFFECT_KEY = "sk_queenvariant"
local STOCK_BUILD = "spider_queen_build" -- prefabs/spiderqueen.lua

local QueenVariant = Class(function(self, inst)
    self.inst = inst
    self.variant = nil -- "lunar" / "shadow" / nil (saved)
    self.active = nil  -- variant whose effects are applied right now (not saved, see Refresh)
end)

function QueenVariant:OnRemoveFromEntity()
    self:SetEffects(nil)
end

function QueenVariant:GetVariant()
    return self.variant
end

function QueenVariant:ApplyLook()
    local def = self.variant ~= nil and Rituals.VARIANTS[self.variant] or nil
    self.inst.AnimState:SetBuild(def ~= nil and def.build or STOCK_BUILD)
end

function QueenVariant:SetVariant(variant)
    if not Rituals.IsValidVariant(variant) then
        variant = nil
    end
    self.variant = variant
    self:ApplyLook()
    self:Refresh()
end

-- Effects ----------------------------------------------------------------------------------------

local function GetOrAdd(inst, name)
    return inst.components[name] or inst:AddComponent(name)
end

-- variant: the side whose effects should be on, or nil for none. Idempotent.
function QueenVariant:SetEffects(variant)
    if self.active == variant then
        return
    end
    local inst = self.inst

    local old = self.active ~= nil and Rituals.VARIANTS[self.active] or nil
    if old ~= nil then
        if inst.components.planardamage ~= nil then
            inst.components.planardamage:RemoveBonus(inst, EFFECT_KEY)
        end
        if inst.components.damagetypebonus ~= nil then
            inst.components.damagetypebonus:RemoveBonus(old.opposite, inst, EFFECT_KEY)
        end
        if inst.components.damagetyperesist ~= nil then
            inst.components.damagetyperesist:RemoveResist(old.alignment, inst, EFFECT_KEY)
        end
    end

    self.active = variant
    local def = variant ~= nil and Rituals.VARIANTS[variant] or nil
    if def ~= nil then
        local tuning = TUNING.SPIDERKINGDOM
        GetOrAdd(inst, "planardamage"):AddBonus(inst, tuning.QUEEN_VARIANT_PLANAR, EFFECT_KEY)
        GetOrAdd(inst, "damagetypebonus"):AddBonus(def.opposite, inst, tuning.QUEEN_VARIANT_BONUS, EFFECT_KEY)
        GetOrAdd(inst, "damagetyperesist"):AddResist(def.alignment, inst, tuning.QUEEN_VARIANT_RESIST, EFFECT_KEY)
    end
end

-- The expedition leader (royalty/expeditions.lua keeps him in inst._sk_expedition.owner), or nil.
function QueenVariant:GetOwner()
    local expedition = self.inst._sk_expedition
    return expedition ~= nil and expedition.owner or nil
end

function QueenVariant:IsActive()
    return self.active ~= nil
end

function QueenVariant:Refresh()
    local owner = self:GetOwner()
    local on = self.variant ~= nil and Rituals.IsVariantActive(self.variant, owner)
    self:SetEffects(on and self.variant or nil)
end

-- Save -------------------------------------------------------------------------------------------

function QueenVariant:OnSave()
    return self.variant ~= nil and { variant = self.variant } or nil
end

function QueenVariant:OnLoad(data)
    if data ~= nil and data.variant ~= nil then
        self:SetVariant(data.variant)
    end
end

function QueenVariant:GetDebugString()
    return string.format("variant: %s, active: %s", tostring(self.variant), tostring(self.active))
end

return QueenVariant
