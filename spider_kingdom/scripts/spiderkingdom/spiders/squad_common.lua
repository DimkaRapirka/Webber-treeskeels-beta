-- T4 Shared Squad: shared logic. Plain module: require("spiderkingdom/spiders/squad_common").
-- Used by spiders/squad.lua (actions, post-inits), components/sk_guardian.lua, components/sk_squadstore.lua,
-- the skill handlers (Enable / Disable) and the client collector in networking/item_actions.lua.
--
-- Client and server: CollectPlayerActions, HasGuardiansOn, GetOwnerId.
-- Server only: the registry of lent spiders, Lend, Recall, CountLent, Enable, Disable.

local Stances = require("spiderkingdom/spiders/stances")

local Squad = {}

Squad.SKILL = "webber_sk_symbiosis_squad"
Squad.LEADER_TAG = "sk_squadleader" -- on Webber, set by the skill (the client offers the action)
Squad.GUARDIAN_TAG = "sk_guardian"  -- on a lent spider (set by sk_guardian)
Squad.NOKEEPER_TAG = "sk_nokeeper"  -- no player's sk_spiderkeeper bonds a lent spider

-- Client label only: how far around the guarded player we look for the doer's guardians.
local LABEL_RADIUS = 30

local GUARDIAN_MUST_TAGS = { Squad.GUARDIAN_TAG }
local GUARDIAN_CANT_TAGS = { "INLIMBO" }

function Squad.FindPlayer(userid)
    if userid == nil then
        return nil
    end
    for _, player in ipairs(AllPlayers) do
        if player.userid == userid then
            return player
        end
    end
end

-- Server: a player who can take spiders back right now (on this shard, alive, not leaving).
function Squad.IsAvailable(player)
    return player ~= nil
        and player:IsValid()
        and not player._sk_despawning
        and not (player.components.sk_spiderkeeper ~= nil and player.components.sk_spiderkeeper.despawning)
        and player.components.leader ~= nil
        and not player:HasTag("playerghost")
        and not (player.components.health ~= nil and player.components.health:IsDead())
end

-- Owner userid of a lent spider (networked, so it also works on clients). nil if it is not lent.
function Squad.GetOwnerId(spider)
    local net = spider._sk_guardowner
    local userid = net ~= nil and net:value() or nil
    return userid ~= "" and userid or nil
end

-- Client and server: does doer have spiders guarding target? (only used for the action label)
function Squad.HasGuardiansOn(doer, target)
    if doer == nil or target == nil or doer.userid == nil or doer.userid == "" then
        return false
    end
    local x, y, z = target.Transform:GetWorldPosition()
    for _, spider in ipairs(TheSim:FindEntities(x, y, z, LABEL_RADIUS, GUARDIAN_MUST_TAGS, GUARDIAN_CANT_TAGS)) do
        local follower = spider.replica.follower
        if follower ~= nil and follower:GetLeader() == target and Squad.GetOwnerId(spider) == doer.userid then
            return true
        end
    end
    return false
end

-- Client collector branch for USEITEM "inventoryitem" on a player (called from networking/item_actions.lua).
-- Right click: left click with an item on a player is the stock "Give".
function Squad.CollectPlayerActions(inst, doer, target, actions, right)
    if right
        and inst.prefab == "spider_whistle"
        and target ~= doer
        and doer:HasTag(Squad.LEADER_TAG)
        and not target:HasTag("playerghost") then
        table.insert(actions, ACTIONS.SK_SQUAD)
    end
end

-- Registry of lent spiders (server) ------------------------------------------------------------

local guardians = setmetatable({}, { __mode = "k" })

function Squad.Register(spider)
    guardians[spider] = true
end

function Squad.Unregister(spider)
    guardians[spider] = nil
end

-- fn(spider, guardian) for every live lent spider. Iterates a copy: fn may end the loan.
function Squad.ForEachGuardian(fn)
    local list = {}
    for spider in pairs(guardians) do
        table.insert(list, spider)
    end
    for _, spider in ipairs(list) do
        local guardian = spider:IsValid() and spider.components.sk_guardian or nil
        if guardian ~= nil and guardian:IsGuarding() then
            fn(spider, guardian)
        end
    end
end

-- guarded: optional player entity; nil counts every loan of this owner.
function Squad.CountLent(owner, guarded)
    local count = 0
    Squad.ForEachGuardian(function(spider, guardian)
        if guardian.owner == owner.userid and (guarded == nil or guardian.guarded == guarded.userid) then
            count = count + 1
        end
    end)
    return count
end

-- A trap that already picked this spider springs without re-checking "untrappable"
-- (components/trap.lua DoSpring), so such a spider is not lendable.
local TRAP_TAGS = { "trap" }
local function IsTrapTarget(spider)
    local x, y, z = spider.Transform:GetWorldPosition()
    for _, trap in ipairs(TheSim:FindEntities(x, 0, z, 2, TRAP_TAGS)) do
        if trap.components.trap ~= nil and trap.components.trap.target == spider then
            return true
        end
    end
    return false
end

local function IsLendable(spider, owner)
    local follower = spider.components.follower
    return spider:IsValid()
        and spider.components.sk_guardian ~= nil
        and follower ~= nil and follower:GetLeader() == owner
        and spider:HasTag("spider")
        and not spider:HasTag("spiderqueen")
        and not spider:HasTag("sk_worker")
        and not spider:HasTag(Squad.GUARDIAN_TAG)
        and not Stances.IsCouriering(spider)
        and spider.mutation_target == nil -- spidermutator in progress (SGspider "mutate")
        and not (spider.sg ~= nil and spider.sg:HasStateTag("mutating"))
        and not (spider.components.health ~= nil and spider.components.health:IsDead())
        and not (spider.components.inventoryitem ~= nil and spider.components.inventoryitem:IsHeld())
        and not IsTrapTarget(spider)
end

-- Lends up to the free amount of the owner's nearest idle spiders to target.
-- Returns the number lent, or nil when the owner already lent the maximum.
function Squad.Lend(owner, target)
    local free = TUNING.SPIDERKINGDOM.SQUAD_MAX_GUARDS - Squad.CountLent(owner)
    if free <= 0 then
        return nil
    end

    local radius_sq = TUNING.SPIDERKINGDOM.SQUAD_LEND_RADIUS * TUNING.SPIDERKINGDOM.SQUAD_LEND_RADIUS
    local candidates = {}
    for spider in pairs(owner.components.leader.followers) do
        if IsLendable(spider, owner) and spider:GetDistanceSqToInst(owner) <= radius_sq then
            table.insert(candidates, spider)
        end
    end
    table.sort(candidates, function(a, b) return a:GetDistanceSqToInst(owner) < b:GetDistanceSqToInst(owner) end)

    -- Start changes the owner's follower list: act on the collected list only.
    local lent = 0
    for i = 1, math.min(free, #candidates) do
        if candidates[i].components.sk_guardian:Start(owner, target) then
            lent = lent + 1
        end
    end
    return lent
end

-- Sends the owner's lent spiders back to him (all of them, or only those guarding `guarded`).
function Squad.Recall(owner, guarded)
    local count = 0
    Squad.ForEachGuardian(function(spider, guardian)
        if guardian.owner == owner.userid and (guarded == nil or guardian.guarded == guarded.userid) then
            guardian:ReturnToOwner()
            count = count + 1
        end
    end)
    return count
end

-- Skill handlers (skilltree/handlers.lua, Wrap) ------------------------------------------------

function Squad.Enable(inst)
    inst:AddTag(Squad.LEADER_TAG)
end

-- Respec: the bodyguards come back.
function Squad.Disable(inst)
    inst:RemoveTag(Squad.LEADER_TAG)
    if inst.userid ~= nil and inst.userid ~= "" then
        Squad.Recall(inst)
    end
end

return Squad
