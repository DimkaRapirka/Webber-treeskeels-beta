-- sk_brood (server only, on every spider den): R3 Royal Workshop brood composition.
-- Remembers which spider type a den raises instead of the stock "spider". The den's own SpawnChild is
-- wrapped in royalty/workshop.lua and asks GetActivePrefab() for every regular child; warriors called out
-- by SpawnDefenders (childname "spider_warrior"), emergency children and K3 workers (spawned directly by
-- sk_workerhive) are never changed.
--
-- Two kinds of brood:
--   * chosen  : set with a mutator on a K2 living den. Applies only while the den keeps the living role
--               and an active workshop of the player who chose it is within range. Respec, logout or an
--               empty throne pause it; the choice itself is saved and comes back with the workshop;
--   * innate  : den planted from a Royal Egg Sack. Always applies, whatever role or skill.
-- Children already outside keep their type; the count inside simply hatches as the new type.

local DenRoles = require("spiderkingdom/data/den_roles")
local Workshops = require("spiderkingdom/royalty/workshops")

local Brood = Class(function(self, inst)
    self.inst = inst
    self.prefab = nil   -- spider prefab raised instead of "spider"
    self.userid = nil   -- player who chose it (chosen brood)
    self.innate = false
end)

function Brood:GetBrood()
    return self.prefab
end

function Brood:IsInnate()
    return self.innate
end

function Brood:SetBrood(prefab, userid, innate)
    if Workshops.BROOD_BY_PREFAB[prefab] == nil then
        return false
    end
    self.prefab = prefab
    self.userid = userid
    self.innate = innate == true
    self.inst:PushEvent("sk_broodchanged", { prefab = prefab })
    return true
end

function Brood:Clear()
    self.prefab = nil
    self.userid = nil
    self.innate = false
    self.inst:PushEvent("sk_broodchanged", {})
end

-- The prefab the next regular child should be, or nil for the stock one.
function Brood:GetActivePrefab()
    if self.prefab == nil then
        return nil
    elseif self.innate then
        return self.prefab
    elseif DenRoles.GetRoleOfDen(self.inst) ~= Workshops.LIVING_ROLE then
        return nil
    elseif Workshops.FindActiveThrone(self.userid, self.inst, TUNING.SPIDERKINGDOM.ROYAL_WORKSHOP_BROOD_RANGE) == nil then
        return nil
    end
    return self.prefab
end

function Brood:OnSave()
    if self.prefab ~= nil then
        return { prefab = self.prefab, userid = self.userid, innate = self.innate or nil }
    end
end

function Brood:OnLoad(data)
    if data ~= nil and data.prefab ~= nil and Workshops.BROOD_BY_PREFAB[data.prefab] ~= nil then
        self.prefab = data.prefab
        self.userid = data.userid
        self.innate = data.innate == true
    end
end

function Brood:GetDebugString()
    return string.format("brood: %s, by: %s, innate: %s, active: %s",
        tostring(self.prefab), tostring(self.userid), tostring(self.innate), tostring(self:GetActivePrefab()))
end

return Brood
