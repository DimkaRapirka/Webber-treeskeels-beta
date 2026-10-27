-- sk_royalthrone (server only): R2 Royal Throne. Holds at most one Spider Queen as a save record.
--
-- The queen inside does not exist as an entity: StoreQueen takes her GetSaveRecord() and removes her in
-- the same call, ReleaseQueen spawns her back with SpawnSaveRecord and clears the record in the same
-- call (same pattern as the official deerclopsspawner storing its hassler). So she persists with the
-- throne's save, is never duplicated, and cannot give birth or plant dens while inside.
-- Every way the throne goes away releases her alive: hammer, fire (on ignite), deconstruction,
-- console removal ("onremove" fallback below).
--
-- API for later skills (R3 workshop, R4 expedition, Affinity rituals):
--   HasQueen(), GetQueenRecord(), GetVariant() / SetVariant(v), IsOccupied(), CanAcceptQueen(),
--   StoreQueen(queen) -> bool, ReleaseQueen(pt) -> queen or nil, GetOwner(), IsOwner(player).
-- Events on the throne: "sk_thronechanged" { instant = bool } (visuals), "sk_queenstored" { },
-- "sk_queenreleased" { queen = queen }.
--
-- R3 Royal Workshop: every queen / owner change re-evaluates the workshop (royalty/workshops.lua), which
-- adds or removes the official prototyper component. It is never saved: on load the owner is offline,
-- and his R3 handler opens the workshop again when he logs in.
--
-- R4 Royal Expedition (royalty/expeditions.lua): the queen can leave with the owner. The throne then has
-- no record (HasQueen() is false, so the R3 workshop closes) but keeps the saved "away" mark: it stays
-- occupied for invitations, and she comes back into it. The queen herself lives in the owner's save
-- (components/sk_spiderkeeper.lua), never in two places: ReleaseQueen(pt, true) spawns her and sets the
-- mark in one call, StoreQueen clears it in the same call that removes her.
--   IsAway(), HasAwayMark(), ClearAway(), ValidateAway(), CanStoreQueen(queen).
--
-- Affinity rituals (affinity/rituals.lua, affinity/rituals_common.lua):
--   * the queen's variant is NOT a throne field: it is her own component (components/sk_queenvariant.lua)
--     and so part of her save record. GetVariant / SetVariant read and write record.data.sk_queenvariant,
--     the table that component's OnSave produces and its OnLoad reads when ReleaseQueen spawns her
--     (entityscript.lua:1906 GetPersistData / :1957 SetPersistData). Old saves with the former "variant"
--     field are moved into the record on load;
--   * ritual progress per side is saved here: GetRitualCount / AddRitualCount / ClearRitual;
--     DropRitualMaterials gives the offered materials back (hammer / burnt / Deconstruction Staff, prefabs/sk_royal_throne.lua);
--   * the owner's userid is mirrored into the prefab's net_string (Thrones.GetOwnerId) for the client.

local Thrones = require("spiderkingdom/royalty/thrones")
local Workshops = require("spiderkingdom/royalty/workshops")
local Rituals = require("spiderkingdom/affinity/rituals_common")

-- Name of the queen's variant component = its key in record.data (entityscript.lua GetPersistData).
local VARIANT_COMPONENT = "sk_queenvariant"

local function OnThroneRemoved(inst)
    local self = inst.components.sk_royalthrone
    if self ~= nil then
        -- Last resort for removals that skip the prefab's own release (deconstruction, c_remove...).
        self:ReleaseQueen()
        Thrones.Unregister(inst, self.owner)
    end
end

local RoyalThrone = Class(function(self, inst)
    self.inst = inst
    self.owner = nil    -- builder userid
    self.record = nil   -- save record of the queen inside (her Affinity variant is in it, see GetVariant)
    self.incoming = nil -- queen walking here after an invitation (not saved, see OnSave)
    self.away = nil     -- R4: this throne's queen is out with the owner (saved)
    self.ritual = nil   -- Affinity rituals: { [variant] = { [material prefab] = count } } (saved)

    inst:ListenForEvent("onremove", OnThroneRemoved)
end)

function RoyalThrone:OnRemoveFromEntity()
    self.inst:RemoveEventCallback("onremove", OnThroneRemoved)
    Thrones.Unregister(self.inst, self.owner)
    -- The component is already gone from inst.components here: this closes the workshop.
    Workshops.RefreshThrone(self.inst, false)
end

-- Owner ------------------------------------------------------------------------------------------

function RoyalThrone:SetOwner(userid)
    if self.owner ~= nil and self.owner ~= userid then
        Thrones.Unregister(self.inst, self.owner)
    end
    self.owner = userid
    Thrones.Register(self.inst, userid)
    if self.inst._sk_owner ~= nil then
        self.inst._sk_owner:set(userid or "")
    end
    Workshops.RefreshThrone(self.inst)
end

function RoyalThrone:GetOwner()
    return self.owner
end

function RoyalThrone:IsOwner(player)
    return player ~= nil and self.owner ~= nil and player.userid == self.owner
end

-- Called by EntityScript:OnBuilt when the recipe places the throne.
function RoyalThrone:OnBuilt(builder)
    if builder ~= nil and builder.userid ~= nil then
        self:SetOwner(builder.userid)
    end
end

-- State ------------------------------------------------------------------------------------------

function RoyalThrone:HasQueen()
    return self.record ~= nil
end

-- Read-only use please: the record is spawned exactly once, by ReleaseQueen.
function RoyalThrone:GetQueenRecord()
    return self.record
end

local function GetRecordVariant(record)
    local data = record ~= nil and record.data or nil
    local saved = type(data) == "table" and data[VARIANT_COMPONENT] or nil
    return type(saved) == "table" and saved.variant or nil
end

-- Writes the variant into the record as the queen's own component data would be (nil clears it).
local function SetRecordVariant(record, variant)
    if type(record.data) ~= "table" then
        record.data = {}
    end
    record.data[VARIANT_COMPONENT] = variant ~= nil and { variant = variant } or nil
end

-- Affinity variant of the queen inside ("lunar" / "shadow"), or nil.
function RoyalThrone:GetVariant()
    return GetRecordVariant(self.record)
end

-- Affinity rituals: changes the variant of the queen inside. Returns true on success.
function RoyalThrone:SetVariant(variant)
    if self.record == nil or (variant ~= nil and not Rituals.IsValidVariant(variant)) then
        return false
    end
    SetRecordVariant(self.record, variant)
    -- The R3 workshop's tech level depends on it (royalty/workshops.lua).
    Workshops.RefreshThrone(self.inst)
    self.inst:PushEvent("sk_queenvariantchanged", { variant = variant })
    return true
end

-- Affinity rituals: progress ------------------------------------------------------------------------

function RoyalThrone:GetRitualCount(variant, prefab)
    local side = self.ritual ~= nil and self.ritual[variant] or nil
    return side ~= nil and side[prefab] or 0
end

function RoyalThrone:AddRitualCount(variant, prefab, count)
    self.ritual = self.ritual or {}
    local side = self.ritual[variant]
    if side == nil then
        side = {}
        self.ritual[variant] = side
    end
    side[prefab] = (side[prefab] or 0) + count
end

function RoyalThrone:ClearRitual(variant)
    if self.ritual ~= nil then
        self.ritual[variant] = nil
        if next(self.ritual) == nil then
            self.ritual = nil
        end
    end
end

-- Gives every material offered so far back, next to the throne, and clears all progress.
function RoyalThrone:DropRitualMaterials()
    local ritual = self.ritual
    self.ritual = nil
    if ritual == nil then
        return
    end
    local lootdropper = self.inst.components.lootdropper
    local x, y, z = self.inst.Transform:GetWorldPosition()
    for _, side in pairs(ritual) do
        for prefab, count in pairs(side) do
            while count > 0 do
                local item = SpawnPrefab(prefab)
                if item == nil then
                    break
                end
                local stackable = item.components.stackable
                local n = stackable ~= nil and math.min(count, stackable.maxsize) or 1
                if stackable ~= nil and n > 1 then
                    stackable:SetStackSize(n)
                end
                count = count - n
                if lootdropper ~= nil then
                    lootdropper:FlingItem(item)
                else
                    item.Transform:SetPosition(x, 0, z)
                end
            end
        end
    end
end

-- Queen inside, on her way in, or out with the owner (R4).
function RoyalThrone:IsOccupied()
    return self.record ~= nil or (self.incoming ~= nil and self.incoming:IsValid()) or self:IsAway()
end

-- R4: the raw mark, as saved. Only royalty/expeditions.lua uses it to find her home.
function RoyalThrone:HasAwayMark()
    return self.away == true
end

-- R4: the queen of this throne is out with the owner (the mark, unless it is stale, royalty/thrones.lua).
function RoyalThrone:IsAway()
    return self.away == true and not Thrones.IsAwayStale(self.owner)
end

function RoyalThrone:CanAcceptQueen()
    return not self:IsOccupied() and Thrones.IsUsable(self.inst)
end

function RoyalThrone:SetIncoming(queen)
    self.incoming = queen
end

function RoyalThrone:ClearIncoming(queen)
    if queen == nil or self.incoming == queen then
        self.incoming = nil
    end
end

local function OnChanged(self, instant)
    if self.record ~= nil then
        self.inst:AddTag(Thrones.OCCUPIED_TAG)
    else
        self.inst:RemoveTag(Thrones.OCCUPIED_TAG)
    end
    if self.away then
        self.inst:AddTag(Thrones.AWAY_TAG)
    else
        self.inst:RemoveTag(Thrones.AWAY_TAG)
    end
    -- Before the visual event, so the throne's tint already knows the workshop state.
    Workshops.RefreshThrone(self.inst)
    self.inst:PushEvent("sk_thronechanged", { instant = instant })
end

-- R4: the queen is no longer out (she died, went wild, or the throne burns). No effect on a record.
function RoyalThrone:ClearAway()
    if self.away then
        self.away = nil
        OnChanged(self, true)
    end
end

-- R4: drops a stale "away" mark (royalty/thrones.lua IsAwayStale).
function RoyalThrone:ValidateAway()
    if self.away and Thrones.IsAwayStale(self.owner) then
        self:ClearAway()
    end
end

-- Store / release --------------------------------------------------------------------------------

-- Whether StoreQueen(queen) would succeed right now.
function RoyalThrone:CanStoreQueen(queen)
    if self.record ~= nil
        or not Thrones.IsUsable(self.inst)
        or queen == nil or not queen:IsValid()
        or queen.prefab ~= Thrones.QUEEN_PREFAB
        or queen:IsInLimbo()
        or (queen.components.health ~= nil and queen.components.health:IsDead()) then
        return false
    end
    if self.incoming ~= nil and self.incoming ~= queen and self.incoming:IsValid() then
        return false
    end
    return true
end

-- Takes a live queen into the throne. Returns true on success; the queen entity is removed.
-- An R4 queen coming home must have ended her expedition first (royalty/expeditions.lua Finish), so the
-- record holds no follower or owner data.
function RoyalThrone:StoreQueen(queen)
    if not self:CanStoreQueen(queen) then
        return false
    end
    self.incoming = nil

    -- Detach her from the world first, so the record holds no references to other entities.
    if queen.components.leader ~= nil then
        queen.components.leader:RemoveAllFollowers()
    end
    if queen.components.combat ~= nil then
        queen.components.combat:DropTarget()
    end
    if queen.components.burnable ~= nil and queen.components.burnable:IsBurning() then
        queen.components.burnable:Extinguish()
    end
    if queen.components.freezable ~= nil and queen.components.freezable:IsFrozen() then
        queen.components.freezable:Unfreeze()
    end

    local record = queen:GetSaveRecord()
    if record == nil then
        return false
    end
    self.record = record -- her variant (sk_queenvariant) is in record.data
    self.away = nil -- R4: she is back
    queen:Remove()

    OnChanged(self, false)
    self.inst:PushEvent("sk_queenstored")
    return true
end

local function FindReleasePoint(inst)
    local x, y, z = inst.Transform:GetWorldPosition()
    local radius = TUNING.SPIDERKINGDOM.ROYAL_THRONE_RELEASE_RADIUS
    local map = TheWorld.Map
    local offset = FindWalkableOffset(Vector3(x, 0, z), math.random() * TWOPI, radius, 12, true, false)
        or FindValidPositionByFan(math.random() * TWOPI, radius, 12, function(o)
            return map:IsPassableAtPoint(x + o.x, 0, z + o.z)
        end)
    if offset ~= nil then
        return Vector3(x + offset.x, 0, z + offset.z)
    end
    return Vector3(x, 0, z)
end

-- Lets the queen out next to the throne (or at pt). Returns the queen, or nil if there was none.
-- away: R4, she leaves with the owner and the throne keeps her place (set in the same call as the spawn).
function RoyalThrone:ReleaseQueen(pt, away)
    local record = self.record
    if record == nil then
        return nil
    end

    local queen = SpawnSaveRecord(record)
    if queen == nil then
        -- Never lose her: a fresh queen is better than none (her saved state is lost).
        queen = SpawnPrefab(record.prefab or Thrones.QUEEN_PREFAB)
        if queen == nil then
            print("[SpiderKingdom] Royal Throne: failed to release the queen, record kept.")
            return nil
        end
    end

    -- Cleared in the same call as the spawn: the record can never produce a second queen.
    self.record = nil
    self.away = away and true or nil

    pt = pt or FindReleasePoint(self.inst)
    if queen.Physics ~= nil then
        queen.Physics:Teleport(pt.x, 0, pt.z)
    else
        queen.Transform:SetPosition(pt.x, 0, pt.z)
    end
    queen:ForceFacePoint(self.inst.Transform:GetWorldPosition())
    if queen.sg ~= nil and queen.sg:HasState("birth") then
        queen.sg:GoToState("birth")
    end

    OnChanged(self, false)
    self.inst:PushEvent("sk_queenreleased", { queen = queen })
    return queen
end

-- Save -------------------------------------------------------------------------------------------

-- A queen still walking here is saved by the world as a wild queen, and the walk itself is not
-- saved. The invitation already spent on her is saved instead and handed back on load
-- (no duplicate: a save after she moved in has no pending invitation, only her record).
-- R4: the "away" mark is saved unless it is stale; the queen herself is in the owner's save.
function RoyalThrone:OnSave()
    local pending = self.record == nil and self.incoming ~= nil and self.incoming:IsValid() or nil
    local away = self.record == nil and self:IsAway() or nil
    if self.owner == nil and self.record == nil and not pending and not away and self.ritual == nil then
        return
    end
    return
    {
        owner = self.owner,
        queen = self.record,
        pending_invitation = pending,
        away = away,
        ritual = self.ritual,
    }
end

local function RefundPendingInvitation(inst)
    local item = SpawnPrefab(Thrones.INVITATION_PREFAB)
    if item ~= nil then
        local x, y, z = inst.Transform:GetWorldPosition()
        if item.components.inventoryitem ~= nil then
            item.components.inventoryitem:DoDropPhysics(x, 0, z, true)
        else
            item.Transform:SetPosition(x, 0, z)
        end
    end
end

function RoyalThrone:OnLoad(data)
    if data == nil then
        return
    end
    if data.owner ~= nil then
        self:SetOwner(data.owner)
    end
    if type(data.queen) == "table" and data.queen.prefab ~= nil then
        self.record = data.queen
        -- Saves from before the variant component kept it in a throne field.
        if Rituals.IsValidVariant(data.variant) and GetRecordVariant(self.record) == nil then
            SetRecordVariant(self.record, data.variant)
        end
    elseif data.away then
        self.away = true
    end
    if type(data.ritual) == "table" then
        for variant, side in pairs(data.ritual) do
            if Rituals.IsValidVariant(variant) and type(side) == "table" then
                for prefab, count in pairs(side) do
                    if type(count) == "number" and count > 0 then
                        self:AddRitualCount(variant, prefab, count)
                    end
                end
            end
        end
    end
    if data.pending_invitation then
        -- Next frame, once the world has finished loading.
        self.inst:DoTaskInTime(0, RefundPendingInvitation)
    end
    OnChanged(self, true)
end

function RoyalThrone:GetDebugString()
    return string.format("owner: %s, queen: %s, variant: %s, incoming: %s, away: %s, ritual: %s",
        tostring(self.owner), tostring(self.record ~= nil), tostring(self:GetVariant()), tostring(self.incoming),
        tostring(self.away), tostring(self.ritual ~= nil))
end

return RoyalThrone
