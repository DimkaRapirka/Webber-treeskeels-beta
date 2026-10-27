-- The official leader emits startfollowing / stopfollowing on the follower, not on the player.
-- Listen through the follower component so no leader hooks or SetLeader wrappers are needed.

local _G = GLOBAL
local Affinity = require("spiderkingdom/affinity/affinity")
local SpiderAffinity = require("spiderkingdom/spiders/affinity")

local function OnStartFollowing(inst, data)
    local leader = data ~= nil and data.leader or nil
    if leader ~= nil then
        Affinity.Lunar.OnFollowerAdded(leader, inst)
        Affinity.Shadow.OnFollowerAdded(leader, inst)
    end
end

local function OnStopFollowing(inst, data)
    local leader = data ~= nil and data.leader or nil
    if leader ~= nil then
        Affinity.Lunar.OnFollowerRemoved(leader, inst)
        Affinity.Shadow.OnFollowerRemoved(leader, inst)
        SpiderAffinity.OnStopFollowing(inst, leader)
    end
end

AddComponentPostInit("follower", function(self)
    if not _G.TheWorld.ismastersim then
        return
    end

    -- Tags are checked when the event arrives: modded spiders work too, even if their tags are
    -- added after the follower component. These listeners never change unrelated followers.
    self.inst:ListenForEvent("startfollowing", OnStartFollowing)
    self.inst:ListenForEvent("stopfollowing", OnStopFollowing)
    -- 5.6 Shadow feast (spiders/affinity.lua): checks leader and skill when a kill happens.
    self.inst:ListenForEvent("killed", SpiderAffinity.OnKilled)
end)
