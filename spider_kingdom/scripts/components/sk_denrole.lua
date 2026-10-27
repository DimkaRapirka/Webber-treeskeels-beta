-- sk_denrole (server only): K2 Spider Architecture role of one spider den.
-- One system for all roles; the role only changes tags, tint, usable slots and two stat bonuses.
-- The den's container is added for every den at construction (so clients get the replica) and can
-- only be opened once a role is assigned. Roles and contents stay when the skill is reset.
--
-- Load order matters (EntityScript:SetPersistData loads components in pairs() order):
--   * OnPreLoadRole (called from the den's OnPreLoad) sets the role tags before the container loads,
--     otherwise the container's itemtestfn would reject and drop the saved items;
--   * LoadPostPass restores the saved spider population once childspawner and growable have loaded.

local DenRoles = require("spiderkingdom/data/den_roles")
local Ownership = require("spiderkingdom/colony/ownership")

local DenRole = Class(function(self, inst)
    self.inst = inst
    self.role = nil
    self.owner_userid = nil

    -- Base values the official SetStage writes (prefabs/spiderden.lua); bonuses are applied on top.
    local childspawner = inst.components.childspawner
    self.base_maxchildren = childspawner ~= nil and childspawner.maxchildren or nil
    self.base_maxemergency = childspawner ~= nil and childspawner.maxemergencychildren or nil
end)

function DenRole:GetRole()
    return self.role
end

function DenRole:GetRoleData()
    return self.role ~= nil and DenRoles.ROLES[self.role] or nil
end

-- Number of container slots the current role may use (0 without a role).
function DenRole:GetAllowedSlots()
    local data = self:GetRoleData()
    return data ~= nil and data.slots or 0
end

function DenRole:IsOwner(doer)
    return self.owner_userid == nil or (doer ~= nil and doer.userid == self.owner_userid)
end

-- Called by the childspawner wrappers in colony/denroles.lua with the value SetStage wanted.
function DenRole:ApplyMaxChildren(base)
    self.base_maxchildren = base
    local data = self:GetRoleData()
    return base + (data ~= nil and data.extra_children or 0)
end

function DenRole:ApplyMaxEmergency(base)
    self.base_maxemergency = base
    local data = self:GetRoleData()
    local mult = data ~= nil and data.defender_mult or 1
    return math.floor(base * mult + 0.5)
end

-- Looping animations of prefabs/spiderden.lua (stage idle, frozen, thaw, someone sleeping inside).
local function GetCurrentDenAnim(inst)
    local anims = inst.anims
    if anims ~= nil then
        for _, key in ipairs({ "idle", "freeze", "thaw" }) do
            if anims[key] ~= nil and inst.AnimState:IsCurrentAnimation(anims[key]) then
                return { name = anims[key], loop = true }
            end
        end
    end
    -- Also during "cocoon_enter", which queues the sleep loop (prefabs/spiderden.lua onsleep).
    local sleepingbag = inst.components.sleepingbag
    if inst.AnimState:IsCurrentAnimation("cocoon_sleep_loop") or (sleepingbag ~= nil and sleepingbag:InUse()) then
        return { name = "cocoon_sleep_loop", loop = true }
    end
    -- One-shot animations (hits, growth) end in the stage idle anyway.
    return anims ~= nil and anims.idle ~= nil and { name = anims.idle, loop = true } or nil
end

local function RefreshTags(self)
    local inst = self.inst
    local data = self:GetRoleData()

    for role in pairs(DenRoles.ROLES) do
        if role == self.role then
            inst:AddTag(DenRoles.TAG_PREFIX..role)
        else
            inst:RemoveTag(DenRoles.TAG_PREFIX..role)
        end
    end

    -- Own model per role (Phase 6). The bank keeps every official den animation name, so the stock
    -- den code (stages, hits, spawning) plays on it; restart the stage idle after a bank change.
    local bank, build
    if data ~= nil then
        bank, build = DenRoles.BANK, data.build
    elseif self.owner_userid ~= nil then
        bank, build = DenRoles.BANK, DenRoles.BASE_BUILD
    else
        bank, build = DenRoles.STOCK_BANK, DenRoles.STOCK_BUILD
    end
    if self.bank ~= bank or self.build ~= build then
        local bank_changed = (self.bank or DenRoles.STOCK_BANK) ~= bank -- nil: still the stock bank
        local anim = bank_changed and GetCurrentDenAnim(inst) or nil
        self.bank, self.build = bank, build
        inst.AnimState:SetBank(bank)
        inst.AnimState:SetBuild(build)
        -- Bedazzling stickers: the role builds have no art of their own, use the stock den's.
        if bank == DenRoles.BANK then
            inst.AnimState:OverrideSymbol("bedazzled_flare", DenRoles.STOCK_BUILD, "bedazzled_flare")
        else
            inst.AnimState:ClearOverrideSymbol("bedazzled_flare")
        end
        if anim ~= nil then
            -- Same animation names in both banks: keep what the den was showing (idle, frozen, sleeping...).
            inst.AnimState:PlayAnimation(anim.name, anim.loop)
        end
    end

    if inst.components.container ~= nil then
        inst.components.container.canbeopened = data ~= nil
    end
end

-- Re-run the official stat setters so the bonus follows the current role. Those setters refill the
-- den (childreninside = max - outside); keep the given population instead so a role change or a load
-- does not hand out free spiders, then let childspawner re-evaluate its regen/spawn updating.
local function RefreshChildren(self, inside, emergencyinside)
    local childspawner = self.inst.components.childspawner
    if childspawner == nil then
        return
    end

    inside = inside or childspawner.childreninside
    emergencyinside = emergencyinside or childspawner.emergencychildreninside

    if self.base_maxchildren ~= nil then
        childspawner:SetMaxChildren(self.base_maxchildren)
        childspawner.childreninside = math.max(0, math.min(inside, childspawner.maxchildren - childspawner:CountChildrenOutside()))
    end
    if self.base_maxemergency ~= nil then
        childspawner:SetMaxEmergencyChildren(self.base_maxemergency)
        childspawner.emergencychildreninside = math.max(0, math.min(emergencyinside, childspawner.maxemergencychildren - childspawner.numemergencychildrenoutside))
    end

    childspawner:TryStopUpdate()
    childspawner:StartUpdate()
end

-- A role with fewer slots than the previous one: drop what no longer fits.
local function DropOverflow(self)
    local container = self.inst.components.container
    if container == nil then
        return
    end
    local allowed = self:GetAllowedSlots()
    for slot = allowed + 1, container:GetNumSlots() do
        if container:GetItemInSlot(slot) ~= nil then
            container:DropItemBySlot(slot)
        end
    end
end

function DenRole:SetRole(role, doer)
    if role ~= nil and DenRoles.ROLES[role] == nil then
        return false
    end
    self.role = role
    if doer ~= nil and doer.userid ~= nil and self.owner_userid == nil then
        self.owner_userid = doer.userid
        Ownership.Register(self.inst, self.owner_userid) -- T3 Cozy Place
    end
    RefreshTags(self)
    DropOverflow(self)
    RefreshChildren(self)
    self.inst:PushEvent("sk_denrolechanged", { role = role, doer = doer })
    return true
end

function DenRole:OnSave()
    if self.role ~= nil or self.owner_userid ~= nil then
        return { role = self.role, owner = self.owner_userid }
    end
end

local function ValidRole(role)
    return role ~= nil and DenRoles.ROLES[role] ~= nil and role or nil
end

-- From the den's OnPreLoad, before any component loads.
function DenRole:OnPreLoadRole(data)
    if data ~= nil then
        self.role = ValidRole(data.role)
        self.owner_userid = data.owner
        RefreshTags(self)
    end
end

function DenRole:OnLoad(data)
    if data ~= nil then
        self.role = ValidRole(data.role)
        self.owner_userid = data.owner
        RefreshTags(self)
        Ownership.Register(self.inst, self.owner_userid) -- T3 Cozy Place
    end
end

-- Runs after every component loaded (EntityScript:LoadPostPass). saved_inside / saved_emergency are
-- captured from the childspawner save data in the den's OnPreLoad (colony/denroles.lua).
function DenRole:LoadPostPass(newents, data)
    RefreshChildren(self, self.saved_inside, self.saved_emergency)
    self.saved_inside = nil
    self.saved_emergency = nil
end

function DenRole:GetDebugString()
    return string.format("role: %s, owner: %s, slots: %d", tostring(self.role), tostring(self.owner_userid), self:GetAllowedSlots())
end

return DenRole
