-- R2 Royal Throne: shared rules. Plain module: require("spiderkingdom/royalty/thrones").
--   * per-shard registry owner userid -> thrones (server). Thrones register themselves when built and
--     when loaded with the world, so it is complete before any player can craft or invite;
--   * "one throne per player" (recipe canbuild) and "one queen per player" (invitation) checks;
--   * the client collector branch for the Royal Invitation used on a wild Spider Queen, called from
--     networking/item_actions.lua (one USEITEM "inventoryitem" collector per mod).
-- The throne itself is components/sk_royalthrone.lua; the action is royalty/throne.lua.
-- R3 Royal Workshop (throne as SPIDERCRAFT prototyper, brood choice) lives in royalty/workshops.lua.
-- R4 Royal Expedition (royalty/expeditions.lua) adds here, because sk_royalthrone and the invitation need it:
--   * the per-shard registry userid -> the queen out with that Webber right now (at most one);
--   * the "away" rule of a throne whose queen is out (IsAwayStale / ValidateAway);
--   * expedition queens are never calm for an invitation and never offered SK_ROYALINVITE.
-- Affinity rituals (affinity/rituals_common.lua) add the networked owner id of a throne (GetOwnerId).

local Thrones = {}

Thrones.SKILL = "webber_sk_royal_throne"
Thrones.THRONE_PREFAB = "sk_royal_throne"
Thrones.INVITATION_PREFAB = "sk_royal_invitation"
Thrones.QUEEN_PREFAB = "spiderqueen"

Thrones.MONARCH_TAG = "sk_monarch"            -- player with R2 (skilltree/handlers.lua); client hint only
Thrones.THRONE_TAG = "sk_royalthrone"         -- the throne structure
Thrones.OCCUPIED_TAG = "sk_throne_occupied"   -- throne with a queen inside (name, client)
Thrones.INVITATION_TAG = "sk_royalinvitation" -- the Royal Invitation item
Thrones.INVITED_TAG = "sk_royalinvited"       -- queen walking to a throne right now
Thrones.EXPEDITION_TAG = "sk_queenexpedition" -- R4: queen out with her Webber (client: no invitation)
Thrones.AWAY_TAG = "sk_throne_away"           -- R4: throne whose queen is out with the owner (client)

-- Affinity rituals (affinity/rituals_common.lua): the owner's userid as a net_string on the throne
-- (prefabs/sk_royal_throne.lua, set by sk_royalthrone:SetOwner), so a client can tell whose throne it is.
Thrones.OWNER_NETVAR = "sk_royal_throne._sk_owner"

-- Client and server: the throne owner's userid, or nil.
function Thrones.GetOwnerId(throne)
    local net = throne ~= nil and throne._sk_owner or nil
    local userid = net ~= nil and net:value() or nil
    return userid ~= nil and userid ~= "" and userid or nil
end

local registry = {} -- [userid] = weak set of thrones

function Thrones.Register(throne, userid)
    if userid == nil then
        return
    end
    local set = registry[userid]
    if set == nil then
        set = setmetatable({}, { __mode = "k" })
        registry[userid] = set
    end
    set[throne] = true
end

function Thrones.Unregister(throne, userid)
    local set = userid ~= nil and registry[userid] or nil
    if set ~= nil then
        set[throne] = nil
    end
end

local function IsLive(throne)
    return throne:IsValid() and throne.components.sk_royalthrone ~= nil
end

-- A throne that can hold a queen: not burnt, not burning.
function Thrones.IsUsable(throne)
    return throne ~= nil and IsLive(throne)
        and not throne:HasTag("burnt")
        and not (throne.components.burnable ~= nil and throne.components.burnable:IsBurning())
end

-- Usable thrones of this player on this shard (burnt ones do not count and may be rebuilt).
function Thrones.GetThrones(userid)
    local result = {}
    local set = userid ~= nil and registry[userid] or nil
    if set ~= nil then
        for throne in pairs(set) do
            if Thrones.IsUsable(throne) then
                table.insert(result, throne)
            end
        end
    end
    return result
end

-- Every live throne of this player on this shard, usable or not (R3 uses it to close workshops).
function Thrones.GetAllThrones(userid)
    local result = {}
    local set = userid ~= nil and registry[userid] or nil
    if set ~= nil then
        for throne in pairs(set) do
            if IsLive(throne) then
                table.insert(result, throne)
            end
        end
    end
    return result
end

function Thrones.HasThrone(userid)
    return #Thrones.GetThrones(userid) > 0
end

-- The throne that holds this player's queen, that she is walking to right now, or whose queen is out
-- with him (R4, sk_royalthrone:IsOccupied).
function Thrones.GetQueenThrone(userid)
    local set = userid ~= nil and registry[userid] or nil
    if set ~= nil then
        for throne in pairs(set) do
            if IsLive(throne) and throne.components.sk_royalthrone:IsOccupied() then
                return throne
            end
        end
    end
end

-- R4: a queen out with this player on this shard counts too (her throne may be gone or on another shard).
function Thrones.PlayerHasQueen(userid)
    return Thrones.GetQueenThrone(userid) ~= nil or Thrones.GetExpeditionQueen(userid) ~= nil
end

-- R4 Royal Expedition: queens out with their Webber (server) -----------------------------------------

local expedition_queens = setmetatable({}, { __mode = "v" }) -- [userid] = queen, this shard only

function Thrones.GetShardId()
    return TheShard ~= nil and TheShard:GetShardId() or nil
end

-- A player's userid, or nil while it is not known yet ("" before setowner).
function Thrones.GetUserId(player)
    local userid = player ~= nil and player.userid or nil
    return userid ~= nil and userid ~= "" and userid or nil
end

function Thrones.SetExpeditionQueen(userid, queen)
    if userid ~= nil and userid ~= "" then
        expedition_queens[userid] = queen
    end
end

function Thrones.ClearExpeditionQueen(userid, queen)
    if userid ~= nil and expedition_queens[userid] == queen then
        expedition_queens[userid] = nil
    end
end

function Thrones.GetExpeditionQueen(userid)
    local queen = userid ~= nil and expedition_queens[userid] or nil
    if queen ~= nil and queen:IsValid() and queen._sk_expedition ~= nil then
        return queen
    end
end

local function FindOnlinePlayer(userid)
    for _, player in ipairs(AllPlayers) do
        if player.userid == userid and not player.is_snapshot_user_session then
            return player
        end
    end
end

-- The "away" mark of this owner's throne on this shard no longer stands for a queen: the owner is here
-- (his expedition queen always travels with him) and has no queen out from this shard. That happens
-- when she died or went wild on another shard, where this throne could not be told.
-- While the owner is offline or on another shard the mark is kept: his save holds her.
function Thrones.IsAwayStale(userid)
    if userid == nil or FindOnlinePlayer(userid) == nil then
        return false
    end
    local queen = Thrones.GetExpeditionQueen(userid)
    return queen == nil or queen._sk_expedition.home_shard ~= Thrones.GetShardId()
end

-- Clears stale "away" marks of this player's thrones (owner just arrived, or he uses a throne).
function Thrones.ValidateAway(userid)
    for _, throne in ipairs(Thrones.GetAllThrones(userid)) do
        throne.components.sk_royalthrone:ValidateAway()
    end
end

-- Server: a wild queen that would listen right now ("not in combat" and not otherwise busy).
function Thrones.IsQueenCalm(queen)
    return queen ~= nil and queen:IsValid()
        and queen.prefab == Thrones.QUEEN_PREFAB
        and not queen:IsInLimbo()
        and queen._sk_invite == nil
        and queen._sk_expedition == nil -- R4: out with her Webber
        and queen.components.health ~= nil and not queen.components.health:IsDead()
        and not (queen.components.combat ~= nil and queen.components.combat:HasTarget())
        and not (queen.sg ~= nil and queen.sg:HasStateTag("busy"))
        and not (queen.components.sleeper ~= nil and queen.components.sleeper:IsAsleep())
        and not (queen.components.freezable ~= nil and queen.components.freezable:IsFrozen())
        and not (queen.components.burnable ~= nil and queen.components.burnable:IsBurning())
end

-- Server: the throne this player may invite this queen into, or nil and an ACTIONFAIL reason.
function Thrones.FindInviteThrone(doer, queen)
    local thrones = Thrones.GetThrones(doer.userid)
    if #thrones == 0 then
        return nil, "NOTHRONE"
    end
    if Thrones.PlayerHasQueen(doer.userid) then
        return nil, "HASQUEEN"
    end

    local range = TUNING.SPIDERKINGDOM.ROYAL_THRONE_INVITE_RANGE
    local best, bestdsq = nil, range * range
    for _, throne in ipairs(thrones) do
        if throne.components.sk_royalthrone:CanAcceptQueen() then
            local dsq = queen:GetDistanceSqToInst(throne)
            if dsq <= bestdsq then
                best, bestdsq = throne, dsq
            end
        end
    end
    if best == nil then
        return nil, "TOOFAR"
    end

    if not Thrones.IsQueenCalm(queen) then
        return nil, "BUSY"
    end
    return best
end

-- Client and server: USEITEM "inventoryitem" branch for target:HasTag("spiderqueen").
-- Called from networking/item_actions.lua BEFORE the generic "spider" branch (the queen has both tags).
-- The server re-checks the skill, the throne and the queen in ACTIONS.SK_ROYALINVITE.fn.
function Thrones.CollectQueenActions(inst, doer, target, actions, right)
    if not right
        and inst:HasTag(Thrones.INVITATION_TAG)
        and doer:HasTag(Thrones.MONARCH_TAG)
        and target.prefab == Thrones.QUEEN_PREFAB
        and not target:HasTag(Thrones.INVITED_TAG)
        and not target:HasTag(Thrones.EXPEDITION_TAG) then
        local health = target.replica.health
        if health == nil or not health:IsDead() then
            table.insert(actions, ACTIONS.SK_ROYALINVITE)
        end
    end
end

return Thrones
