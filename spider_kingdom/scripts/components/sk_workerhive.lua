-- sk_workerhive (server only, on spider dens): K3 Worker Brood. A den with the lumber or farm role
-- (K2) whose owner is online with K3 (tag "sk_workforce", colony/ownership.lua) raises worker spiders
-- and leads them. Workers are stock "spider" prefabs with an active sk_worker component; the den is
-- their leader, so the stock Leader:OnSave / LoadPostPass keeps the link across saves.
-- K4 Web Logistics: a storage den whose owner is online with K4 (tag "sk_logistics") raises haulers
-- the same way (profession "hauler", colony/network.lua). K6 Colony Heart: a paused network stops
-- every profession (Network.IsPaused).

local DenRoles = require("spiderkingdom/data/den_roles")
local Network = require("spiderkingdom/colony/network")

local SPAWN_PERIOD = 10

-- den role -> worker profession, and the owner's skill tag it needs (colony/ownership.lua)
local PROFESSION_BY_ROLE = { lumber = "lumber", farm = "farm", storage = "hauler" }
local SKILL_TAG = { lumber = "sk_workforce", farm = "sk_workforce", hauler = "sk_logistics" }

local WorkerHive = Class(function(self, inst)
    self.inst = inst
    self.spawn_time_left = 0

    if inst.components.leader == nil then
        inst:AddComponent("leader")
    end

    self.task = inst:DoPeriodicTask(SPAWN_PERIOD, function() self:Tick() end, math.random() * SPAWN_PERIOD)
end)

function WorkerHive:GetProfession()
    local role = DenRoles.GetRoleOfDen(self.inst)
    return role ~= nil and PROFESSION_BY_ROLE[role] or nil
end

function WorkerHive:IsUsable()
    local inst = self.inst
    return inst:IsValid() and not inst:HasTag("burnt")
        and not (inst.components.health ~= nil and inst.components.health:IsDead())
end

-- Workers work in daylight only, while the owner has the skill, the den keeps its role and the
-- den's Colony Heart network (if any) is not paused.
function WorkerHive:IsWorking()
    local profession = self:GetProfession()
    return profession ~= nil
        and self:IsUsable()
        and self.inst:HasTag(SKILL_TAG[profession])
        and TheWorld.state.isday
        and not Network.IsPaused(self.inst)
end

function WorkerHive:GetMaxWorkers()
    local growable = self.inst.components.growable
    local stage = growable ~= nil and math.clamp(growable:GetStage(), 1, 3) or 1
    local tuning = TUNING.SPIDERKINGDOM
    local per_stage = self:GetProfession() == "hauler" and tuning.HAULERS_PER_STAGE or tuning.WORKERS_PER_STAGE
    return per_stage[stage] or 0
end

function WorkerHive:SpawnWorker()
    local inst = self.inst
    local spider = SpawnPrefab("spider")
    if spider == nil or spider.components.sk_worker == nil then
        if spider ~= nil then
            spider:Remove()
        end
        return
    end

    local x, y, z = inst.Transform:GetWorldPosition()
    local offset = FindWalkableOffset(inst:GetPosition(), math.random() * TWOPI, 2, 8, true, false)
    if offset ~= nil then
        x, z = x + offset.x, z + offset.z
    end
    spider.Transform:SetPosition(x, 0, z)

    spider.components.sk_worker:Activate()
    inst.components.leader:AddFollower(spider)

    local fx = SpawnPrefab("spawn_fx_small")
    if fx ~= nil then
        fx.Transform:SetPosition(x, 0, z)
    end
    inst.SoundEmitter:PlaySound("dontstarve/creatures/spider/spider_egg_sack")
end

-- Any free slot the den's role may use (K2 limits non-storage roles to the first slots).
function WorkerHive:HasRoom()
    local container = self.inst.components.container
    local denrole = self.inst.components.sk_denrole
    if container == nil or denrole == nil then
        return false
    end
    for slot = 1, denrole:GetAllowedSlots() do
        if container:GetItemInSlot(slot) == nil then
            return true
        end
    end
    return false
end

-- The den shrank (shaving, queen reset): retire the workers above the new limit.
function WorkerHive:ReconcileWorkers()
    local excess = self:CountWorkers() - self:GetMaxWorkers()
    if excess <= 0 then
        return
    end
    for follower in pairs(self.inst.components.leader.followers) do
        if excess <= 0 then
            break
        end
        local worker = follower.components.sk_worker
        if worker ~= nil and worker:IsActive() and not worker.retiring then
            worker:Retire()
            excess = excess - 1
        end
    end
end

function WorkerHive:CountWorkers()
    local count = 0
    for follower in pairs(self.inst.components.leader.followers) do
        local worker = follower.components.sk_worker
        if worker ~= nil and worker:IsActive() and not worker.retiring then
            count = count + 1
        end
    end
    return count
end

function WorkerHive:Tick()
    self:ReconcileWorkers()
    if not self:IsWorking() then
        return
    end
    if self:CountWorkers() < self:GetMaxWorkers() then
        self.spawn_time_left = self.spawn_time_left - SPAWN_PERIOD
        if self.spawn_time_left <= 0 then
            self.spawn_time_left = TUNING.SPIDERKINGDOM.WORKER_SPAWN_TIME
            self:SpawnWorker()
        end
    end
end

-- Hands an item to the den's container. Returns true if all of it was taken; what does not fit is
-- returned to the caller (never dropped).
function WorkerHive:Store(item)
    local container = self.inst.components.container
    if container == nil or not self:IsUsable() then
        return false, item
    end
    if container:GiveItem(item, nil, nil, false) then
        return true, nil
    end
    return false, item:IsValid() and item or nil
end

function WorkerHive:OnSave()
    if self.spawn_time_left > 0 then
        return { spawn_time_left = self.spawn_time_left }
    end
end

function WorkerHive:OnLoad(data)
    if data ~= nil and data.spawn_time_left ~= nil then
        self.spawn_time_left = data.spawn_time_left
    end
end

function WorkerHive:OnRemoveFromEntity()
    if self.task ~= nil then
        self.task:Cancel()
        self.task = nil
    end
end

function WorkerHive:GetDebugString()
    return string.format("profession: %s, working: %s, workers: %d/%d, next spawn: %.0f",
        tostring(self:GetProfession()), tostring(self:IsWorking()), self:CountWorkers(), self:GetMaxWorkers(), self.spawn_time_left)
end

return WorkerHive
