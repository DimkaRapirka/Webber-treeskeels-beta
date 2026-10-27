-- T1 We Don't Bite: shared logic (server). Plain module: require("spiderkingdom/spiders/nobite_common").
-- Used by the spider post-inits (spiders/nobite.lua) and by the skill handlers.

local NoBite = {}

local function GetNoBiteLeader(spider)
    local follower = spider.components.follower
    local leader = follower ~= nil and follower:GetLeader() or nil
    return leader ~= nil and leader:HasTag("sk_nobite") and leader or nil
end
NoBite.GetNoBiteLeader = GetNoBiteLeader

local function IsProvoking(leader, target)
    local provokers = leader._sk_provokers
    local expires = provokers ~= nil and provokers[target] or nil
    return expires ~= nil and expires > GetTime()
end

local function IsFriendOfPlayers(target)
    if target:HasTag("player") or target:HasTag("companion") then
        return true
    end
    local follower = target.components.follower
    local targetleader = follower ~= nil and follower:GetLeader() or nil
    return targetleader ~= nil and targetleader:HasTag("player")
end

-- True if this spider must not fight this target.
function NoBite.IsProtected(spider, target)
    if target == nil or not target:IsValid() then
        return false
    end
    local leader = GetNoBiteLeader(spider)
    if leader == nil or target == leader then
        return false
    end
    return IsFriendOfPlayers(target) and not IsProvoking(leader, target)
end

function NoBite.MarkProvoker(leader, attacker)
    local now = GetTime()
    local provokers = leader._sk_provokers
    if provokers == nil then
        provokers = setmetatable({}, { __mode = "k" }) -- don't keep removed entities alive
        leader._sk_provokers = provokers
    else
        for ent, expires in pairs(provokers) do
            if expires <= now then
                provokers[ent] = nil
            end
        end
    end
    provokers[attacker] = now + TUNING.SPIDERKINGDOM.NOBITE_PROVOKE_TIME
end

-- A player in PvP who is actually targeting the victim (not splash damage) provokes the pack.
function NoBite.IsDeliberatePvPAttack(attacker, victim)
    return TheNet:GetPVPEnabled()
        and attacker:HasTag("player")
        and attacker.components.combat ~= nil
        and attacker.components.combat.target == victim
end

-- Called from the spider's combat:SetTarget wrapper. Covers vanilla retaliation (spider OnAttacked),
-- ShareTarget and leader assistance (leader:OnAttacked -> SuggestTarget), which all end in SetTarget.
-- A deliberate PvP attack on the spider or on its leader registers the attacker as a provoker first.
function NoBite.ShouldIgnoreTarget(spider, target)
    if not NoBite.IsProtected(spider, target) then
        return false
    end
    local leader = GetNoBiteLeader(spider)
    if NoBite.IsDeliberatePvPAttack(target, spider) or NoBite.IsDeliberatePvPAttack(target, leader) then
        NoBite.MarkProvoker(leader, target)
        return false
    end
    return true
end

-- "attacked" on a spider or on its leader: every deliberate PvP hit (re)starts the provocation timer.
-- The SetTarget wrapper only sees the first hit, and leader assistance (SuggestTarget) skips
-- spiders that already have an enemy, so provocation is recorded here as well.
function NoBite.RecordDeliberateHit(leader, victim, attacker)
    if leader ~= nil and attacker ~= nil and attacker ~= leader and attacker:IsValid()
        and NoBite.IsDeliberatePvPAttack(attacker, victim) then
        NoBite.MarkProvoker(leader, attacker)
    end
end

local function OnLeaderAttacked(inst, data)
    NoBite.RecordDeliberateHit(inst, inst, data ~= nil and data.attacker or nil)
end

function NoBite.Enable(inst)
    NoBite.Disable(inst)
    inst:AddTag("sk_nobite")
    inst:ListenForEvent("attacked", OnLeaderAttacked)
end

function NoBite.Disable(inst)
    inst:RemoveTag("sk_nobite")
    inst:RemoveEventCallback("attacked", OnLeaderAttacked)
    inst._sk_provokers = nil
end

return NoBite
