-- K2 Spider Architecture: den roles (see components/sk_denrole.lua, data/den_roles.lua).
--   * every spiderden (all stages share the prefab name "spiderden") gets a 9-slot container at
--     construction, so clients have the replica; it opens only once a role is assigned;
--   * Webber with the skill assigns a role by using a marker item on his den (SK_SETDENROLE);
--   * name and tint show the role; living / guard bonuses wrap the official childspawner setters.

local _G = GLOBAL
local DenRoles = require("spiderkingdom/data/den_roles")
local SKUtil = require("spiderkingdom/util")

local SKILL = "webber_sk_colony_architecture"

local GetRoleOfDen = DenRoles.GetRoleOfDen

local function GetAllowedSlotsOfDen(den)
    local role = GetRoleOfDen(den)
    local data = role ~= nil and DenRoles.ROLES[role] or nil
    return data ~= nil and data.slots or 0
end

-- Container widget ---------------------------------------------------------------------------

local containers = require("containers")

local den_params =
{
    widget =
    {
        slotpos = {},
        animbank = "ui_chest_3x3",
        animbuild = "ui_chest_3x3",
        pos = _G.Vector3(0, 200, 0),
        side_align_tip = 160,
    },
    type = "chest",
    -- Runs on server and client (container_replica:CanTakeItemInSlot). Non-storage roles use the first
    -- slots only. Automatic insertion (slot == nil) is limited by the GiveItem wrapper below.
    itemtestfn = function(container, item, slot)
        local allowed = GetAllowedSlotsOfDen(container.inst)
        return allowed > 0 and (slot == nil or slot <= allowed)
    end,
}

for y = 2, 0, -1 do
    for x = 0, 2 do
        table.insert(den_params.widget.slotpos, _G.Vector3(80 * x - 80 * 2 + 80, 80 * y - 80 * 2 + 80, 0))
    end
end

containers.params.spiderden = den_params
containers.MAXITEMSLOTS = math.max(containers.MAXITEMSLOTS, DenRoles.CONTAINER_SLOTS)

-- Vanilla GiveItem with slot == nil picks any empty slot without re-checking itemtestfn per slot
-- (components/container.lua). Keep automatic insertion (STORE, couriers, loading) inside the allowed range.
local function FindAllowedSlot(container, item, allowed)
    local stackable = item.components.stackable
    if stackable ~= nil and container.acceptsstacks then
        for slot = 1, allowed do
            local other = container.slots[slot]
            if other ~= nil and stackable:CanStackWith(other) and not other.components.stackable:IsFull() then
                return slot
            end
        end
    end
    for slot = 1, allowed do
        if container.slots[slot] == nil then
            return slot
        end
    end
end

local function IsDenClosed(den)
    return den._sk_dead or (den.components.health ~= nil and den.components.health:IsDead())
end

local function LimitGiveItem(container)
    local GiveItem = container.GiveItem
    container.GiveItem = function(self, item, slot, src_pos, drop_on_fail, ...)
        if item == nil or item.components.inventoryitem == nil then
            return GiveItem(self, item, slot, src_pos, drop_on_fail, ...)
        end

        -- A dead den is no longer saved (persists = false): refuse late inserts, e.g. a buffered STORE.
        -- A slot past the end makes vanilla take its refusal path, which drops the item on the ground.
        if IsDenClosed(self.inst) then
            return GiveItem(self, item, self.numslots + 1, src_pos, drop_on_fail, ...)
        end

        local allowed = GetAllowedSlotsOfDen(self.inst)
        if allowed >= self.numslots then
            return GiveItem(self, item, slot, src_pos, drop_on_fail, ...)
        end

        if slot ~= nil then
            if slot > allowed or self.slots[slot] == nil then
                -- Out of range: vanilla refuses it. Empty allowed slot: vanilla places it there.
                return GiveItem(self, item, slot, src_pos, drop_on_fail, ...)
            end
            -- Occupied allowed slot: vanilla would fall back to any empty slot, so stack here if
            -- possible and place the rest inside the allowed range below.
            local other = self.slots[slot]
            if item.components.stackable ~= nil and self.acceptsstacks
                and item.components.stackable:CanStackWith(other) and not other.components.stackable:IsFull() then
                item = other.components.stackable:Put(item, src_pos)
                if item == nil then
                    return true
                end
            end
        end

        while true do
            local target = FindAllowedSlot(self, item, allowed)
            if target == nil then
                -- A disallowed slot makes vanilla take its normal refusal path (including drop_on_fail).
                return GiveItem(self, item, allowed + 1, src_pos, drop_on_fail, ...)
            end
            local other = self.slots[target]
            if other == nil then
                return GiveItem(self, item, target, src_pos, drop_on_fail, ...)
            end
            item = other.components.stackable:Put(item, src_pos)
            if item == nil then
                return true
            end
        end
    end
end

-- Den post-init ------------------------------------------------------------------------------

local function GetDisplayName(inst)
    local name = _G.STRINGS.NAMES.SPIDERDEN
    local role = GetRoleOfDen(inst)
    local rolename = role ~= nil and _G.STRINGS.SK_DENROLE_NAMES[string.upper(role)] or nil
    return rolename ~= nil and (name.." ("..rolename..")") or name
end

-- Never lose stored items. "death" comes first: a dead den gets persists = false
-- (components/health.lua) and would not be saved before it is removed.
local function DropContents(inst)
    local container = inst.components.container
    if container ~= nil then
        container.canbeopened = false
        container:Close()
        container:DropEverything()
    end
end

local function OnDenDeath(inst)
    inst._sk_dead = true
    DropContents(inst)
end

-- "spiderden" covers spiderden_2 / spiderden_3 too: they call SetPrefabName("spiderden") and
-- SpawnPrefab runs the post-inits registered for inst.prefab (mainfunctions.lua).
AddPrefabPostInit("spiderden", function(inst)
    inst.displaynamefn = GetDisplayName

    if not _G.TheWorld.ismastersim then
        return
    end

    inst:AddComponent("container")
    inst.components.container:WidgetSetup("spiderden")
    inst.components.container.canbeopened = false
    LimitGiveItem(inst.components.container)

    inst:AddComponent("sk_denrole")

    -- Bonuses follow the official per-stage values (SetStage in prefabs/spiderden.lua).
    local childspawner = inst.components.childspawner
    if childspawner ~= nil then
        local SetMaxChildren = childspawner.SetMaxChildren
        childspawner.SetMaxChildren = function(self, max, ...)
            return SetMaxChildren(self, inst.components.sk_denrole:ApplyMaxChildren(max), ...)
        end
        local SetMaxEmergencyChildren = childspawner.SetMaxEmergencyChildren
        childspawner.SetMaxEmergencyChildren = function(self, max, ...)
            return SetMaxEmergencyChildren(self, inst.components.sk_denrole:ApplyMaxEmergency(max), ...)
        end
    end

    -- Role tags must exist before the container loads (see components/sk_denrole.lua).
    local OnPreLoad = inst.OnPreLoad
    inst.OnPreLoad = function(inst, data, ...)
        if OnPreLoad ~= nil then
            OnPreLoad(inst, data, ...)
        end
        if data ~= nil then
            local denrole = inst.components.sk_denrole
            denrole:OnPreLoadRole(data.sk_denrole)
            if data.childspawner ~= nil then
                denrole.saved_inside = data.childspawner.childreninside
                denrole.saved_emergency = data.childspawner.emergencychildreninside
            end
        end
    end

    inst:ListenForEvent("death", OnDenDeath)
    inst:ListenForEvent("onremove", DropContents)
end)

-- Assign-role action ------------------------------------------------------------------------

local SK_SETDENROLE = _G.Action({ priority = 1, mount_valid = false })
SK_SETDENROLE.id = "SK_SETDENROLE"
SK_SETDENROLE.str = _G.STRINGS.ACTIONS.SK_SETDENROLE
SK_SETDENROLE.fn = function(act)
    local doer, den, item = act.doer, act.target, act.invobject
    if doer == nil or den == nil or item == nil or den.components.sk_denrole == nil then
        return false
    end
    if not SKUtil.HasSkill(doer, SKILL) then
        return false
    end
    local role = DenRoles.ROLE_BY_ITEM[item.prefab]
    if role == nil or den:HasTag("burnt") then
        return false
    end
    if not den.components.sk_denrole:IsOwner(doer) then
        return false, "NOTOWNER"
    end
    if den.components.sk_denrole:GetRole() == role then
        return false, "SAMEROLE"
    end

    -- Consume one marker (same pattern as spidereggsack ondeploy).
    local used = item.components.stackable ~= nil and item.components.stackable:Get() or item
    used:Remove()

    den.components.sk_denrole:SetRole(role, doer)
    return true
end
AddAction(SK_SETDENROLE)

-- Client collectors live in networking/item_actions.lua (USEITEM: SK_SETDENROLE, STORE suppression)
-- and networking/sleep_actions.lua (SCENE: left click opens a den with a role): a mod can register
-- only one collector per component and action type.

AddStategraphActionHandler("wilson", _G.ActionHandler(_G.ACTIONS.SK_SETDENROLE, "give"))
AddStategraphActionHandler("wilson_client", _G.ActionHandler(_G.ACTIONS.SK_SETDENROLE, "give"))
