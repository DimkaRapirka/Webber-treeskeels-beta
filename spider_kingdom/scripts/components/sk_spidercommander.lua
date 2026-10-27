-- sk_spidercommander (server only, on Webber): the current command stance for all his spiders.
-- Saved with the player; re-applied to every spider that starts following him (also after load and
-- migration, through the leader's follower callbacks) and enforced once per second.

local Stances = require("spiderkingdom/spiders/stances")

local TICK = 1

local ASSIST_MUST_TAGS = { "_combat", "_health" }
local ASSIST_CANT_TAGS = { "INLIMBO", "player", "companion", "wall", "structure", "playerghost", "notarget", "noattack" }
local ASSIST_ONEOF_TAGS = { "hostile", "monster" }

local function IsCommandable(follower)
    return follower:HasTag("spider") and not follower:HasTag("spiderqueen") and not follower:HasTag("sk_worker")
        and not follower:HasTag("sk_guardian") -- a borrowed T4 bodyguard keeps its owner's orders
        and not follower:HasTag("sk_mount") -- M1 Spider Steed: its own brain, no stances
end

local Commander = Class(function(self, inst)
    self.inst = inst
    self.stance = "follow"
    self.task = inst:DoPeriodicTask(TICK, function() self:Tick() end, math.random() * TICK)
end)

function Commander:GetStance()
    return self.stance
end

function Commander:ForEachSpider(fn)
    local leader = self.inst.components.leader
    if leader == nil then
        return
    end
    for follower in pairs(leader.followers) do
        if follower:IsValid() and IsCommandable(follower) then
            fn(follower)
        end
    end
end

-- immediate_anchor: a fresh order (Stay holds the current spot); false when restoring from a save.
function Commander:SetStance(stance, immediate_anchor)
    if not Stances.IsValid(stance) then
        return false
    end
    self.stance = stance
    self:ForEachSpider(function(spider) Stances.SetStance(spider, stance, immediate_anchor) end)
    return true
end

function Commander:CycleStance()
    self:SetStance(Stances.Next(self.stance), true)
    return self.stance
end

-- A new recruit under Stay holds where it was recruited; a spider restored by sk_spiderkeeper
-- (flag set around its OnLoad) takes its anchor lazily, after a possible move to the portal.
function Commander:OnFollowerAdded(follower)
    if IsCommandable(follower) then
        Stances.SetStance(follower, self.stance, not self.inst._sk_restoring_followers)
    end
end

function Commander:OnFollowerRemoved(follower)
    if follower:IsValid() then
        Stances.Clear(follower)
    end
end

-- "attack": a spider without a target goes for the nearest hostile creature around Webber.
local function AssistAttack(self, spider)
    local combat = spider.components.combat
    if combat == nil or combat:HasTarget() or Stances.IsCouriering(spider) or Stances.IsRecalled(spider) then
        return
    end
    local target = FindEntity(self.inst, TUNING.SPIDERKINGDOM.COMMAND_ATTACK_RADIUS, function(guy)
        return combat:CanTarget(guy) and not combat:IsAlly(guy)
            and not (guy.components.health ~= nil and guy.components.health:IsDead())
    end, ASSIST_MUST_TAGS, ASSIST_CANT_TAGS, ASSIST_ONEOF_TAGS)
    if target ~= nil then
        combat:SetTarget(target)
    end
end

function Commander:Tick()
    if self.inst.components.health ~= nil and self.inst.components.health:IsDead() then
        return
    end
    self:ForEachSpider(function(spider)
        -- SetStance is idempotent: it only resets state when the stance really changes.
        Stances.SetStance(spider, self.stance)
        if self.stance == "attack" then
            AssistAttack(self, spider)
        end
    end)
end

function Commander:OnSave()
    if self.stance ~= "follow" then
        return { stance = self.stance }
    end
end

-- Components load in pairs() order: sk_spiderkeeper may already have restored the spiders, so
-- push the saved stance to them now (anchors are taken lazily after a possible portal move).
function Commander:OnLoad(data)
    if data ~= nil and Stances.IsValid(data.stance) then
        self:SetStance(data.stance, false)
    end
end

function Commander:OnRemoveFromEntity()
    if self.task ~= nil then
        self.task:Cancel()
        self.task = nil
    end
end

function Commander:GetDebugString()
    return "stance: "..tostring(self.stance)
end

return Commander
