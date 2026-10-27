-- R2 Royal Throne: Webber with the skill uses a Royal Invitation on a calm wild Spider Queen while
-- one of his thrones is close to her. The invitation is spent, the queen screams, walks to the
-- throne with her brain paused and moves in (components/sk_royalthrone.lua stores her as a save
-- record). If she does not arrive in time she is placed inside anyway. If she is attacked, dies, or
-- the throne burns or disappears on the way, she stays wild and the invitation is given back.
-- The walk is not saved: a save taken during it reloads her as a wild queen, and the throne's save
-- (sk_royalthrone OnSave "pending_invitation") drops the spent invitation back next to the throne.
-- One throne per player (recipe canbuild, royalty/recipes.lua) and one queen per player
-- (royalty/thrones.lua FindInviteThrone).
--
-- The client collector branch is Thrones.CollectQueenActions, called from networking/item_actions.lua.

local _G = GLOBAL
local SKUtil = require("spiderkingdom/util")
local Thrones = require("spiderkingdom/royalty/thrones")

local BRAIN_REASON = "sk_royalinvite"
local TICK = 0.5

-- Strings --------------------------------------------------------------------------------------

-- The recipe's canbuild refusal is read from ACTIONFAIL.BUILD[reason]. Webber has his own BUILD
-- table, which does not fall back to the generic one, so the line goes into both.
local function AddBuildFailString()
    local royal = _G.STRINGS.SK_ROYAL
    local text = royal ~= nil and royal.BUILD_HASTHRONE or nil
    if text == nil then
        return
    end
    for _, character in ipairs({ "GENERIC", "WEBBER" }) do
        local speech = _G.STRINGS.CHARACTERS[character]
        if speech ~= nil and speech.ACTIONFAIL ~= nil then
            if type(speech.ACTIONFAIL.BUILD) ~= "table" then
                speech.ACTIONFAIL.BUILD = {}
            end
            speech.ACTIONFAIL.BUILD.SK_HASTHRONE = text
        end
    end
end
AddBuildFailString()

local function Say(doer, key)
    local royal = _G.STRINGS.SK_ROYAL
    local text = royal ~= nil and royal[key] or nil
    if text ~= nil and doer ~= nil and doer:IsValid() and doer.components.talker ~= nil then
        doer.components.talker:Say(text)
    end
end

-- The walk to the throne -------------------------------------------------------------------------

local function GetApproachPoint(queen, throne)
    local tx, ty, tz = throne.Transform:GetWorldPosition()
    local qx, qy, qz = queen.Transform:GetWorldPosition()
    local dx, dz = qx - tx, qz - tz
    local len = math.sqrt(dx * dx + dz * dz)
    local stop = TUNING.SPIDERKINGDOM.ROYAL_THRONE_ARRIVE_DIST * 0.5
    if len < 0.01 then
        return _G.Vector3(tx + stop, 0, tz)
    end
    return _G.Vector3(tx + dx / len * stop, 0, tz + dz / len * stop)
end

local OnInviteInterrupted -- forward declaration (StopInvite's callers refer to it)

-- removing: the queen herself is being removed. BrainManager already dropped her
-- (mainfunctions.lua OnRemoveEntity runs before "onremove"), so her brain must not restart.
local function StopInvite(queen, removing)
    local invite = queen._sk_invite
    if invite == nil then
        return nil
    end
    queen._sk_invite = nil

    if invite.task ~= nil then
        invite.task:Cancel()
    end
    local interrupt = invite.oninterrupt
    queen:RemoveEventCallback("attacked", interrupt)
    queen:RemoveEventCallback("death", interrupt)
    queen:RemoveEventCallback("onremove", invite.onremoved)
    queen:RemoveEventCallback("onremove", interrupt, invite.throne)
    queen:RemoveEventCallback("onignite", interrupt, invite.throne)
    queen:RemoveEventCallback("burntup", interrupt, invite.throne)
    if invite.throne:IsValid() and invite.throne.components.sk_royalthrone ~= nil then
        invite.throne.components.sk_royalthrone:ClearIncoming(queen)
    end

    queen:RemoveTag(Thrones.INVITED_TAG)
    if not removing then
        if queen.components.locomotor ~= nil then
            queen.components.locomotor:Stop()
        end
        queen:RestartBrain(BRAIN_REASON)
    end
    return invite
end

local function RefundInvitation(invite, queen)
    local item = _G.SpawnPrefab(Thrones.INVITATION_PREFAB)
    if item == nil then
        return
    end
    local pos = queen:IsValid() and queen:GetPosition() or invite.pos
    local doer = invite.doer
    if doer ~= nil and doer:IsValid() and not doer:HasTag("playerghost") and doer.components.inventory ~= nil then
        doer.components.inventory:GiveItem(item, nil, pos)
    else
        item.Transform:SetPosition(pos:Get())
    end
end

-- Any interruption: she stays wild and the invitation comes back.
OnInviteInterrupted = function(queen, removing)
    local invite = StopInvite(queen, removing)
    if invite ~= nil then
        RefundInvitation(invite, queen)
    end
end

local function EnterThrone(queen)
    local invite = StopInvite(queen)
    if invite == nil then
        return
    end
    local throne = invite.throne
    local x, y, z = queen.Transform:GetWorldPosition()
    if throne:IsValid() and throne.components.sk_royalthrone ~= nil
        and throne.components.sk_royalthrone:StoreQueen(queen) then
        local fx = _G.SpawnPrefab("spawn_fx_medium")
        if fx ~= nil then
            fx.Transform:SetPosition(x, y, z)
        end
        Say(invite.doer, "INVITED")
        SKUtil.Log("Royal Throne:", invite.doer, "settled a queen in", throne)
    else
        RefundInvitation(invite, queen)
    end
end

local function InviteTick(queen)
    local invite = queen._sk_invite
    if invite == nil then
        return
    end
    local throne = invite.throne
    if not Thrones.IsUsable(throne) then
        OnInviteInterrupted(queen)
        return
    end

    invite.pos = queen:GetPosition()
    invite.elapsed = invite.elapsed + TICK

    local arrive = TUNING.SPIDERKINGDOM.ROYAL_THRONE_ARRIVE_DIST
    if queen:GetDistanceSqToInst(throne) <= arrive * arrive
        or invite.elapsed >= TUNING.SPIDERKINGDOM.ROYAL_THRONE_WALK_TIME then
        EnterThrone(queen)
        return
    end

    -- (Re)start walking whenever she is free to: after the taunt, a hit reaction, waking up...
    local locomotor = queen.components.locomotor
    if locomotor ~= nil and not queen.sg:HasStateTag("busy") and not locomotor:WantsToMoveForward() then
        locomotor:GoToPoint(GetApproachPoint(queen, throne))
    end
end

local function StartInvite(queen, throne, doer)
    queen._sk_invite =
    {
        throne = throne,
        doer = doer,
        pos = queen:GetPosition(),
        elapsed = 0,
    }
    queen:AddTag(Thrones.INVITED_TAG)
    throne.components.sk_royalthrone:SetIncoming(queen)

    -- No wandering, nest planting, birthing or chasing while she walks (spiderqueenbrain.lua).
    queen:StopBrain(BRAIN_REASON)
    if queen.components.combat ~= nil then
        queen.components.combat:DropTarget()
    end

    -- Event callbacks receive the entity that pushed the event (the throne for its own events),
    -- so one closure per invitation always refers to this queen.
    local interrupt = function() OnInviteInterrupted(queen) end
    local onremoved = function() OnInviteInterrupted(queen, true) end
    queen._sk_invite.oninterrupt = interrupt
    queen._sk_invite.onremoved = onremoved
    queen:ListenForEvent("attacked", interrupt)
    queen:ListenForEvent("death", interrupt)
    queen:ListenForEvent("onremove", onremoved)
    queen:ListenForEvent("onremove", interrupt, throne)
    queen:ListenForEvent("onignite", interrupt, throne)
    queen:ListenForEvent("burntup", interrupt, throne)

    queen:ForceFacePoint(doer.Transform:GetWorldPosition())
    if not queen.sg:HasStateTag("busy") then
        queen.sg:GoToState("taunt")
    end

    queen._sk_invite.task = queen:DoPeriodicTask(TICK, InviteTick)
end

-- Action -----------------------------------------------------------------------------------------

local SK_ROYALINVITE = _G.Action({ priority = 1, mount_valid = false })
SK_ROYALINVITE.id = "SK_ROYALINVITE"
SK_ROYALINVITE.str = _G.STRINGS.ACTIONS.SK_ROYALINVITE
SK_ROYALINVITE.fn = function(act)
    local doer, queen, item = act.doer, act.target, act.invobject
    if doer == nil or queen == nil or item == nil
        or item.prefab ~= Thrones.INVITATION_PREFAB
        or queen.prefab ~= Thrones.QUEEN_PREFAB then
        return false
    end
    if not SKUtil.HasSkill(doer, Thrones.SKILL) then
        return false
    end

    local throne, reason = Thrones.FindInviteThrone(doer, queen)
    if throne == nil then
        return false, reason
    end

    local used = item.components.stackable ~= nil and item.components.stackable:Get() or item
    used:Remove()

    StartInvite(queen, throne, doer)
    return true
end
AddAction(SK_ROYALINVITE)

-- Client collector: Thrones.CollectQueenActions, called from networking/item_actions.lua.

AddStategraphActionHandler("wilson", _G.ActionHandler(_G.ACTIONS.SK_ROYALINVITE, "give"))
AddStategraphActionHandler("wilson_client", _G.ActionHandler(_G.ACTIONS.SK_ROYALINVITE, "give"))
