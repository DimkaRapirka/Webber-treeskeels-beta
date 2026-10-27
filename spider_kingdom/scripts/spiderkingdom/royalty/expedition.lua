-- R4 Royal Expedition: wiring (modimport). Rules and the expedition itself: royalty/expeditions.lua.
--   * Spider Queen post-init (server): the follower replica is prepared at spawn, so the follower component
--     can be added and removed at runtime (official beeguard.lua pattern: the replica's net vars must exist
--     from construction); combat:SetTarget refuses friends while she is on an expedition;
--   * ACTIONS.SK_ROYALEXPEDITION: the Spider Whistle on your own Royal Throne calls the queen out / sends
--     her home. Client collector: Expeditions.CollectThroneActions (networking/item_actions.lua);
--   * world: when a player arrives, stale "away" marks of his thrones are cleared (royalty/thrones.lua).

local _G = GLOBAL
local SKUtil = require("spiderkingdom/util")
local Thrones = require("spiderkingdom/royalty/thrones")
local Expeditions = require("spiderkingdom/royalty/expeditions")

-- Seconds after "ms_playerjoined": his queen (restored in his OnLoad) is registered long before.
local VALIDATE_DELAY = 2

-- Spider Queen ---------------------------------------------------------------------------------

AddPrefabPostInit(Thrones.QUEEN_PREFAB, function(inst)
    if not _G.TheWorld.ismastersim then
        return
    end

    if inst.components.follower == nil then
        -- Same as prefabs/beeguard.lua: remove the tag so the replica is created below, then hidden.
        inst:RemoveTag("__follower")
        inst:PrereplicateComponent("follower")
    end

    local combat = inst.components.combat
    if combat ~= nil then
        -- Instance wrapper, only active on an expedition: covers the stock OnAttacked (SetTarget on the
        -- attacker, also when it is her Webber), ShareTarget from wild queens and leader suggestions.
        local SetTarget = combat.SetTarget
        combat.SetTarget = function(self, target, ...)
            if target ~= nil and Expeditions.BlocksTarget(self.inst, target) then
                return
            end
            return SetTarget(self, target, ...)
        end
    end
end)

-- World ----------------------------------------------------------------------------------------

AddPrefabPostInit("world", function(inst)
    if not inst.ismastersim then
        return
    end
    inst:ListenForEvent("ms_playerjoined", function(world, player)
        local userid = Thrones.GetUserId(player)
        if userid ~= nil then
            world:DoTaskInTime(VALIDATE_DELAY, function()
                Thrones.ValidateAway(userid)
            end)
        end
    end)
end)

-- Action ---------------------------------------------------------------------------------------

local SK_ROYALEXPEDITION = _G.Action({ priority = 1, mount_valid = true })
SK_ROYALEXPEDITION.id = "SK_ROYALEXPEDITION"
SK_ROYALEXPEDITION.str = _G.STRINGS.ACTIONS.SK_ROYALEXPEDITION
SK_ROYALEXPEDITION.strfn = function(act)
    return act.target ~= nil and act.target:HasTag(Thrones.OCCUPIED_TAG) and "CALL" or "HOME"
end
SK_ROYALEXPEDITION.fn = function(act)
    local doer, throne, item = act.doer, act.target, act.invobject
    if doer == nil or throne == nil or item == nil or item.prefab ~= Expeditions.WHISTLE_PREFAB
        or throne.components.sk_royalthrone == nil
        or not SKUtil.HasSkill(doer, Expeditions.SKILL) then
        return false
    end
    if not throne.components.sk_royalthrone:IsOwner(doer) then
        return false, "NOTOWNER"
    end
    if not Thrones.IsUsable(throne) then
        return false, "BUSY"
    end
    return Expeditions.UseThrone(doer, throne)
end
AddAction(SK_ROYALEXPEDITION)

-- Client collector: Expeditions.CollectThroneActions, called from networking/item_actions.lua.

AddStategraphActionHandler("wilson", _G.ActionHandler(_G.ACTIONS.SK_ROYALEXPEDITION, "give"))
AddStategraphActionHandler("wilson_client", _G.ActionHandler(_G.ACTIONS.SK_ROYALEXPEDITION, "give"))
