-- R1 Royal Audience: Webber with the skill can trade with a wild Spider Queen.
-- The official spiderqueen has no trader component (prefabs/spiderqueen.lua), so we add the official one.
-- The "trader" tag is set by the component on the server and replicates to clients,
-- which is all the client needs to offer ACTIONS.GIVE (componentactions.lua, tradable).

local _G = GLOBAL
local SKUtil = require("spiderkingdom/util")
local TRADES = require("spiderkingdom/data/royal_trades")

local SKILL = "webber_sk_royal_audience"

local function GetTrade(item)
    return item ~= nil and TRADES[item.prefab] or nil
end

-- Physical ability to trade (trader:AbleToAccept). Mirrors the official default checks,
-- plus "not while fighting".
local function AbleToAcceptTest(inst, item, giver)
    if inst.components.health:IsDead() then
        return false, "DEAD"
    elseif inst.components.sleeper ~= nil and inst.components.sleeper:IsAsleep() then
        return false, "SLEEPING"
    elseif inst.sg:HasStateTag("busy") or inst.components.combat:HasTarget() then
        return false, "BUSY"
    end
    return true
end

-- Desire to trade (trader:WantsToAccept). A refusal triggers OnRefuse and keeps the item.
local function AcceptTest(inst, item, giver)
    if not SKUtil.HasSkill(giver, SKILL) then
        return false
    end
    local trade = GetTrade(item)
    if trade == nil then
        return false
    end
    if trade.cooldown ~= nil and inst.components.timer:TimerExists(trade.cooldown) then
        return false
    end
    return true
end

local function SpawnFollower(inst, giver, prefab)
    local creature = _G.SpawnPrefab(prefab)
    if creature == nil then
        return
    end

    local x, y, z = inst.Transform:GetWorldPosition()
    local offset = _G.FindWalkableOffset(inst:GetPosition(), math.random() * _G.TWOPI, TUNING.SPIDERKINGDOM.ROYAL_SPAWN_RADIUS, 8, true, false)
    if offset ~= nil then
        x, z = x + offset.x, z + offset.z
    end
    creature.Transform:SetPosition(x, 0, z)

    if giver.components.leader ~= nil then
        giver.components.leader:AddFollower(creature)
    end
    if creature.sg ~= nil and creature.sg:HasState("taunt") then
        creature.sg:GoToState("taunt")
    end
end

local function OnAccept(inst, giver, item)
    local trade = GetTrade(item)
    if trade == nil then
        return
    end

    if trade.loot ~= nil then
        for i = 1, trade.count or 1 do
            inst.components.lootdropper:SpawnLootPrefab(trade.loot)
        end
    end

    if trade.follower ~= nil then
        SpawnFollower(inst, giver, trade.follower)
    end

    if trade.cooldown ~= nil then
        inst.components.timer:StartTimer(trade.cooldown, TUNING.SPIDERKINGDOM.ROYAL_EGGSACK_COOLDOWN)
    end

    if giver ~= nil then
        inst:ForceFacePoint(giver.Transform:GetWorldPosition())
    end
    if not inst.sg:HasStateTag("busy") then
        inst.sg:GoToState("taunt")
    end

    SKUtil.Log("Royal Audience:", giver, "gave", item.prefab, "to", inst)
end

local function OnRefuse(inst, giver, item)
    if giver ~= nil then
        inst:ForceFacePoint(giver.Transform:GetWorldPosition())
    end
    if not inst.sg:HasStateTag("busy") then
        inst.sg:GoToState("taunt")
    end
end

AddPrefabPostInit("spiderqueen", function(inst)
    if not _G.TheWorld.ismastersim then
        return
    end

    if inst.components.trader ~= nil then
        -- Another mod already made the queen a trader (e.g. Treats for Webber). Do not stack a second system.
        print("[SpiderKingdom] spiderqueen already has a trader component; Royal Audience is disabled for compatibility.")
        return
    end

    if inst.components.timer == nil then
        inst:AddComponent("timer")
    end

    inst:AddComponent("trader")
    inst.components.trader:SetAbleToAcceptTest(AbleToAcceptTest)
    inst.components.trader:SetAcceptTest(AcceptTest)
    inst.components.trader:SetOnAccept(OnAccept)
    inst.components.trader:SetOnRefuse(OnRefuse)
end)
