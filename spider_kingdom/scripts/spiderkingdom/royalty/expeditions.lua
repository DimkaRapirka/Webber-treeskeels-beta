-- R4 Royal Expedition: shared rules. Plain module: require("spiderkingdom/royalty/expeditions").
--
-- The owner (Webber with R4) uses the Spider Whistle on his own Royal Throne:
--   * queen inside  -> "Call the queen": she leaves the throne (sk_royalthrone:ReleaseQueen(nil, true) marks
--     the throne "away" in the same call) and travels with him;
--   * queen out     -> "Send the queen home": she walks back and moves in (or appears inside at once when
--     she is far away or off screen).
-- One queen out per player at a time.
--
-- On the expedition (server):
--   * official follower component (replica prepared at spawn, royalty/expedition.lua), leader = the owner.
--     keepdeadleader: she stays with his ghost; KeepLeaderOnAttacked: a stray hit from him does not free her;
--   * brains/sk_queenexpeditionbrain.lua instead of the stock brain: no nest planting (makenest), no wild
--     spider births (poop_pre / incrementalproducer), follows and fights for him. Her stock brain, retarget,
--     keep-target, sleep tests and trader state are restored when she goes wild;
--   * never targets the owner or anyone the official CanBeAlly calls a friend (other players without PvP,
--     their followers, the owner's spiders); her sanity aura is already 0 for "spiderwhisperer" (stock);
--   * the R1 trader is disabled (no trades), she is never "calm" for a Royal Invitation (royalty/thrones.lua);
--   * she is bonded by components/sk_spiderkeeper.lua as the "queen" kind: persists = false, her record
--     lives in the owner's save, she leaves and comes back with him (logout, migration, reconnect).
--
-- Exactly one queen: she exists either as the throne's record, or as this live / saved companion (the
-- throne then only keeps an "away" mark), or as a wild queen in the world after the expedition ended.
--   * throne hammered / burnt / removed while she is out: nothing to release, she stays with the owner and
--     later moves into whichever usable throne he has on her home shard;
--   * owner death: she stays with the ghost; owner logout / migration: saved with him;
--   * her death: the expedition ends, her throne's mark is cleared (on another shard: when the owner next
--     arrives there, royalty/thrones.lua IsAwayStale);
--   * respec of R4 / owner without R4: she goes home at once if she can, otherwise as soon as she can;
--   * reroll / Wonkey (keeper released): she goes home if she can, otherwise she stays as a wild queen.
-- Cross-shard rule: she can only go home on her home shard (the shard of the throne she came from), because a
-- throne on another shard cannot be told she came back. On another shard the action fails with OTHERWORLD.
--
-- Affinity rituals: her variant is her own component (components/sk_queenvariant.lua), saved in her record, so
-- it needs nothing from the expedition data. Its combat effects only apply on an expedition: Start and Finish
-- refresh them (RefreshVariant), the owner's affinity skill events do the rest (affinity/rituals.lua).

local SKUtil = require("spiderkingdom/util")
local Thrones = require("spiderkingdom/royalty/thrones")

local Expeditions = {}

Expeditions.SKILL = "webber_sk_royal_expedition"
Expeditions.REGENT_TAG = "sk_regent"          -- player with R4 (client hint for SK_ROYALEXPEDITION)
Expeditions.WHISTLE_PREFAB = "spider_whistle"

local TICK = 0.5
local RETARGET_PERIOD = 1
local SPEED_KEY = "sk_expedition"

local RETARGET_MUST_TAGS = { "_combat" }
local RETARGET_CANT_TAGS = { "INLIMBO", "playerghost", "notarget", "noattack" }

local function Say(player, key)
    local royal = STRINGS.SK_ROYAL
    local text = royal ~= nil and royal[key] or nil
    if text ~= nil and player ~= nil and player:IsValid() and player.components.talker ~= nil then
        player.components.talker:Say(text)
    end
end

local function IsDead(inst)
    return inst.components.health ~= nil and inst.components.health:IsDead()
end

-- Affinity rituals: (re)applies or removes the variant's expedition effects (server).
local function RefreshVariant(queen)
    local variant = queen.components.sk_queenvariant
    if variant ~= nil then
        variant:Refresh()
    end
end

function Expeditions.IsOnExpedition(queen)
    return queen ~= nil and queen._sk_expedition ~= nil
end

function Expeditions.IsGoingHome(queen)
    local expedition = queen._sk_expedition
    return expedition ~= nil and expedition.gohome ~= nil
end

-- Combat ------------------------------------------------------------------------------------------

local function IsFriend(queen, guy)
    local expedition = queen._sk_expedition
    return guy == expedition.owner or queen.components.combat:CanBeAlly(guy)
end

-- Used by the SetTarget wrapper (royalty/expedition.lua): no target at all on the way home, never a friend.
function Expeditions.BlocksTarget(queen, target)
    local expedition = queen._sk_expedition
    return expedition ~= nil and (expedition.gohome ~= nil or IsFriend(queen, target))
end

-- Her own target search: whoever attacks her Webber or her.
local function Retarget(queen)
    local expedition = queen._sk_expedition
    local owner = expedition ~= nil and expedition.owner or nil
    if owner == nil or not owner:IsValid() or expedition.gohome ~= nil then
        return nil
    end
    local combat = queen.components.combat
    return FindEntity(queen, TUNING.SPIDERKINGDOM.ROYAL_EXPEDITION_DEFEND_RANGE, function(guy)
        local target = guy.components.combat ~= nil and guy.components.combat.target or nil
        return (target == owner or target == queen)
            and combat:CanTarget(guy)
            and not IsFriend(queen, guy)
    end, RETARGET_MUST_TAGS, RETARGET_CANT_TAGS)
end

-- She does not chase far from her Webber (the brain's Follow brings her back once the target is dropped).
local function KeepTarget(queen, target)
    local expedition = queen._sk_expedition
    if expedition == nil then
        return true
    end
    local owner = expedition.owner
    return expedition.gohome == nil
        and owner ~= nil and owner:IsValid()
        and not IsFriend(queen, target)
        and queen:IsNear(owner, TUNING.SPIDERKINGDOM.ROYAL_EXPEDITION_LEASH)
end

-- She stays awake to keep up; forced sleep (pan flute, sleep darts) still lasts its full time, because the
-- sleeper only runs the wake test after that time (components/sleeper.lua GoToSleep -> SetWakeTest).
local function NeverSleep()
    return false
end

local function AlwaysWake()
    return true
end

-- Home -------------------------------------------------------------------------------------------

-- The throne she goes back to, or nil and an ACTIONFAIL reason. Only on her home shard: the throne she
-- left (with the "away" mark) if it is usable, otherwise any usable empty throne of the owner here.
function Expeditions.FindHomeThrone(queen)
    local expedition = queen._sk_expedition
    if expedition == nil then
        return nil
    end
    if expedition.home_shard ~= Thrones.GetShardId() then
        return nil, "OTHERWORLD"
    end
    local fallback = nil
    for _, throne in ipairs(Thrones.GetThrones(expedition.userid)) do
        local component = throne.components.sk_royalthrone
        if component:HasAwayMark() and not component:HasQueen() then
            return throne
        end
        if fallback == nil and not component:IsOccupied() then
            fallback = throne
        end
    end
    if fallback ~= nil then
        return fallback
    end
    return nil, "NOTHRONE"
end

-- A queen that is not (or no longer) out: clears the "away" marks of the owner's thrones on her home shard.
local function ClearAwayMarks(userid, home_shard)
    if home_shard ~= Thrones.GetShardId() then
        return -- that throne is told later, royalty/thrones.lua IsAwayStale
    end
    for _, throne in ipairs(Thrones.GetAllThrones(userid)) do
        throne.components.sk_royalthrone:ClearAway()
    end
end

local function GetApproachPoint(queen, throne)
    local tx, ty, tz = throne.Transform:GetWorldPosition()
    local qx, qy, qz = queen.Transform:GetWorldPosition()
    local dx, dz = qx - tx, qz - tz
    local len = math.sqrt(dx * dx + dz * dz)
    local stop = TUNING.SPIDERKINGDOM.ROYAL_THRONE_ARRIVE_DIST * 0.5
    if len < 0.01 then
        return Vector3(tx + stop, 0, tz)
    end
    return Vector3(tx + dx / len * stop, 0, tz + dz / len * stop)
end

-- Ends the walk home without storing her. Returns the walk data, or nil if she was not walking.
local function StopGoHome(queen)
    local expedition = queen._sk_expedition
    local gohome = expedition ~= nil and expedition.gohome or nil
    if gohome == nil then
        return nil
    end
    expedition.gohome = nil

    gohome.task:Cancel()
    queen:RemoveEventCallback("onremove", gohome.onlost, gohome.throne)
    queen:RemoveEventCallback("onignite", gohome.onlost, gohome.throne)
    queen:RemoveEventCallback("entitysleep", gohome.onsleep)
    if queen.components.follower ~= nil then
        queen.components.follower:EnableLeashing()
    end
    return gohome
end

-- Moves her into the throne now. Returns true on success (the queen entity is gone then).
function Expeditions.StoreHome(queen, throne)
    local expedition = queen._sk_expedition
    local component = throne ~= nil and throne:IsValid() and throne.components.sk_royalthrone or nil
    if expedition == nil or component == nil or not component:CanStoreQueen(queen) then
        return false
    end
    StopGoHome(queen)

    local owner, home_shard = expedition.owner, expedition.home_shard
    local x, y, z = queen.Transform:GetWorldPosition()

    -- Expedition first, so the throne's record holds no follower / owner data.
    Expeditions.Finish(queen, "home")
    if component:StoreQueen(queen) then
        local fx = SpawnPrefab("spawn_fx_medium")
        if fx ~= nil then
            fx.Transform:SetPosition(x, y, z)
        end
        SKUtil.Log("Royal Expedition: queen back in", throne)
        return true
    end

    -- Cannot happen after CanStoreQueen; never leave her wild while her throne is marked "away".
    if owner ~= nil and owner:IsValid() and Expeditions.Start(queen, owner, { home_shard = home_shard }) then
        return false
    end
    ClearAwayMarks(Thrones.GetUserId(owner) or expedition.userid, home_shard)
    return false
end

-- Immediately, without the walk (respec, reroll, far away). Returns true if she is home now.
function Expeditions.ReturnNow(queen)
    local throne = Expeditions.FindHomeThrone(queen)
    return throne ~= nil and Expeditions.StoreHome(queen, throne)
end

local function ArriveHome(queen)
    local gohome = StopGoHome(queen)
    if gohome ~= nil and queen:IsValid() and not Expeditions.StoreHome(queen, gohome.throne) then
        local expedition = queen._sk_expedition
        Say(expedition ~= nil and expedition.owner or nil, "EXPEDITION_NOTHRONE")
    end
end

-- The throne burns or disappears on the way: she keeps following her Webber.
local function CancelGoHome(queen)
    if StopGoHome(queen) ~= nil then
        local expedition = queen._sk_expedition
        Say(expedition ~= nil and expedition.owner or nil, "EXPEDITION_NOTHRONE")
    end
end

local function GoHomeTick(queen)
    local expedition = queen._sk_expedition
    local gohome = expedition ~= nil and expedition.gohome or nil
    if gohome == nil then
        return
    end
    if not Thrones.IsUsable(gohome.throne) then
        CancelGoHome(queen)
        return
    end
    gohome.elapsed = gohome.elapsed + TICK
    local arrive = TUNING.SPIDERKINGDOM.ROYAL_THRONE_ARRIVE_DIST
    if queen:IsNear(gohome.throne, arrive) or gohome.elapsed >= TUNING.SPIDERKINGDOM.ROYAL_THRONE_WALK_TIME then
        ArriveHome(queen)
    end
end

-- "Send the queen home": she walks back (brain node SKGoHome), or appears inside at once when far / off
-- screen. The walk is not saved: a save taken during it keeps her out with the owner.
function Expeditions.SendHome(queen, throne)
    local expedition = queen._sk_expedition
    if expedition == nil then
        return false
    end
    if expedition.gohome ~= nil then
        return true
    end
    if queen:IsAsleep() or not queen:IsNear(throne, TUNING.SPIDERKINGDOM.ROYAL_EXPEDITION_WALK_RANGE) then
        return Expeditions.StoreHome(queen, throne)
    end

    local gohome =
    {
        throne = throne,
        pos = GetApproachPoint(queen, throne),
        elapsed = 0,
    }
    gohome.onlost = function() CancelGoHome(queen) end
    -- Off screen she would be ported back to her leader: move her in instead (next frame, not inside
    -- the engine's sleep callback).
    gohome.onsleep = function() queen:DoTaskInTime(0, ArriveHome) end
    expedition.gohome = gohome

    queen.components.combat:DropTarget()
    if queen.components.follower ~= nil then
        queen.components.follower:DisableLeashing()
    end
    queen:ListenForEvent("onremove", gohome.onlost, throne)
    queen:ListenForEvent("onignite", gohome.onlost, throne)
    queen:ListenForEvent("entitysleep", gohome.onsleep)
    gohome.task = queen:DoPeriodicTask(TICK, GoHomeTick)
    return true
end

-- Expedition lifecycle ---------------------------------------------------------------------------

local function OnQueenDeath(queen)
    Expeditions.Finish(queen, "dead")
end

-- Removed by the keeper (owner leaving), the throne (home), or anything else (console). Only the registry
-- needs care: a stale "away" mark is cleared by royalty/thrones.lua IsAwayStale.
local function OnQueenRemoved(queen)
    local expedition = queen._sk_expedition
    if expedition ~= nil then
        Thrones.ClearExpeditionQueen(expedition.userid, queen)
    end
end

-- Leader lost some other way than the owner leaving the server (keeper "despawning") or the expedition
-- ending: home if she can, otherwise wild. Deferred: this runs inside follower:SetLeader.
local function CheckLeader(queen)
    local expedition = queen._sk_expedition
    if expedition == nil or IsDead(queen) then
        return
    end
    local follower = queen.components.follower
    if follower ~= nil and follower:GetLeader() == expedition.owner then
        return
    end
    if not Expeditions.ReturnNow(queen) then
        Expeditions.Finish(queen, "wild")
    end
end

local function OnLeaderChanged(queen, data)
    local expedition = queen._sk_expedition
    if expedition == nil or (data ~= nil and data.new == expedition.owner) then
        return
    end
    local owner = expedition.owner
    local keeper = owner ~= nil and owner.components.sk_spiderkeeper or nil
    if keeper ~= nil and keeper:IsDespawning() then
        return -- logout / migration: she is saved with him and removed with him
    end
    queen:DoTaskInTime(0, CheckLeader)
end

-- An owner without R4 (respec, possibly on another shard or while offline) sends her home as soon as she
-- can go. Only once his skills are known: they arrive after the client handshake
-- (player_common_extensions.lua OnPostActivateHandshake_Server -> "ms_skilltreeinitialized").
local function CheckSkill(queen)
    local expedition = queen._sk_expedition
    if expedition ~= nil and expedition.skillready
        and expedition.owner:IsValid()
        and not SKUtil.HasSkill(expedition.owner, Expeditions.SKILL)
        and not IsDead(queen) then
        if Expeditions.ReturnNow(queen) then
            Say(expedition.owner, "EXPEDITION_HOME")
        end
    end
end

-- Starts (or, with data from the owner's save, resumes) the expedition. Returns true on success.
-- data: { home_shard, userid } (GetSaveData) or nil for a queen just called out on this shard.
function Expeditions.Start(queen, owner, data)
    local keeper = owner ~= nil and owner.components.sk_spiderkeeper or nil
    if queen == nil or not queen:IsValid() or queen._sk_expedition ~= nil or IsDead(queen)
        or keeper == nil or not keeper:CanBondQueen()
        or owner.components.leader == nil
        or queen.components.combat == nil then
        return false
    end

    local combat = queen.components.combat
    local sleeper = queen.components.sleeper
    local trader = queen.components.trader
    local restoring = data ~= nil

    local expedition =
    {
        owner = owner,
        userid = Thrones.GetUserId(owner) or (data ~= nil and data.userid) or nil,
        home_shard = data ~= nil and data.home_shard or Thrones.GetShardId(),
        -- A queen called out now: the caller just checked the skill. A restored one: wait for the handshake.
        skillready = not restoring,
        stock =
        {
            brainfn = queen.brainfn,
            targetfn = combat.targetfn,
            retargetperiod = combat.retargetperiod,
            keeptargetfn = combat.keeptargetfn,
            sleeptestfn = sleeper ~= nil and sleeper.sleeptestfn or nil,
            waketestfn = sleeper ~= nil and sleeper.waketestfn or nil,
            trader = trader ~= nil and trader.enabled or nil,
        },
    }
    queen._sk_expedition = expedition
    queen:AddTag(Thrones.EXPEDITION_TAG)

    -- Combat, sleep, trade (restored by Finish).
    combat:SetRetargetFunction(RETARGET_PERIOD, Retarget)
    combat:SetKeepTargetFunction(KeepTarget)
    combat:DropTarget()
    if sleeper ~= nil then
        sleeper:SetSleepTest(NeverSleep)
        sleeper:SetWakeTest(AlwaysWake)
    end
    if trader ~= nil then
        trader:Disable() -- R1: no trades with a queen on an expedition
    end
    if queen.components.locomotor ~= nil then
        -- Stock walk speed (TUNING.SPIDERQUEEN_WALKSPEED 1.75) could never keep up with a player.
        queen.components.locomotor:SetExternalSpeedMultiplier(queen, SPEED_KEY, TUNING.SPIDERKINGDOM.ROYAL_EXPEDITION_SPEED_MULT)
    end

    -- Follower of the owner. The replica was prepared at spawn (royalty/expedition.lua).
    if queen.components.follower == nil then
        queen:AddComponent("follower")
        expedition.addedfollower = true
    end
    local follower = queen.components.follower
    follower.keepdeadleader = true
    follower:KeepLeaderOnAttacked()
    owner.components.leader:AddFollower(queen)
    keeper:BondQueen(queen)

    -- Required here (server, first use): clients load this module for the collector only.
    queen:SetBrain(require("brains/sk_queenexpeditionbrain"))

    queen:ListenForEvent("death", OnQueenDeath)
    queen:ListenForEvent("onremove", OnQueenRemoved)
    queen:ListenForEvent("leaderchanged", OnLeaderChanged)
    if restoring then
        expedition.onskillready = function()
            expedition.skillready = true
            CheckSkill(queen)
        end
        queen:ListenForEvent("ms_skilltreeinitialized", expedition.onskillready, owner)
    end
    local period = TUNING.SPIDERKINGDOM.ROYAL_EXPEDITION_SKILL_CHECK
    expedition.checktask = queen:DoPeriodicTask(period, CheckSkill, period)

    -- A snapshot copy of the owner's session (mainfunctions.lua RestoreSnapshotUserSession) is not him.
    if not owner.is_snapshot_user_session then
        Thrones.SetExpeditionQueen(expedition.userid, queen)
    end

    RefreshVariant(queen)

    SKUtil.Log("Royal Expedition: queen out with", owner, "home shard", expedition.home_shard)
    return true
end

-- Ends the expedition. reason:
--   "home" - she is about to be stored in a throne (StoreHome), the throne clears its own mark;
--   "wild" - she stays in the world as a wild queen; her throne's mark is cleared;
--   "dead" - she died; her throne's mark is cleared, nothing is restored on the corpse.
function Expeditions.Finish(queen, reason)
    local expedition = queen._sk_expedition
    if expedition == nil then
        return
    end
    StopGoHome(queen)

    -- First, so every callback below sees a queen without an expedition.
    queen._sk_expedition = nil
    queen:RemoveTag(Thrones.EXPEDITION_TAG)
    RefreshVariant(queen) -- no expedition: variant effects off

    if expedition.checktask ~= nil then
        expedition.checktask:Cancel()
    end
    queen:RemoveEventCallback("death", OnQueenDeath)
    queen:RemoveEventCallback("onremove", OnQueenRemoved)
    queen:RemoveEventCallback("leaderchanged", OnLeaderChanged)
    if expedition.onskillready ~= nil then
        queen:RemoveEventCallback("ms_skilltreeinitialized", expedition.onskillready, expedition.owner)
    end
    Thrones.ClearExpeditionQueen(expedition.userid, queen)

    local owner = expedition.owner
    local keeper = owner ~= nil and owner.components.sk_spiderkeeper or nil
    if keeper ~= nil then
        keeper:UnbondQueen(queen) -- persists = true again
    else
        queen.persists = true
    end

    local follower = queen.components.follower
    if follower ~= nil then
        local leader = follower.leader
        if leader ~= nil and leader.components.leader ~= nil then
            leader.components.leader:RemoveFollower(queen)
        else
            follower:SetLeader(nil)
        end
        if expedition.addedfollower then
            queen:RemoveComponent("follower")
        else
            follower.keepdeadleader = nil
            follower:LoseLeaderOnAttacked()
        end
    end

    if queen.components.locomotor ~= nil then
        queen.components.locomotor:RemoveExternalSpeedMultiplier(queen, SPEED_KEY)
    end

    if reason ~= "home" then
        ClearAwayMarks(expedition.userid, expedition.home_shard)
    end
    if reason == "dead" then
        SKUtil.Log("Royal Expedition: queen died")
        return
    end

    local stock = expedition.stock
    local combat = queen.components.combat
    combat:SetRetargetFunction(stock.retargetperiod, stock.targetfn)
    combat:SetKeepTargetFunction(stock.keeptargetfn)
    local sleeper = queen.components.sleeper
    if sleeper ~= nil then
        sleeper:SetSleepTest(stock.sleeptestfn)
        sleeper:SetWakeTest(stock.waketestfn)
    end
    if queen.components.trader ~= nil and stock.trader then
        queen.components.trader:Enable()
    end
    queen:SetBrain(stock.brainfn)

    SKUtil.Log("Royal Expedition: expedition ended,", reason)
end

-- Owner's save (components/sk_spiderkeeper.lua) ------------------------------------------------------

-- Her Affinity variant is not here: it is saved in her own record (components/sk_queenvariant.lua).
function Expeditions.GetSaveData(queen)
    local expedition = queen._sk_expedition
    return expedition ~= nil
        and { home_shard = expedition.home_shard, userid = expedition.userid }
        or nil
end

-- A queen respawned from the owner's save. Resumes the expedition; if the keeper cannot hold her (a
-- conflicting spider-transfer mod made it passive), she moves into her throne if it is here, otherwise she
-- stays as a wild queen. Returns true if the expedition resumed.
function Expeditions.Restore(queen, owner, data)
    data = data or {}
    -- Saves from before the variant component kept it here ("variant").
    local variant = queen.components.sk_queenvariant
    if data.variant ~= nil and variant ~= nil and variant:GetVariant() == nil then
        variant:SetVariant(data.variant)
    end
    if Expeditions.Start(queen, owner, { home_shard = data.home_shard or Thrones.GetShardId(), userid = data.userid }) then
        return true
    end
    if data.home_shard == nil or data.home_shard == Thrones.GetShardId() then
        local userid = Thrones.GetUserId(owner) or data.userid
        for _, throne in ipairs(Thrones.GetThrones(userid)) do
            local component = throne.components.sk_royalthrone
            if (component:HasAwayMark() or not component:IsOccupied()) and component:StoreQueen(queen) then
                return false
            end
        end
        ClearAwayMarks(userid, Thrones.GetShardId())
    end
    print("[SpiderKingdom] Royal Expedition: could not resume the expedition, the queen stays wild.")
    return false
end

-- The keeper lets everything go (Celestial Portal reroll, Wonkey): home if she can, otherwise wild.
function Expeditions.OnKeeperReleased(queen)
    if queen._sk_expedition ~= nil and not Expeditions.ReturnNow(queen) then
        Expeditions.Finish(queen, "wild")
    end
end

-- Throne action (royalty/expedition.lua SK_ROYALEXPEDITION.fn) ---------------------------------------

local function CallOut(doer, throne)
    local keeper = doer.components.sk_spiderkeeper
    if keeper == nil or not keeper:CanBondQueen() or doer.components.leader == nil then
        return false, "CANNOT"
    end
    if doer:HasTag("playerghost") or not Thrones.IsUsable(throne) then
        return false
    end

    local component = throne.components.sk_royalthrone
    local queen = component:ReleaseQueen(nil, true)
    if queen == nil then
        return false
    end
    if not Expeditions.Start(queen, doer) then
        -- Cannot happen after the checks above; never leave a wild queen next to an "away" throne.
        if not component:StoreQueen(queen) then
            component:ClearAway()
        end
        return false
    end
    Say(doer, "EXPEDITION_CALLED")
    return true
end

-- Server. The caller checked the whistle, the skill and that doer owns the usable throne.
function Expeditions.UseThrone(doer, throne)
    local component = throne.components.sk_royalthrone
    Thrones.ValidateAway(doer.userid)

    local queen = Thrones.GetExpeditionQueen(doer.userid)
    if component:HasQueen() then
        if queen ~= nil then
            return false, "ALREADYOUT"
        end
        return CallOut(doer, throne)
    end

    if queen == nil or queen._sk_expedition.owner ~= doer then
        return false, "NOQUEEN"
    end
    if queen._sk_expedition.gohome ~= nil then
        return true -- already on her way
    end
    local home, reason = Expeditions.FindHomeThrone(queen)
    if home == nil then
        return false, reason
    end
    if home ~= throne then
        return false, "NOTHERTHRONE"
    end
    if IsDead(queen) or queen:IsInLimbo() then
        return false, "BUSY"
    end
    if not Expeditions.SendHome(queen, throne) then
        return false, "BUSY"
    end
    Say(doer, "EXPEDITION_HOME")
    return true
end

-- R4 skill handler (skilltree/handlers.lua: Wrap(Expeditions)) ---------------------------------------

function Expeditions.Enable(inst)
    inst:AddTag(Expeditions.REGENT_TAG)
end

-- Respec: a queen out with him goes home at once if she can (otherwise CheckSkill keeps trying).
function Expeditions.Disable(inst)
    inst:RemoveTag(Expeditions.REGENT_TAG)
    local queen = Thrones.GetExpeditionQueen(inst.userid)
    if queen ~= nil and queen._sk_expedition.owner == inst and Expeditions.ReturnNow(queen) then
        Say(inst, "EXPEDITION_HOME")
    end
end

-- Client and server: USEITEM "inventoryitem" branch for target:HasTag(Thrones.THRONE_TAG), called from
-- networking/item_actions.lua. Offered on any throne; the server checks the owner and the queen.
function Expeditions.CollectThroneActions(inst, doer, target, actions, right)
    if not right
        and inst.prefab == Expeditions.WHISTLE_PREFAB
        and doer:HasTag(Expeditions.REGENT_TAG)
        and not target:HasTag("burnt") then
        table.insert(actions, ACTIONS.SK_ROYALEXPEDITION)
    end
end

return Expeditions
