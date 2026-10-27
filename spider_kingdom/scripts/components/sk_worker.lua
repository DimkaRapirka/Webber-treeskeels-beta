-- sk_worker (server only, on every stock "spider"; inactive until a den's sk_workerhive activates it):
-- K3 Worker Brood. The worker's leader is its den. Once per second this component picks what to do;
-- a brain node (colony/workers.lua) only walks to GetMoveTarget(). Work is done here when in reach,
-- with the stock "eat" animation as a stand-in (no new animations before Phase 6):
--   lumber - chops trees (Workable:WorkedBy, CHOP only) and carries logs, cones, twigs home;
--   farm   - harvests bushes, grass, saplings, reeds and ripe crops (Pickable:Pick fills its inventory);
--   both   - deliver everything to the den's container (K2) before taking new work; a full den stops
--            the work;
--   night, lost role, owner without K3 - wait at the den;
--   retiring (the den shrank below its worker count) - deliver, then leave.
-- K4 Web Logistics - profession "hauler" (workers of a storage den): takes one stack from a production
--   den it serves and carries it to the storage den chosen by colony/network.lua (Woby's courier rule).
--   Items are only moved between containers and its own inventory, so a save at any moment holds each
--   item exactly once; cargo nobody can take is kept and the hauler waits at home (never dropped),
--   except by the stock death drop or when it despawns without a den (dropped where it stands).
--   Delivery goes on at night, while paused or without the skill; fetching needs IsWorking().
-- Workers never fight (combat wrappers in colony/workers.lua) and have no sanity aura.

local JOBS = require("spiderkingdom/data/worker_jobs")
local Network = require("spiderkingdom/colony/network")

local TICK = 1
local REACH_DIST = 2
local HOME_DIST = 3
local CLAIM_TIME = 10

local HAULER = "hauler"

-- Modes whose target is a den (the brain node keeps a den's distance) and modes that claim the target.
local DEN_MODES = { home = true, deposit = true, fetch = true, deliver = true }
local CLAIM_MODES = { work = true, pickup = true, fetch = true }

local Worker = Class(function(self, inst)
    self.inst = inst
    self.active = false
    self.retiring = false
    self.target = nil
    self.mode = nil -- "work" | "pickup" | "deposit" | "home"; haulers: "fetch" | "deliver" | "home"
    self.profession = nil
    self.work_cooldown = 0
    self.search_cooldown = 0
    self.orphan_ticks = 0
    self.task = nil
end)

function Worker:IsActive()
    return self.active
end

function Worker:GetHome()
    local follower = self.inst.components.follower
    local leader = follower ~= nil and follower:GetLeader() or nil
    return leader ~= nil and leader.components.sk_workerhive ~= nil and leader or nil
end

-- Look (Phase 6): job-coloured stripes and a job hat in the stock "swap_hat" slot of spiders (anim/sk_spider_hats.zip,
-- art_src/tools/gen_hats.py; the spider bank draws it on layer "hat", prefabs/spider.lua Show("hat")).
local HAT_BUILD = "sk_spider_hats"
local HATS = { lumber = "swap_hat_lumber", farm = "swap_hat_farm", [HAULER] = "swap_hat_hauler" }

-- Skin per profession: spider_build with job-coloured stripes shaped like the Spider Warrior's
-- (anim/sk_spider_worker_<profession>.zip, art_src/tools/gen_workers.py).
local STOCK_BUILD = "spider_build" -- prefabs/spider.lua
local BUILDS = { lumber = "sk_spider_worker_lumber", farm = "sk_spider_worker_farm", [HAULER] = "sk_spider_worker_hauler" }

local function RefreshTint(self)
    local build = self.profession ~= nil and BUILDS[self.profession] or nil
    self.inst.AnimState:SetBuild(build or STOCK_BUILD)
    local hat = self.profession ~= nil and HATS[self.profession] or nil
    if hat ~= nil then
        self.inst.AnimState:OverrideSymbol("swap_hat", HAT_BUILD, hat)
        self.inst.AnimState:Show("hat")
    else
        self.inst.AnimState:ClearOverrideSymbol("swap_hat")
    end
end

function Worker:IsHauler()
    return self.profession == HAULER
end

-- For the brain node: the current target is a den (keep a den's distance from it).
function Worker:IsGoingToDen()
    return DEN_MODES[self.mode] == true
end

function Worker:Activate()
    if self.active then
        return
    end
    local inst = self.inst
    self.active = true
    inst:AddTag("sk_worker")
    inst:AddTag("sk_nokeeper") -- never bonded to a player (sk_spiderkeeper)
    inst.no_targeting = true
    RefreshTint(self)
    if inst.components.inventoryitem ~= nil then
        inst.components.inventoryitem.canbepickedup = false
    end

    -- Every stock way to turn a spider into another entity would drop the worker state and its cargo:
    -- moon potions / full moon (halloweenmoonmutable) and the lunar corpse mutation (sg.mem.nolunarmutate).
    if inst.components.halloweenmoonmutable ~= nil then
        inst:RemoveComponent("halloweenmoonmutable")
    end
    if inst.sg ~= nil then
        inst.sg.mem.nolunarmutate = true
    end

    if self.task == nil then
        self.task = inst:DoPeriodicTask(TICK, function() self:Tick() end, math.random() * TICK)
    end
end

-- The den has more workers than it may keep: deliver what we carry, then go.
function Worker:Retire()
    self.retiring = true
end

-- Movement target for the brain node.
function Worker:GetMoveTarget()
    local target = self.target
    if target ~= nil and target:IsValid() then
        return target
    end
    return nil
end

-- Claims, so several workers do not crowd one tree -------------------------------------------

local function IsClaimedByOther(self, ent)
    local claim = ent._sk_worker_claim
    return claim ~= nil and claim.worker ~= self.inst and claim.worker:IsValid() and claim.time > GetTime()
end

local function Claim(self, ent)
    ent._sk_worker_claim = { worker = self.inst, time = GetTime() + CLAIM_TIME }
end

local function SetTarget(self, mode, target)
    if mode ~= self.mode or target ~= self.target then
        self.trip_start = GetTime()
    end
    self.mode = mode
    self.target = target
    if target ~= nil and CLAIM_MODES[mode] then
        Claim(self, target)
    end
end

-- Job rules (used both to find a target and to re-check it every tick) ------------------------

local PICKUP_MUST = { "_inventoryitem" }
local PICKUP_CANT = { "INLIMBO", "NOCLICK", "fire", "smolder", "outofreach", "heavy", "irreplaceable" }

local function IsValidPickup(job, ent)
    local item = ent.components.inventoryitem
    return job.pickup[ent.prefab] and item ~= nil and item.owner == nil and item.canbepickedup
        and not ent:IsInLimbo() and not ent:HasAnyTag(PICKUP_CANT)
end

local function IsValidChop(job, ent)
    if job.chop_must == nil or not ent:HasTag("tree") or ent:HasAnyTag(job.chop_cant) then
        return false
    end
    local workable = ent.components.workable
    return workable ~= nil and workable:CanBeWorked() and workable:GetWorkAction() == ACTIONS.CHOP
end

local function IsValidPick(job, ent)
    if job.pick_must == nil or ent:HasAnyTag(job.pick_cant) then
        return false
    end
    local pickable = ent.components.pickable
    if pickable == nil or not pickable:CanBePicked() or pickable:IsStuck() then
        return false
    end
    -- Giant crops (prefabs/farm_plants.lua is_oversized) drop heavy produce that cannot go in a den.
    if ent.is_oversized then
        return false
    end
    if job.pick_prefabs[ent.prefab] then
        return true
    end
    for _, tag in ipairs(job.pick_tags) do
        if ent:HasTag(tag) then
            return true
        end
    end
    return false
end

local function IsValidWork(job, ent)
    return IsValidChop(job, ent) or IsValidPick(job, ent)
end

local function FindNear(self, den, must, cant, test)
    local x, y, z = den.Transform:GetWorldPosition()
    local best, best_dsq = nil, nil
    for _, ent in ipairs(TheSim:FindEntities(x, 0, z, TUNING.SPIDERKINGDOM.WORKER_RADIUS, must, cant)) do
        if ent ~= self.inst and ent:IsValid() and not IsClaimedByOther(self, ent) and test(ent) then
            local dsq = self.inst:GetDistanceSqToInst(ent)
            if best_dsq == nil or dsq < best_dsq then
                best, best_dsq = ent, dsq
            end
        end
    end
    return best
end

local function FindJob(self, den, job)
    local pickup = FindNear(self, den, PICKUP_MUST, PICKUP_CANT, function(ent) return IsValidPickup(job, ent) end)
    if pickup ~= nil then
        return "pickup", pickup
    end
    if job.chop_must ~= nil then
        local tree = FindNear(self, den, job.chop_must, job.chop_cant, function(ent) return IsValidChop(job, ent) end)
        if tree ~= nil then
            return "work", tree
        end
    end
    if job.pick_must ~= nil then
        local plant = FindNear(self, den, job.pick_must, job.pick_cant, function(ent) return IsValidPick(job, ent) end)
        if plant ~= nil then
            return "work", plant
        end
    end
end

-- Helpers ------------------------------------------------------------------------------------

-- Item slots plus the "hand" slot: things that cannot go into containers land in activeitem
-- (components/inventory.lua GiveItem).
local function CountItems(inst)
    local inventory = inst.components.inventory
    if inventory == nil then
        return 0
    end
    return inventory:NumItems() + (inventory.activeitem ~= nil and 1 or 0)
end

local function DropEverything(inst)
    if inst.components.inventory ~= nil then
        inst.components.inventory:DropEverything()
    end
end

-- Asleep, frozen, stunned or in any other busy state: no work this tick.
local function CanActNow(inst)
    if inst.components.sleeper ~= nil and inst.components.sleeper:IsAsleep() then
        return false
    end
    if inst.components.freezable ~= nil and inst.components.freezable:IsFrozen() then
        return false
    end
    return inst.sg == nil or not inst.sg:HasStateTag("busy")
end

local function PlayWorkAnim(inst)
    if inst.sg ~= nil and not inst.sg:HasStateTag("busy") then
        inst.sg:GoToState("eat")
    end
end

-- Put carried items into the den. Returns true if the worker is now empty.
local function Deposit(self, den)
    local inventory = self.inst.components.inventory
    local items = {}
    inventory:ForEachItem(function(item) table.insert(items, item) end)
    local empty = true
    for _, item in ipairs(items) do
        local removed = inventory:RemoveItem(item, true)
        if removed ~= nil then
            local stored, rest = den.components.sk_workerhive:Store(removed)
            if not stored then
                empty = false
                if rest ~= nil then
                    inventory:GiveItem(rest)
                end
            end
        end
    end

    -- Something that can never go into a container (held as activeitem): leave it next to the den.
    local active = inventory.activeitem
    if active ~= nil then
        local item = inventory:RemoveItem(active, true)
        if item ~= nil then
            local stored, rest = den.components.sk_workerhive:Store(item)
            if not stored and rest ~= nil and rest:IsValid() then
                rest.Transform:SetPosition(den.Transform:GetWorldPosition())
                if rest.components.inventoryitem ~= nil then
                    rest.components.inventoryitem:OnDropped(true)
                end
            end
        end
    end
    return empty
end

local function Despawn(self)
    local inst = self.inst
    DropEverything(inst)
    local fx = SpawnPrefab("spawn_fx_small")
    if fx ~= nil then
        fx.Transform:SetPosition(inst.Transform:GetWorldPosition())
    end
    inst:Remove()
end

-- K4 hauler ----------------------------------------------------------------------------------

-- A den the hauler could not reach in time (water, walls...) is skipped for a while.
local function TripTimedOut(self)
    return GetTime() - (self.trip_start or 0) > TUNING.SPIDERKINGDOM.LOGISTICS_TRIP_TIME
end

local function Avoid(self, den)
    if self.avoid == nil then
        self.avoid = setmetatable({}, { __mode = "k" })
    end
    self.avoid[den] = GetTime() + 2 * TUNING.SPIDERKINGDOM.LOGISTICS_TRIP_TIME
end

local function IsAvoided(self, den)
    local time = self.avoid ~= nil and self.avoid[den] or nil
    return time ~= nil and time > GetTime()
end

local function GetCarriedItem(inst)
    local inventory = inst.components.inventory
    local found = nil
    inventory:ForEachItemSlot(function(item)
        if found == nil then
            found = item
        end
    end)
    return found or inventory.activeitem
end

-- Carry the cargo to a storage den that takes it. Leftovers (the den filled up meanwhile) go to the
-- next storage den on the next tick. Nowhere to go: keep it and wait at home, retrying with back-off.
local function HaulerDeliver(self, home)
    local inst = self.inst
    local item = GetCarriedItem(inst)
    if item == nil then
        return
    end

    -- Only "hand" cargo left: it can never go into a container (see Deposit), so it is left next to
    -- the home den, as for any other worker.
    if item == inst.components.inventory.activeitem then
        if inst:GetDistanceSqToInst(home) <= HOME_DIST * HOME_DIST then
            Deposit(self, home)
            SetTarget(self, nil, nil)
        else
            SetTarget(self, "home", home)
        end
        return
    end

    local dest = self.mode == "deliver" and self:GetMoveTarget() or nil
    if dest ~= nil and not (Network.IsStorage(dest, Network.GetDenOwner(home)) and Network.GetRoomFor(dest, item) > 0) then
        dest = nil
    end
    if dest ~= nil and inst:GetDistanceSqToInst(dest) > HOME_DIST * HOME_DIST and TripTimedOut(self) then
        Avoid(self, dest)
        dest = nil
    end
    if dest == nil then
        self.search_cooldown = math.max(0, self.search_cooldown - TICK)
        if self.search_cooldown <= 0 then
            dest = Network.FindStorageFor(home, item, inst, function(den) return not IsAvoided(self, den) end)
            if dest == nil then
                self.search_cooldown = TUNING.SPIDERKINGDOM.LOGISTICS_SEARCH_PERIOD
            end
        end
    end
    if dest == nil then
        SetTarget(self, "home", home)
        return
    end

    if inst:GetDistanceSqToInst(dest) > HOME_DIST * HOME_DIST or not CanActNow(inst) then
        SetTarget(self, "deliver", dest)
        return
    end

    Deposit(self, dest)
    SetTarget(self, nil, nil)
    self.search_cooldown = 0
end

-- Walk to a production den and take one stack that a storage den has room for.
local function HaulerFetch(self, home)
    local inst = self.inst
    local source = self.mode == "fetch" and self:GetMoveTarget() or nil
    if source ~= nil and not Network.IsSource(source, Network.GetDenOwner(home)) then
        source = nil
    end
    if source ~= nil and inst:GetDistanceSqToInst(source) > HOME_DIST * HOME_DIST and TripTimedOut(self) then
        Avoid(self, source)
        SetTarget(self, nil, nil)
        source = nil
    end

    if source ~= nil then
        if inst:GetDistanceSqToInst(source) > HOME_DIST * HOME_DIST or not CanActNow(inst) then
            Claim(self, source)
            return
        end
        local item, dest = Network.TakeStack(source, home, inst, function(den) return not IsAvoided(self, den) end)
        if item ~= nil then
            -- If the inventory refused it, it lands at our feet rather than at the world origin.
            item.Transform:SetPosition(inst.Transform:GetWorldPosition())
            inst.components.inventory:GiveItem(item)
            PlayWorkAnim(inst)
            SetTarget(self, "deliver", dest)
            return
        end
        -- Emptied by someone else, or the storage dens filled up on the way: look again.
        SetTarget(self, nil, nil)
    end

    self.search_cooldown = math.max(0, self.search_cooldown - TICK)
    if self.search_cooldown <= 0 then
        local found = Network.FindHaulJob(home, inst, function(den)
            return not IsClaimedByOther(self, den) and not IsAvoided(self, den)
        end)
        if found ~= nil then
            SetTarget(self, "fetch", found)
            return
        end
        self.search_cooldown = TUNING.SPIDERKINGDOM.LOGISTICS_SEARCH_PERIOD
    end
    SetTarget(self, "home", home)
end

local function HaulerTick(self, home, hive)
    if CountItems(self.inst) > 0 then
        HaulerDeliver(self, home)
        return
    end
    if self.retiring then
        Despawn(self)
        return
    end
    if not hive:IsWorking() then
        SetTarget(self, "home", home)
        return
    end
    HaulerFetch(self, home)
end

-- Tick ---------------------------------------------------------------------------------------

function Worker:Tick()
    local inst = self.inst
    if inst.components.health ~= nil and inst.components.health:IsDead() then
        return
    end

    local den = self:GetHome()
    if den == nil then
        -- The den is gone (or did not restore its followers after a load): leave the goods, vanish.
        self.orphan_ticks = self.orphan_ticks + 1
        if self.orphan_ticks >= 3 then
            Despawn(self)
        end
        return
    end
    self.orphan_ticks = 0

    -- Off screen the brain does not move us, so searching is pointless. A retiring worker still has
    -- to leave (or the den would keep more workers than allowed): unload directly, then go.
    if inst:IsAsleep() then
        if self.retiring then
            if CountItems(inst) > 0 then
                Deposit(self, den)
            end
            Despawn(self)
        end
        return
    end

    local tuning = TUNING.SPIDERKINGDOM
    local hive = den.components.sk_workerhive
    local profession = hive:GetProfession()
    local job = profession ~= nil and JOBS[profession] or nil
    local working = hive:IsWorking() and job ~= nil and not self.retiring
    local carried = CountItems(inst)
    local near_den = inst:GetDistanceSqToInst(den) <= HOME_DIST * HOME_DIST

    if profession ~= self.profession then
        self.profession = profession
        RefreshTint(self)
        -- A trip home with cargo stays a trip home.
        if self.mode ~= "deposit" then
            SetTarget(self, nil, nil)
        end
    end

    if profession == HAULER then
        HaulerTick(self, den, hive)
        return
    end

    -- Delivery: once a trip home has started, unload everything before anything else.
    if carried > 0 and (self.mode == "deposit" or carried >= tuning.WORKER_CARRY_SLOTS or not working) then
        if not near_den then
            SetTarget(self, "deposit", den)
            return
        end
        if not Deposit(self, den) then
            -- The den is full: wait there and retry every tick.
            SetTarget(self, "deposit", den)
            return
        end
        carried = 0
        SetTarget(self, nil, nil)
    end

    if self.retiring then
        if carried == 0 then
            Despawn(self)
        end
        return
    end

    if not working or not hive:HasRoom() then
        -- Cargo may still fit an existing stack: try to unload it rather than just waiting.
        SetTarget(self, carried > 0 and "deposit" or "home", den)
        return
    end

    self.work_cooldown = math.max(0, self.work_cooldown - TICK)

    -- Current target: re-checked against the current job every tick.
    local target = (self.mode == "work" or self.mode == "pickup") and self:GetMoveTarget() or nil
    if target ~= nil then
        local valid = (self.mode == "pickup" and IsValidPickup(job, target))
            or (self.mode == "work" and IsValidWork(job, target))
        if not valid then
            target = nil
        elseif inst:GetDistanceSqToInst(target) <= REACH_DIST * REACH_DIST and CanActNow(inst) then
            if self.mode == "pickup" then
                inst.components.inventory:GiveItem(target)
                PlayWorkAnim(inst)
                target = nil
            elseif self.work_cooldown <= 0 then
                self.work_cooldown = tuning.WORKER_WORK_PERIOD
                PlayWorkAnim(inst)
                if IsValidPick(job, target) then
                    target.components.pickable:Pick(inst)
                    target = nil
                else
                    target.components.workable:WorkedBy(inst, 1)
                    if not (target:IsValid() and IsValidChop(job, target)) then
                        target = nil
                    end
                end
            end
        end
    end

    if target ~= nil then
        Claim(self, target)
        return
    end

    -- Choose the next job. Unsuccessful searches back off so idle colonies stay cheap.
    self.search_cooldown = math.max(0, self.search_cooldown - TICK)
    if self.search_cooldown <= 0 then
        local mode, found = FindJob(self, den, job)
        if found ~= nil then
            SetTarget(self, mode, found)
            return
        end
        self.search_cooldown = tuning.WORKER_IDLE_SEARCH_PERIOD
    end

    -- Nothing to do nearby: bring home what we have, otherwise wait at the den.
    if carried > 0 then
        SetTarget(self, "deposit", den)
    else
        SetTarget(self, "home", den)
    end
end

function Worker:OnSave()
    if self.active then
        return { active = true, retiring = self.retiring or nil, delivering = self.mode == "deposit" or nil }
    end
end

function Worker:OnLoad(data)
    if data ~= nil and data.active then
        self:Activate()
        self.retiring = data.retiring or false
        if data.delivering then
            self.mode = "deposit" -- the target (the den) is picked up again on the first tick
        end
    end
end

function Worker:OnRemoveFromEntity()
    if self.task ~= nil then
        self.task:Cancel()
        self.task = nil
    end
end

function Worker:GetDebugString()
    return string.format("active: %s, profession: %s, retiring: %s, mode: %s, target: %s, carrying: %d",
        tostring(self.active), tostring(self.profession), tostring(self.retiring), tostring(self.mode), tostring(self.target), CountItems(self.inst))
end

return Worker
