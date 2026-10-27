-- The mod's single USEITEM collector for "inventoryitem" (MOD_COMPONENT_ACTIONS keeps one function per
-- mod, component and action type). Mod collectors run after all vanilla ones (componentactions.lua
-- CollectActions), so vanilla actions are already in the list. Client and server.
--
--   * K2 Spider Architecture: SK_SETDENROLE with a marker item on a den; a den with a role does not
--     swallow items meant for bedazzle / shave / upgrade / role change (STORE removed then).
--   * T2 Spider Mail: the Courier Kit on one of your spiders -> SK_MAKECOURIER.
--   * R2 Royal Throne: the Royal Invitation on a wild Spider Queen -> SK_ROYALINVITE.
--   * R4 Royal Expedition: the Spider Whistle on your throne -> SK_ROYALEXPEDITION (call out / send home).
--   * R3 Royal Workshop: a mutator on your living den near an open workshop -> SK_SETBROOD.
--   * T4 Shared Squad: the Spider Whistle on another player -> SK_SQUAD (lend / recall bodyguards).
--   * K6 Colony Heart: Twigs on your heart -> SK_HEARTTOGGLE (pause / resume the network's workers).
--   * Spider commands: the Spider Whistle on a den -> SK_SENDHOME, on your spider -> SK_SPIDERSTANCE.
-- The actions themselves are defined in colony/denroles.lua and couriers/mail.lua.

local _G = GLOBAL
local DenRoles = require("spiderkingdom/data/den_roles")
local MailCommon = require("spiderkingdom/couriers/mail_common")
local Thrones = require("spiderkingdom/royalty/thrones")
local Squad = require("spiderkingdom/spiders/squad_common")
local Network = require("spiderkingdom/colony/network")
local Workshops = require("spiderkingdom/royalty/workshops")
local Expeditions = require("spiderkingdom/royalty/expeditions")
local Rituals = require("spiderkingdom/affinity/rituals_common")

local function RemoveAction(actions, action)
    for i = #actions, 1, -1 do
        if actions[i] == action then
            table.remove(actions, i)
        end
    end
end

local function HasAction(actions, action)
    for _, v in ipairs(actions) do
        if v == action then
            return true
        end
    end
    return false
end

-- Den-specific item actions that must win over storing the item in a den with a role.
local DEN_ITEM_ACTIONS = { "BEDAZZLE", "SHAVE", "UPGRADE", "SK_SETDENROLE", "SK_SETBROOD" }

local function CollectDenActions(inst, doer, target, actions, right)
    -- Spider commands: the stock whistle on a den sends nearby spiders into it (spiders/commands.lua).
    if not right and inst.prefab == "spider_whistle" and doer:HasTag("spiderwhisperer") then
        table.insert(actions, _G.ACTIONS.SK_SENDHOME)
    end

    if not right
        and doer:HasTag("sk_architect")
        and DenRoles.ROLE_BY_ITEM[inst.prefab] ~= nil then
        table.insert(actions, _G.ACTIONS.SK_SETDENROLE)
    end

    -- R3 Royal Workshop: a mutator on a living den near an open workshop (royalty/workshops.lua).
    Workshops.CollectDenActions(inst, doer, target, actions, right)

    if DenRoles.GetRoleOfDen(target) ~= nil then
        for _, id in ipairs(DEN_ITEM_ACTIONS) do
            if HasAction(actions, _G.ACTIONS[id]) then
                RemoveAction(actions, _G.ACTIONS.STORE)
                break
            end
        end
    end
end

local function CollectSpiderActions(inst, doer, target, actions, right)
    local follower = target.replica.follower

    -- Spider commands: the stock whistle on one of your spiders changes the orders (spiders/commands.lua).
    if not right
        and inst.prefab == "spider_whistle"
        and doer:HasTag("spiderwhisperer")
        and not target:HasTag("sk_guardian") -- a borrowed T4 bodyguard keeps its owner's orders
        and not target:HasTag("sk_mount") -- M1 Spider Steed: its own brain, no stances
        and follower ~= nil and follower:GetLeader() == doer then
        table.insert(actions, _G.ACTIONS.SK_SPIDERSTANCE)
    end

    -- T2 Spider Mail: the Courier Kit on one of your spiders turns it into a courier (couriers/mail.lua).
    if not right
        and inst.prefab == "sk_courier_kit"
        and doer:HasTag("sk_mailer")
        and MailCommon.CanUpgrade(doer, target) then
        table.insert(actions, _G.ACTIONS.SK_MAKECOURIER)
    end
end

AddComponentAction("USEITEM", "inventoryitem", function(inst, doer, target, actions, right)
    if target:HasTag("spiderden") and target.prefab == "spiderden" and not target:HasTag("burnt") then
        CollectDenActions(inst, doer, target, actions, right)
    elseif target:HasTag("spiderqueen") then
        -- Before "spider": the queen has both tags (R2 Royal Throne, royalty/thrones.lua).
        Thrones.CollectQueenActions(inst, doer, target, actions, right)
    elseif target:HasTag("spider") then
        CollectSpiderActions(inst, doer, target, actions, right)
    elseif target:HasTag(Thrones.THRONE_TAG) then
        -- R4 Royal Expedition: the whistle on your throne calls the queen out / sends her home.
        Expeditions.CollectThroneActions(inst, doer, target, actions, right)
        Rituals.CollectThroneActions(inst, doer, target, actions, right)
    elseif target:HasTag(Network.HEART_TAG) then
        -- K6 Colony Heart: twigs pause / resume the network's workers (colony/network.lua).
        Network.CollectHeartActions(inst, doer, target, actions, right)
    elseif target:HasTag("player") then
        -- T4 Shared Squad: right click another player with the whistle (spiders/squad_common.lua).
        Squad.CollectPlayerActions(inst, doer, target, actions, right)
    end
end)
