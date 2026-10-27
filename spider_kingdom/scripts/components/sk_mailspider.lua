-- sk_mailspider (server only, on sk_courierspider): T2 Spider Mail, reworked after the WX-78 delivery drone
-- (prefabs/wx78_drone_delivery.lua). The official mapdeliverable component provides "Send" (right click),
-- the map target, the flight progress and its save/resume; this component handles what the spider does:
--   idle      - an ordinary follower of its owner (bonded by sk_spiderkeeper, travels across shards);
--   out       - flying to the map point, out of the scene (RemoveFromScene, like Woby's teleports);
--   waiting   - landed at the destination as an open container, standing still and not fighting, until
--               it is emptied, the wait runs out, or its owner comes close;
--   returning - flying back to its owner, then following again.
-- While it is away (tag "sk_away") it is not a follower at all: no bonding, leashing, whistle, repellent
-- or shard migration with the owner. It persists in the world like the drone; only the owner's userid
-- is kept, and it joins him again when it is back.
--
-- Across worlds (Phase 5.5, couriers/shard_common.lua): a map point next to an open world portal sends it
-- through to the linked shard.
--   transit   - hidden at the portal, waiting for the other shard to confirm it has spawned the copy;
--   arriving  - only inside the save record that crosses (Quarantine replaces it at once);
--   quarantine - arrived, hidden at the paired portal until its receipt is saved on this shard, so its
--               cargo cannot be used before the arrival is final.
-- On the other side it waits next to the paired portal like at any destination. When it would fly back
-- and its owner is not on that shard, it crosses back the same way (home = the shard it was sent from)
-- and then flies to him, or waits at the portal for him. Cargo that official migration would not let
-- through (irreplaceable items, a Beefalo Bell with its beefalo...) is dropped at the portal first, with
-- the official worldmigrator:DropThingsThatShouldNotMigrate.

local MailShard = require("spiderkingdom/couriers/shard_common")

local Courier = Class(function(self, inst)
    self.inst = inst
    self.portal = nil        -- out trip: id of the local portal it will cross at the destination
    self.home = nil          -- shard id it was sent from (cleared when it rejoins its owner)
    self.arrived_portal = nil -- on the far side: id of the local portal it came out of
    self.transit = nil       -- { id, world, portal, next } while crossing
    self.owner_userid = nil
    self.phase = "idle"
    self.wait_left = 0
    self.had_cargo = false
    self.task = nil

    local function DropCargo()
        if inst.components.container ~= nil then
            inst.components.container:DropEverything()
        end
    end
    inst:ListenForEvent("death", DropCargo)
    -- Any other removal (e.g. murder, which takes it out of the inventory first) except sk_spiderkeeper
    -- packing it into the owner's save, or the owner's inventory being torn down after it was saved
    -- with the courier still held: the container's own removal only closes it.
    inst:ListenForEvent("onremove", function()
        local held = inst.components.inventoryitem ~= nil and inst.components.inventoryitem:IsHeld()
        if not inst._sk_keeper_removed and not held then
            DropCargo()
        end
    end)

    -- Away from the pack nobody may recruit it (feeding, Spider Hat, ...): leave such a leader at once.
    inst:ListenForEvent("startfollowing", function(inst, data)
        if self:IsAway() and not self.rejoining then
            inst:DoTaskInTime(0, function()
                local follower = inst.components.follower
                local leader = follower ~= nil and follower:GetLeader() or nil
                if self:IsAway() and leader ~= nil and leader.components.leader ~= nil then
                    leader.components.leader:RemoveFollower(inst)
                    follower:ClearCachedPlayerLeader()
                end
            end)
        end
    end)

    -- Not pickable while away (stock spiders become pickable when they fall asleep).
    local function KeepUnpickable()
        if self:IsAway() and inst.components.inventoryitem ~= nil then
            inst.components.inventoryitem.canbepickedup = false
        end
    end
    inst:ListenForEvent("gotosleep", KeepUnpickable)
    inst:ListenForEvent("onwakeup", KeepUnpickable)
    inst:ListenForEvent("startleashing", KeepUnpickable) -- stock OnStartLeashing makes it pickable
    self.KeepUnpickable = KeepUnpickable
end)

local function FindPlayer(userid)
    if userid == nil then
        return nil
    end
    for _, player in ipairs(AllPlayers) do
        if player.userid == userid then
            return player
        end
    end
end

function Courier:IsAway()
    return self.phase ~= "idle"
end

function Courier:GetOwner()
    return FindPlayer(self.owner_userid)
end

function Courier:SetOwner(player)
    self.owner_userid = player ~= nil and player.userid or self.owner_userid
end

local function StartTask(self)
    if self.task == nil then
        self.task = self.inst:DoPeriodicTask(2, function() self:Tick() end)
    end
end

local function StopTask(self)
    if self.task ~= nil then
        self.task:Cancel()
        self.task = nil
    end
end

local function GetRegistry()
    return TheWorld.components.sk_mailregistry
end

local function IsForeign(self)
    return self.home ~= nil and self.home ~= TheShard:GetShardId()
end

local function ContainerHasItems(inst)
    local container = inst.components.container
    return container ~= nil and not container:IsEmpty()
end

-- Leaves the owner's pack for the trip: no longer a follower (so no bonding, leashing, whistle or
-- migration), not openable, out of the scene.
local function TakeOff(self)
    local inst = self.inst
    local follower = inst.components.follower
    local leader = follower ~= nil and follower:GetLeader() or nil
    inst:AddTag("sk_away")
    if leader ~= nil and leader.components.leader ~= nil then
        leader.components.leader:RemoveFollower(inst) -- unbonds through the follower hooks
    end
    if follower ~= nil then
        follower:ClearCachedPlayerLeader() -- no stock re-follow within 20 units after a load
    end
    inst.persists = true
    self.KeepUnpickable()
    if inst.components.container ~= nil then
        inst.components.container:Close()
        inst.components.container.canbeopened = false
    end
    if inst.components.combat ~= nil then
        inst.components.combat:DropTarget()
    end
    if self.origin == nil then
        self.origin = inst:GetPosition()
    end
    if not inst:IsInLimbo() then
        local fx = SpawnPrefab("spawn_fx_small")
        if fx ~= nil then
            fx.Transform:SetPosition(inst.Transform:GetWorldPosition())
        end
        inst:RemoveFromScene()
    end
end

local function IsLandable(pt)
    return TheWorld.Map:IsPassableAtPoint(pt.x, 0, pt.z) and not TheWorld.Map:IsGroundTargetBlocked(pt)
end

-- A walkable spot near pt, or nil. Map points may be ocean or void (mapdeliverable only checks flight).
local function FindLandingSpot(pt)
    if IsLandable(pt) then
        return pt
    end
    for _, radius in ipairs({ 2, 4, 8 }) do
        local offset = FindWalkableOffset(pt, math.random() * TWOPI, radius, 12, true, false)
        if offset ~= nil then
            return pt + offset
        end
    end
end

-- Returns false if there is no safe spot anywhere yet (the courier then stays hidden and retries).
local function Land(self, pos)
    local inst = self.inst
    local owner = self:GetOwner()
    local spot = FindLandingSpot(pos)
        or (self.origin ~= nil and FindLandingSpot(self.origin))
        or (owner ~= nil and owner:IsValid() and FindLandingSpot(owner:GetPosition()))
    if not spot then -- the "and" chain can yield false, not only nil
        return false
    end
    inst.Transform:SetPosition(spot.x, 0, spot.z)
    if inst:IsInLimbo() then
        inst:ReturnToScene()
    end
    if inst.components.container ~= nil then
        inst.components.container.canbeopened = true
    end
    local fx = SpawnPrefab("spawn_fx_small")
    if fx ~= nil then
        fx.Transform:SetPosition(spot.x, 0, spot.z)
    end
    self.KeepUnpickable()
    return true
end

-- Back with the owner: follow and bond again.
local function Rejoin(self, owner)
    local inst = self.inst
    self.phase = "idle"
    self.origin = nil
    self.portal = nil
    self.home = nil
    self.arrived_portal = nil
    StopTask(self)
    inst:RemoveTag("sk_away")
    if owner.components.leader ~= nil then
        self.rejoining = true
        owner.components.leader:AddFollower(inst) -- sk_spiderkeeper bonds through the follower hooks
        self.rejoining = nil
    end
end

-- mapdeliverable callbacks --------------------------------------------------------------------

-- Who may open the map for this courier (mapdeliverable onstartmapactionfn): its owner, idle, with the skill.
function Courier:CanStartMapAction(doer)
    if doer == nil or self.phase ~= "idle" then
        return false
    end
    local updater = doer.components.skilltreeupdater
    if updater == nil or not updater:IsActivated("webber_sk_symbiosis_mail") then
        return false
    end
    return self.inst.components.follower:GetLeader() == doer
end

-- doer is nil when mapdeliverable resumes a saved flight (MapDeliverable:OnLoad) or for the way back.
function Courier:OnStartDelivery(pt, doer)
    if self.phase == "idle" then
        if not self:CanStartMapAction(doer) or FindLandingSpot(pt) == nil then
            return false
        end
        self:SetOwner(doer)
        self.phase = "out"
        self.origin = nil
        self.had_cargo = ContainerHasItems(self.inst)
        self.home = TheShard:GetShardId()
        local portal = MailShard.FindPortalNear(pt, TUNING.SPIDERKINGDOM.MAIL_PORTAL_RADIUS)
        self.portal = portal ~= nil and portal.components.worldmigrator.id or nil
    elseif self.phase ~= "out" and self.phase ~= "returning" then
        return false
    end
    TakeOff(self)
    StartTask(self)
    return true
end

function Courier:OnDeliveryProgress(t, len, origin, dest)
    local inst = self.inst
    local k = len > 0 and t / len or 1
    local x, _, z = inst.Transform:GetWorldPosition()
    local nx, nz = origin.x + (dest.x - origin.x) * k, origin.z + (dest.z - origin.z) * k
    if IsFlyingPermittedFromPointToPoint_BypassVault(x, 0, z, nx, 0, nz) then
        inst.Transform:SetPosition(nx, 0, nz)
    else
        inst.components.mapdeliverable:Stop()
    end
end

function Courier:OnStopDelivery()
    local inst = self.inst
    if self.phase == "out" and self.portal ~= nil then
        local portal = MailShard.FindPortalById(self.portal)
        self.portal = nil
        if MailShard.IsPortalOpen(portal) then
            self:Ship(portal, "waiting")
            return
        end
        -- The portal closed on the way (plugged, other shard down): deliver here instead.
    end
    if not Land(self, inst:GetPosition()) then
        -- Nowhere safe to land (moved boats, owner offline): stay hidden and retry from the tick.
        self.stranded_at = inst:GetPosition()
        self.phase = "stranded"
        StartTask(self)
        return
    end
    if self.phase == "returning" then
        local owner = self:GetOwner()
        if owner ~= nil and owner:IsValid() and inst:GetDistanceSqToInst(owner) <= TUNING.SPIDERKINGDOM.MAIL_REJOIN_DIST * TUNING.SPIDERKINGDOM.MAIL_REJOIN_DIST then
            Rejoin(self, owner)
            return
        end
    end
    -- Arrived (or could not reach the owner): wait here as an open container.
    self.phase = "waiting"
    self.wait_left = TUNING.SPIDERKINGDOM.MAIL_WAIT_TIME
    StartTask(self)
end

function Courier:CalcDeliveryTime(dest)
    local x, _, z = self.inst.Transform:GetWorldPosition()
    local dist = math.sqrt(math2d.DistSq(x, z, dest.x, dest.z))
    return 2 + dist / TUNING.SPIDERKINGDOM.MAIL_SPEED
end

function Courier:StartReturn(owner)
    if self.phase ~= "waiting" or self.inst.components.mapdeliverable:IsDelivering() then
        return false
    end
    self.phase = "returning"
    local ok = self.inst.components.mapdeliverable:SendToPoint(owner:GetPosition(), nil)
    if not ok then
        self.phase = "waiting"
    end
    return ok
end

-- Across worlds ---------------------------------------------------------------------------------

-- Hidden at the portal; the parcel goes out once this state is saved, and again until the other shard
-- answers (couriers/shard_common.lua).
function Courier:Ship(portal, next_phase)
    local inst = self.inst
    local migrator = portal.components.worldmigrator
    TakeOff(self)
    migrator:DropThingsThatShouldNotMigrate(inst)
    self.phase = "transit"
    self.transit =
    {
        id = MailShard.NewParcelId(),
        world = migrator.linkedWorld,
        portal = migrator.receivedPortal,
        next = next_phase,
    }
    GetRegistry():Register(self.transit.id, inst)
    GetRegistry():RequestSave()
    StartTask(self)

    local owner = self:GetOwner()
    if owner ~= nil and owner.components.talker ~= nil and inst:IsNear(owner, TUNING.SPIDERKINGDOM.MAIL_SAY_DIST) then
        owner.components.talker:Say(STRINGS.SK_MAIL.CROSSED)
    end
end

-- The transit state is on disk (marked in OnSave; DURABLE when loaded): see couriers/shard_common.lua.
local function IsTransitDurable(transit)
    return MailShard.IsDurable(transit.mark)
end

function Courier:SendParcel()
    local transit = self.transit
    if transit == nil or not IsTransitDurable(transit) or not Shard_IsWorldAvailable(transit.world) then
        return
    end
    transit.sent = GetTime()
    self.packing = true -- OnSave writes the far side's state into the record
    local record = self.inst:GetSaveRecord()
    self.packing = nil
    MailShard.SendParcel(transit.world, transit.id, transit.portal, record)
end

-- The other shard has the courier now: remove this copy without dropping its cargo.
function Courier:OnShipped(id)
    if self.phase ~= "transit" or self.transit == nil or self.transit.id ~= id then
        return
    end
    GetRegistry():Unregister(id)
    GetRegistry():AddForget(id, self.transit.world)
    self.transit = nil
    StopTask(self)
    self.inst._sk_keeper_removed = true -- the onremove cargo drop is for other removals
    self.inst:Remove()
end

-- The other shard could not take it: arrive here, at the portal.
function Courier:OnShipRejected(id)
    if self.phase ~= "transit" or self.transit == nil or self.transit.id ~= id then
        return
    end
    GetRegistry():Unregister(id)
    GetRegistry():AddForget(id, self.transit.world) -- once landing here is saved, the refusal may go
    local next_phase = self.transit.next
    self.transit = nil
    self.retry_home_at = GetTime() + TUNING.SPIDERKINGDOM.MAIL_SHARD_RETRY -- no RPC loop on a lasting refusal
    self.phase = next_phase == "returning" and "returning" or "out"
    self:OnStopDelivery()
end

-- Far side: spawned from the parcel (couriers/shard.lua). Hidden at the paired portal until the receipt
-- is on disk (Tick -> OnArrive).
function Courier:Quarantine(parcel_id, portal)
    local inst = self.inst
    local x, _, z = portal.Transform:GetWorldPosition()
    inst.Transform:SetPosition(x, 0, z)
    if not inst:IsInLimbo() then
        inst:RemoveFromScene()
    end
    if inst.components.container ~= nil then
        inst.components.container:Close()
        inst.components.container.canbeopened = false
    end
    self.phase = "quarantine"
    self.quarantine = { id = parcel_id, portal = portal.components.worldmigrator.id }
    StartTask(self)
end

function Courier:OnArrive()
    local inst = self.inst
    local quarantine = self.quarantine
    self.quarantine = nil
    self.arrived_portal = quarantine ~= nil and quarantine.portal or nil
    local next_phase = self.arrive_next
    self.arrive_next = nil

    local portal = MailShard.FindPortalById(self.arrived_portal)
    local pt = portal ~= nil and portal:GetPosition() or inst:GetPosition()
    local offset = FindWalkableOffset(pt, math.random() * TWOPI, TUNING.SPIDERKINGDOM.MAIL_PORTAL_EXIT_DIST, 12, true, false)
    if offset ~= nil then
        pt = pt + offset
    end
    inst.Transform:SetPosition(pt.x, 0, pt.z)
    self.origin = nil

    if next_phase == "returning" then
        self.had_cargo = false -- back home: go to the owner right away
        self.phase = "returning"
    else
        self.phase = "out"
    end
    self:OnStopDelivery()
end

-- Far side, owner not on this shard: cross back the way it came.
function Courier:ShipHome()
    if self.retry_home_at ~= nil and GetTime() < self.retry_home_at then
        return false
    end
    local portal = MailShard.FindPortalTo(self.home, self.arrived_portal)
    if portal == nil then
        return false -- home shard down or the portal closed: keep waiting
    end
    self:Ship(portal, "returning")
    return true
end

-- While waiting: come home when emptied, when the wait is over, or join the owner who walked up.
function Courier:Tick()
    local inst = self.inst
    if self.phase == "transit" then
        local transit = self.transit
        if transit ~= nil and (transit.sent == nil or GetTime() - transit.sent >= TUNING.SPIDERKINGDOM.MAIL_SHARD_RESEND) then
            self:SendParcel()
        end
        return
    elseif self.phase == "quarantine" then
        if self.quarantine == nil or GetRegistry():IsReceiptDurable(self.quarantine.id) then
            self:OnArrive()
        end
        return
    end
    if self.phase == "stranded" then
        if Land(self, self.stranded_at or inst:GetPosition()) then
            self.stranded_at = nil
            self.phase = "waiting"
            self.wait_left = TUNING.SPIDERKINGDOM.MAIL_WAIT_TIME
        end
        return
    end
    if self.phase ~= "waiting" then
        return
    end
    if inst.components.inventoryitem ~= nil and inst.components.inventoryitem:IsHeld() then
        return
    end
    if inst.components.health ~= nil and inst.components.health:IsDead() then
        return
    end

    local owner = self:GetOwner()
    local tuning = TUNING.SPIDERKINGDOM
    if owner ~= nil and owner:IsValid() and not owner:HasTag("playerghost")
        and inst:GetDistanceSqToInst(owner) <= tuning.MAIL_REJOIN_DIST * tuning.MAIL_REJOIN_DIST then
        Rejoin(self, owner)
        return
    end

    self.wait_left = self.wait_left - 2
    local delivered = self.had_cargo and not ContainerHasItems(inst)
    if not (delivered or not self.had_cargo or self.wait_left <= 0) then
        return
    end
    if inst.components.container ~= nil and inst.components.container:IsOpen() then
        return -- someone is still taking things out
    end
    if owner ~= nil and owner:IsValid() then
        self:StartReturn(owner)
    elseif IsForeign(self) then
        self:ShipHome()
    end
end

function Courier:OnSave()
    if self.packing then
        -- The record that crosses to another shard: no origin, no transit, the far side's phase.
        return {
            owner = self.owner_userid,
            phase = "arriving",
            next = self.transit ~= nil and self.transit.next or nil,
            had_cargo = self.had_cargo or nil,
            home = self.home,
        }
    end
    if self.owner_userid ~= nil or self.phase ~= "idle" then
        local origin = self.origin
        local transit = self.transit
        if transit ~= nil then
            transit.mark = MailShard.MarkSave(transit.mark) -- this world save holds the transit state
        end
        local quarantine = self.quarantine
        return {
            owner = self.owner_userid,
            phase = self.phase ~= "idle" and self.phase or nil,
            portal = self.portal,
            home = self.home,
            ap = self.arrived_portal,
            tid = transit ~= nil and transit.id or nil,
            tworld = transit ~= nil and transit.world or nil,
            tportal = transit ~= nil and transit.portal or nil,
            tnext = transit ~= nil and transit.next or nil,
            qid = quarantine ~= nil and quarantine.id or nil,
            qportal = quarantine ~= nil and quarantine.portal or nil,
            next = self.arrive_next,
            wait_left = self.wait_left > 0 and self.wait_left or nil,
            had_cargo = self.had_cargo or nil,
            ox = origin ~= nil and origin.x or nil,
            oz = origin ~= nil and origin.z or nil,
            sx = self.stranded_at ~= nil and self.stranded_at.x or nil,
            sz = self.stranded_at ~= nil and self.stranded_at.z or nil,
        }
    end
end

-- Also called from the prefab's OnPreLoad, before mapdeliverable resumes a flight (component load
-- order is not fixed), so OnStartDelivery knows whether the flight goes out or back.
function Courier:OnLoad(data)
    if data == nil then
        return
    end
    self.owner_userid = data.owner or self.owner_userid
    self.phase = data.phase or "idle"
    self.wait_left = data.wait_left or 0
    self.had_cargo = data.had_cargo or false
    self.origin = data.ox ~= nil and Vector3(data.ox, 0, data.oz) or nil
    self.portal = data.portal
    self.home = data.home
    self.arrived_portal = data.ap
    self.arrive_next = data.next
    if self.phase ~= "idle" then
        self.inst:AddTag("sk_away")
        if self.inst.components.follower ~= nil then
            self.inst.components.follower:ClearCachedPlayerLeader()
        end
    end
    if self.phase == "waiting" then
        StartTask(self)
    elseif self.phase == "transit" then
        if data.tid ~= nil and data.tworld ~= nil then
            -- Saved while crossing: hide again and keep sending the same parcel (the other shard
            -- recognises its id if it already has the courier).
            self.transit = { id = data.tid, world = data.tworld, portal = data.tportal, next = data.tnext, mark = MailShard.DURABLE }
            GetRegistry():Register(data.tid, self.inst)
            StartTask(self)
        else
            self.phase = "waiting"
            StartTask(self)
        end
        self.inst:DoTaskInTime(0, function(inst)
            if self.phase == "transit" and not inst:IsInLimbo() then
                inst:RemoveFromScene()
            end
        end)
    elseif self.phase == "quarantine" then
        -- Saved while its receipt was not on disk yet: the receipt is in the same save, so it is now.
        self.quarantine = data.qid ~= nil and { id = data.qid, portal = data.qportal } or nil
        self.inst:DoTaskInTime(0, function(inst)
            if self.phase == "quarantine" and not inst:IsInLimbo() then
                inst:RemoveFromScene()
            end
        end)
        StartTask(self)
    elseif self.phase == "stranded" then
        -- Saved while hidden with nowhere to land: hide again and keep retrying.
        self.stranded_at = data.sx ~= nil and Vector3(data.sx, 0, data.sz) or nil
        self.inst:DoTaskInTime(0, function(inst)
            if self.phase == "stranded" and not inst:IsInLimbo() then
                inst:RemoveFromScene()
            end
        end)
        StartTask(self)
    end
end

function Courier:OnRemoveFromEntity()
    StopTask(self)
    if self.transit ~= nil then
        GetRegistry():Unregister(self.transit.id)
    end
end

function Courier:GetDebugString()
    return string.format("phase: %s, owner: %s, wait: %.0f, home: %s, portal: %s, arrived: %s, parcel: %s",
        tostring(self.phase), tostring(self.owner_userid), self.wait_left, tostring(self.home), tostring(self.portal),
        tostring(self.arrived_portal), tostring(self.transit ~= nil and self.transit.id or nil))
end

return Courier
