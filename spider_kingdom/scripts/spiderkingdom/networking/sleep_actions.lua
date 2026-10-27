-- The mod's single SCENE collector for "sleepingbag" (MOD_COMPONENT_ACTIONS keeps one function per
-- mod, component and action type). Mod collectors run after the vanilla ones (componentactions.lua
-- CollectActions), so the vanilla SLEEPIN decision is already in the list. Client and server.
--
--   * T3 Cozy Place: vanilla only lets spiderwhisperers sleep in a "spiderden"; dens tagged "sk_cozy"
--     (owner online with the skill) accept every player. The server ACTIONS.SLEEPIN.fn has no
--     such check (actions.lua), so nothing else is needed.
--   * K5 Portable Home: the portable cocoon is Webber-only unless it is "sk_cozy".
--   * K2 Spider Architecture: on a den with a role, left click opens it (RUMMAGE, priority -1) and
--     right click sleeps; otherwise SLEEPIN (priority 0) would always win.

local _G = GLOBAL
local DenRoles = require("spiderkingdom/data/den_roles")
local Ownership = require("spiderkingdom/colony/ownership")

-- Server-side re-check at sleep time (see Ownership.WrapIsNearDanger).
AddPlayerPostInit(function(inst)
    if _G.TheWorld.ismastersim then
        Ownership.WrapIsNearDanger(inst)
    end
end)

-- The "tent" state commits sleep 6 frames after entering (ontimeout -> PerformBufferedAction, then
-- hides the player). Re-check the permission there and leave through the stock failure cleanup.
AddStategraphPostInit("wilson", function(sg)
    local tent = sg.states.tent
    if tent == nil or tent.ontimeout == nil then
        return
    end
    local ontimeout = tent.ontimeout
    tent.ontimeout = function(inst, ...)
        local act = inst:GetBufferedAction()
        if act ~= nil and Ownership.IsSleepForbidden(inst, act.target) then
            inst:PushEvent("performaction", { action = inst.bufferedaction })
            inst:ClearBufferedAction()
            inst.AnimState:PlayAnimation("pickup_pst")
            inst.sg:GoToState("idle", true)
            return
        end
        return ontimeout(inst, ...)
    end
end)

local function HasAction(actions, action)
    for _, v in ipairs(actions) do
        if v == action then
            return true
        end
    end
    return false
end

local function RemoveAction(actions, action)
    for i = #actions, 1, -1 do
        if actions[i] == action then
            table.remove(actions, i)
        end
    end
end

-- Same base conditions as the vanilla collector.
local function CanUseBag(inst, doer)
    return doer:HasTag("player") and not doer:HasTag("insomniac") and not inst:HasTag("hassleeper")
end

AddComponentAction("SCENE", "sleepingbag", function(inst, doer, actions, right)
    local SLEEPIN = _G.ACTIONS.SLEEPIN
    local cozy = inst:HasTag("sk_cozy")
    local webber = doer:HasTag("spiderwhisperer")

    if cozy and not webber and inst:HasTag("spiderden") and CanUseBag(inst, doer) and not HasAction(actions, SLEEPIN) then
        table.insert(actions, SLEEPIN)
    end

    if inst:HasTag("sk_portablecocoon") and not webber and not cozy then
        RemoveAction(actions, SLEEPIN)
    end

    if not right and inst:HasTag("spiderden") and DenRoles.GetRoleOfDen(inst) ~= nil and HasAction(actions, _G.ACTIONS.RUMMAGE) then
        RemoveAction(actions, SLEEPIN)
    end
end)
