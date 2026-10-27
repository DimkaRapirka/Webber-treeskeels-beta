-- M4 Faithful Mount (skill webber_sk_rider_faithful): the Spider Steed's saddlebag (4 slots, owner only),
-- out-of-combat regeneration and +10% speed. The rules live in components/sk_spidermount.lua; this file
-- holds what clients need too:
--
--   * containers.params.sk_spider_mount: the widget, needed on both sides (container_replica WidgetSetup).
--     The container is on every steed (prefabs/sk_spider_mount.lua); it opens with the stock RUMMAGE
--     (left click), never while riding (componentactions.lua "container").
--   * Owner only: the server sets container.restrictedtag (stock RUMMAGE fails with RESTRICTED,
--     actions.lua); the SCENE collector below also hides RUMMAGE from everyone but the steed's leader.
--     This is the mod's only SCENE "container" collector (one per mod and component).
--   * No irreplaceable items: they would leave the shard with the steed's save record, like items in a
--     player's inventory, which the stock OnDespawn drops instead (player_common.lua).
--   * No items that own creatures or react to their owner leaving (Beefalo Bell, Lavae Tooth...): the stock
--     inventory forwards "player_despawn" to them and registers their pets for migration
--     (components/inventory.lua), a steed's bag does neither. A bell saved in the bag while its beefalo
--     stays in the world would duplicate the beefalo on every reconnect. Checked on the server (components;
--     the client only predicts the move).

local _G = GLOBAL
local MountCommon = require("spiderkingdom/mounts/mount_common")

local containers = require("containers")

local params =
{
    widget =
    {
        slotpos =
        {
            _G.Vector3(-37.5, 32 + 4, 0),
            _G.Vector3(37.5, 32 + 4, 0),
            _G.Vector3(-37.5, -(32 + 4), 0),
            _G.Vector3(37.5, -(32 + 4), 0),
        },
        animbank = "ui_chest_2x2",
        animbuild = "ui_chest_2x2",
        pos = _G.Vector3(200, 0, 0),
        side_align_tip = 120,
    },
    type = "chest",
}

local function OwnsCreaturesOrListensForDespawn(item)
    return item.components.leader ~= nil
        or item.components.petleash ~= nil
        or item.components.migrationpetowner ~= nil
        or (item.event_listeners ~= nil and item.event_listeners["player_despawn"] ~= nil)
end

function params.itemtestfn(container, item, slot)
    if item:HasTag("irreplaceable") then
        return false
    end
    return not (_G.TheWorld.ismastersim and OwnsCreaturesOrListensForDespawn(item))
end

containers.params[MountCommon.MOUNT_PREFAB] = params

-- Client collector: RUMMAGE only for the steed's leader ---------------------------------------------

local function RemoveAction(actions, action)
    for i = #actions, 1, -1 do
        if actions[i] == action then
            table.remove(actions, i)
        end
    end
end

AddComponentAction("SCENE", "container", function(inst, doer, actions, right)
    if inst:HasTag(MountCommon.MOUNT_TAG) then
        local follower = inst.replica.follower
        if follower == nil or follower:GetLeader() ~= doer then
            RemoveAction(actions, _G.ACTIONS.RUMMAGE)
        end
    end
end)
