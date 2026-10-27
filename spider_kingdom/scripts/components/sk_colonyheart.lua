-- sk_colonyheart (server only): K6 Colony Heart. Holds the owner and the network's pause switch.
-- The network itself is not stored: colony/network.lua computes it on demand (owner's dens within
-- HEART_RADIUS), so links never go stale and nothing has to be rebuilt after a load. The heart links
-- only while its owner is online with K6 (tag "sk_heartlink", colony/ownership.lua) and it is not burnt
-- or burning; otherwise every den falls back to its local K4 radius. Removing the heart never touches dens.
--
-- API: GetOwner(), IsOwner(player), SetOwner(userid), IsLinked(), IsPaused(), SetPaused(bool),
--      TogglePaused() -> bool. Event on the heart: "sk_heartchanged" (visuals).

local Network = require("spiderkingdom/colony/network")
local Ownership = require("spiderkingdom/colony/ownership")

local function OnHeartRemoved(inst)
    local self = inst.components.sk_colonyheart
    if self ~= nil then
        self:Unregister()
    end
end

local ColonyHeart = Class(function(self, inst)
    self.inst = inst
    self.owner = nil  -- builder userid
    self.paused = false

    inst:ListenForEvent("onremove", OnHeartRemoved)
end)

function ColonyHeart:Unregister()
    Network.UnregisterHeart(self.inst, self.owner)
    Ownership.Unregister(self.inst, self.owner)
end

function ColonyHeart:OnRemoveFromEntity()
    self.inst:RemoveEventCallback("onremove", OnHeartRemoved)
    self:Unregister()
    self.inst:RemoveTag(Network.LINK_TAG)
    self.inst:RemoveTag(Network.PAUSED_TAG)
end

-- Owner ------------------------------------------------------------------------------------------

function ColonyHeart:GetOwner()
    return self.owner
end

-- A heart without an owner (e.g. spawned from the console) is taken by the first Webber who uses it.
function ColonyHeart:IsOwner(player)
    return self.owner == nil or (player ~= nil and player.userid == self.owner)
end

function ColonyHeart:SetOwner(userid)
    if self.owner ~= nil and self.owner ~= userid then
        self:Unregister()
        self.inst:RemoveTag(Network.LINK_TAG)
    end
    self.owner = userid
    if userid ~= nil then
        Network.RegisterHeart(self.inst, userid)
        -- Only the link tag: the den tags (cozy, workforce, logistics) mean nothing on the heart.
        Ownership.Register(self.inst, userid, { [Network.LINK_TAG] = true })
    end
end

-- Called by EntityScript:OnBuilt when the recipe places the heart.
function ColonyHeart:OnBuilt(builder)
    if builder ~= nil and builder.userid ~= nil then
        self:SetOwner(builder.userid)
    end
end

function ColonyHeart:IsLinked()
    return Network.IsHeartLinked(self.inst)
end

-- Pause switch -------------------------------------------------------------------------------------

function ColonyHeart:IsPaused()
    return self.paused
end

function ColonyHeart:SetPaused(paused)
    self.paused = paused == true
    if self.paused then
        self.inst:AddTag(Network.PAUSED_TAG)
    else
        self.inst:RemoveTag(Network.PAUSED_TAG)
    end
    self.inst:PushEvent("sk_heartchanged")
end

function ColonyHeart:TogglePaused()
    self:SetPaused(not self.paused)
    return self.paused
end

-- Save ---------------------------------------------------------------------------------------------

function ColonyHeart:OnSave()
    if self.owner ~= nil or self.paused then
        return { owner = self.owner, paused = self.paused or nil }
    end
end

function ColonyHeart:OnLoad(data)
    if data ~= nil then
        if data.owner ~= nil then
            self:SetOwner(data.owner)
        end
        self:SetPaused(data.paused)
    end
end

function ColonyHeart:GetDebugString()
    return string.format("owner: %s, linked: %s, paused: %s",
        tostring(self.owner), tostring(self:IsLinked()), tostring(self.paused))
end

return ColonyHeart
