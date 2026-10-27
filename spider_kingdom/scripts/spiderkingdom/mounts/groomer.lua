-- M1 Spider Groomer (skill webber_sk_rider_groomer):
--   1. give meat-type food to one of your Spider Warriors (stock GIVE): every meal counts
--      (components/sk_grooming.lua); after MOUNT_FEED_NEEDED meals and MOUNT_MIN_DAYS days since the first
--      one it grows into a Spider Steed (prefabs/sk_spider_mount.lua);
--   2. right click the steed: the stock MOUNT action. Only its owner, and only with the skill
--      (components/sk_spidermount.lua). The stock rider dismounts it with the stock DISMOUNT action.
--
-- Client: the stock MOUNT collector (componentactions.lua "rideable") offers MOUNT to anyone on a "rideable"
-- target; the SCENE collector below takes it away again on a steed that is not the doer's. Mod collectors
-- run after the vanilla ones (EntityScript:CollectActions). This is the mod's only SCENE "rideable" collector.

local _G = GLOBAL
local MountCommon = require("spiderkingdom/mounts/mount_common")

-- Spider Warriors: grooming progress + meal counting (server) ---------------------------------------

AddPrefabPostInit(MountCommon.GROOM_PREFAB, function(inst)
    if not _G.TheWorld.ismastersim then
        return
    end

    inst:AddComponent("sk_grooming")

    -- Chained after the stock trader.onaccept (prefabs/spider.lua OnGetItemFromPlayer: eat + befriend).
    -- The food is judged before the stock code eats (removes) it.
    local trader = inst.components.trader
    if trader ~= nil then
        local old_onaccept = trader.onaccept
        trader.onaccept = function(inst, giver, item, ...)
            local is_meal = MountCommon.IsGroomingFood(item)
            if old_onaccept ~= nil then
                old_onaccept(inst, giver, item, ...)
            end
            if is_meal and inst:IsValid() and inst.components.sk_grooming ~= nil then
                inst.components.sk_grooming:OnFed(giver)
            end
        end
    end
end)

-- Client collector: no MOUNT on someone else's steed --------------------------------------------

local function RemoveAction(actions, action)
    for i = #actions, 1, -1 do
        if actions[i] == action then
            table.remove(actions, i)
        end
    end
end

AddComponentAction("SCENE", "rideable", function(inst, doer, actions, right)
    if inst:HasTag(MountCommon.MOUNT_TAG) and not MountCommon.CanOfferMount(inst, doer) then
        RemoveAction(actions, _G.ACTIONS.MOUNT)
    end
end)
