-- Shared mechanic (no Insight cost): Webber's spiders follow him between worlds and across reconnects.
-- See components/sk_spiderkeeper.lua.

local _G = GLOBAL
local SKUtil = require("spiderkingdom/util")

-- Mods that already carry spiders across shards. Running two systems at once would duplicate spiders.
local CONFLICTING_MODS =
{
    "workshop-2529730952", -- Keep Spiders When Despawning
    "workshop-1171138081", -- Treats for Webber
    "workshop-3354479198", -- Webber Spider Sea
}

local function FindConflictingMod()
    local modindex = _G.KnownModIndex
    if modindex == nil then
        return nil
    end
    for _, modname in ipairs(CONFLICTING_MODS) do
        if modindex:IsModEnabledAny(modname) then
            return modname
        end
    end
end

local conflict = FindConflictingMod()
if conflict ~= nil then
    print("[SpiderKingdom] "..conflict.." is enabled and already moves spiders between worlds; Spider Kingdom spider transfer is disabled.")
end

AddPrefabPostInit("webber", function(inst)
    if not _G.TheWorld.ismastersim then
        return
    end

    inst:AddComponent("sk_spiderkeeper")

    if conflict ~= nil then
        -- Still restore spiders saved earlier by this component (otherwise their records would be
        -- dropped on the next save), but hand them back to vanilla following and bond nothing new.
        inst.components.sk_spiderkeeper:SetPassive(true)
        return
    end

    -- Official per-character hooks called by the player's leader (prefabs/player_common.lua,
    -- OnFollowerAdded / OnFollowerRemoved). Chain whatever was set before us.
    local old_added = inst.additional_OnFollowerAdded
    local old_removed = inst.additional_OnFollowerRemoved

    inst.additional_OnFollowerAdded = function(inst, follower)
        if old_added ~= nil then
            old_added(inst, follower)
        end
        inst.components.sk_spiderkeeper:OnFollowerAdded(follower)
    end

    inst.additional_OnFollowerRemoved = function(inst, follower)
        if old_removed ~= nil then
            old_removed(inst, follower)
        end
        inst.components.sk_spiderkeeper:OnFollowerRemoved(follower)
    end

    SKUtil.Log("sk_spiderkeeper attached to", inst)
end)
