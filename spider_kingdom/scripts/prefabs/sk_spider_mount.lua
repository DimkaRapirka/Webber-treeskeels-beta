-- M1 Spider Groomer: the Spider Steed, a Spider Warrior grown big enough to ride (components/sk_grooming.lua).
--
--   * Art: the same model as when ridden (build sk_spider_steed_mount: beefalo symbols repainted as a spider)
--     on bank sk_steed (official beefalo animations renamed for the stock SGspider, attacks re-timed to its
--     damage frames, art_src/tools/gen_steed_bank.py), six-faced like the beefalo; stock SGspider (warrior leap
--     attack, sounds), the stock saddle drawn on it.
--   * Riding: the stock rideable component without a saddle, like big Woby (prefabs/wobybig.lua):
--     canride is switched by components/sk_spidermount.lua (owner with the skill), SetShouldSave(false)
--     because the mount is saved by sk_spiderkeeper in the owner's save, and a custom rider test (owner only).
--     The "saddleable" tag the rideable component adds is removed: no saddles (the stock SADDLE collector
--     checks only that tag, componentactions.lua saddler).
--   * Rider visual: components/rider.lua switches the rider to the "wilsonbeefalo" bank and asks the mount
--     for its build overrides: sk_spider_steed_mount (beefalo symbols repainted with the steed's abdomen,
--     face and legs) and the stock saddle. The beefalo rig animates four legs.
--   * Not a stock spider: no inventory item (cannot be picked up or trapped), no hats, no sanity aura,
--     no sleep, no stock trader (only its owner feeds it meat, which heals it), no mutations, no corpse.
--     It keeps the "spider" tag, so sk_spiderkeeper carries it between shards like Webber's other spiders.
--   * Saddlebag (M4, mounts/faithful.lua): a 2x2 container on every steed, opened only while its owner has
--     M4 (or while something is still inside), owner only (components/sk_spidermount.lua).
--   * Brain: brains/sk_spidermountbrain.lua (fight, follow the owner, wander; stand still while the bag
--     is open).

local MountCommon = require("spiderkingdom/mounts/mount_common")

local assets =
{
    Asset("ANIM", "anim/sk_steed.zip"),              -- on foot: bank (beefalo anims under SGspider's names)
    Asset("ANIM", "anim/sk_spider_steed_mount.zip"), -- rider overrides (beefalo symbols, see ApplyBuildOverrides)
    Asset("ANIM", "anim/saddle_basic.zip"),
    Asset("ANIM", "anim/woby_big_mount_dash.zip"), -- M2: rider "dash_woby*" anims, bank wilsonbeefalo
    Asset("SOUND", "sound/spider.fsb"),
}

local prefabs =
{
    "monstermeat",
    "silk",
    "spidergland",
    "spider_mutate_fx",
}

local brain = require("brains/sk_spidermountbrain")

local LOOT = { "monstermeat", "monstermeat", "monstermeat", "silk", "silk", "spidergland" }

local function SoundPath(inst, event)
    return "dontstarve/creatures/spiderwarrior/"..event
end

-- Same keys as the beefalo's sound table; the rider's stategraph plays them (SGwilson DoMountSound).
local sounds =
{
    walk = SoundPath(nil, "walk_spider"),
    grunt = SoundPath(nil, "attack_grunt"),
    yell = SoundPath(nil, "scream"),
    swish = SoundPath(nil, "walk_spider"),
    curious = SoundPath(nil, "scream"),
    angry = SoundPath(nil, "Attack"),
    sleep = SoundPath(nil, "sleeping"),
}

-- Rider interface (components/rider.lua Mount / ActualDismount): only ever called with the rider's AnimState.
-- The rider bank draws the mount with beefalo symbols (like Woby's woby_big_build): sk_spider_steed_mount keeps
-- beefalo_build's geometry with every frame repainted from the steed (abdomen, spider face, spider legs; the
-- beefalo face parts, antlers and tail are empty), art_src/tools/gen_steed_mount.py. The steed has no saddle item, so the stock saddle art is
-- drawn on the rider directly; ActualDismount clears "swap_saddle" itself (components/rider.lua).
local MOUNT_BUILD = "sk_spider_steed_mount"

local function ApplyBuildOverrides(inst, animstate)
    if animstate ~= inst.AnimState then
        animstate:AddOverrideBuild(MOUNT_BUILD)
        animstate:Hide("HEAT") -- beefalo mating-season layer (prefabs/beefalo.lua ApplyBuildOverrides)
        animstate:OverrideSymbol("swap_saddle", "saddle_basic", "swap_saddle")
    end
end

local function ClearBuildOverrides(inst, animstate)
    if animstate ~= inst.AnimState then
        animstate:ClearOverrideBuild(MOUNT_BUILD)
    end
end

-- Combat ---------------------------------------------------------------------------------------

local function GetLeader(inst)
    return inst.components.follower:GetLeader()
end

local function IsOnLeadersSide(inst, guy)
    local leader = GetLeader(inst)
    if leader == nil then
        return false
    end
    if guy == leader then
        return true
    end
    local follower = guy.components.follower
    return follower ~= nil and follower:GetLeader() == leader
end

-- Defends its owner and itself: picks enemies that are going for either of them.
local RETARGET_MUST_TAGS = { "_combat", "_health" }
local RETARGET_CANT_TAGS = { "INLIMBO", "playerghost", "wall", "structure", "notarget", "noattack" }
local function Retarget(inst)
    if inst.no_targeting or inst.components.rideable:IsBeingRidden() then
        return nil
    end
    local leader = GetLeader(inst)
    local center = leader ~= nil and leader:IsValid() and leader or inst
    local combat = inst.components.combat
    return FindEntity(center, TUNING.SPIDERKINGDOM.MOUNT_TARGET_DIST, function(guy)
        local target = guy.components.combat ~= nil and guy.components.combat.target or nil
        return target ~= nil
            and (target == inst or (leader ~= nil and target == leader))
            and not IsOnLeadersSide(inst, guy)
            and combat:CanTarget(guy)
            and not combat:IsAlly(guy)
    end, RETARGET_MUST_TAGS, RETARGET_CANT_TAGS)
end

local function KeepTarget(inst, target)
    if target == nil or not target:IsValid()
        or target.components.health == nil or target.components.health:IsDead()
        or IsOnLeadersSide(inst, target) then
        return false
    end
    local leader = GetLeader(inst)
    return leader == nil or not leader:IsValid() or inst:IsNear(leader, TUNING.SPIDERKINGDOM.MOUNT_KEEP_TARGET_DIST)
end

local function OnAttacked(inst, data)
    local attacker = data ~= nil and data.attacker or nil
    if attacker == nil or not attacker:IsValid() or inst.no_targeting
        or IsOnLeadersSide(inst, attacker)
        or (attacker:HasTag("player") and not TheNet:GetPVPEnabled()) then
        return
    end
    inst.components.combat:SetTarget(attacker)
end

-- Feeding: only its owner (or a Webber with the skill claiming an ownerless mount); meat heals it.

local function AbleToAcceptTest(inst, item, giver)
    if inst.components.health:IsDead() then
        return false, "DEAD"
    elseif not MountCommon.IsGroomingFood(item) then
        return false
    elseif not inst.components.sk_spidermount:CanTakeFoodFrom(giver) then
        return false, "SK_MOUNTOWNERONLY"
    end
    return true
end

local function AcceptTest(inst, item, giver)
    return MountCommon.IsGroomingFood(item) and inst.components.sk_spidermount:CanTakeFoodFrom(giver)
end

local function OnGetItemFromPlayer(inst, giver, item)
    inst.components.sk_spidermount:OnFedBy(giver)
    if not inst.sg:HasStateTag("busy") then
        inst.sg:GoToState("eat", true)
    end
end

local function OnRefuseItem(inst, giver, item)
    if not inst.sg:HasStateTag("busy") then
        inst.sg:GoToState("taunt")
    end
end

local function GetStatus(inst)
    if GetLeader(inst) == nil then
        return "WILD"
    elseif inst.components.health:GetPercent() < 0.3 then
        return "HURT"
    end
end

-------------------------------------------------------------------------------------------------

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddDynamicShadow()
    inst.entity:AddNetwork()

    local scale = TUNING.SPIDERKINGDOM.MOUNT_SCALE

    MakeCharacterPhysics(inst, 100, .5) -- same radius as the stock mounts: the rider is dropped on its spot
    inst.DynamicShadow:SetSize(6 * scale, 2 * scale) -- same model and shadow size as components/rider.lua Mount
    inst.Transform:SetSixFaced() -- the bank's facings are the beefalo's
    inst.Transform:SetScale(scale, scale, scale)

    inst.AnimState:SetBank("sk_steed")
    inst.AnimState:SetBuild(MOUNT_BUILD)
    inst.AnimState:OverrideSymbol("swap_saddle", "saddle_basic", "swap_saddle")
    inst.AnimState:Hide("HEAT") -- beefalo mating-season layer
    inst.AnimState:PlayAnimation("idle", true)

    inst:AddTag("spider")
    inst:AddTag("spider_warrior") -- SGspider: warrior leap attack and hit reaction
    inst:AddTag("monster")
    inst:AddTag("scarytoprey")
    inst:AddTag("largecreature")
    inst:AddTag("companion")
    inst:AddTag(MountCommon.MOUNT_TAG)

    --trader (from trader component) added to pristine state for optimization
    inst:AddTag("trader")

    inst:AddComponent("spawnfader")

    -- Rider interface: also needed on clients (mount sounds in the rider's stategraph).
    inst.sounds = sounds
    inst.ApplyBuildOverrides = ApplyBuildOverrides
    inst.ClearBuildOverrides = ClearBuildOverrides

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.SoundPath = SoundPath
    inst.incineratesound = SoundPath(inst, "die")

    -- locomotor must be constructed before the stategraph!
    inst:AddComponent("locomotor")
    inst.components.locomotor:SetSlowMultiplier(1)
    inst.components.locomotor:SetTriggersCreep(false)
    inst.components.locomotor.pathcaps = { ignorecreep = true }
    inst.components.locomotor:SetAllowPlatformHopping(true)
    inst.components.locomotor.walkspeed = TUNING.SPIDERKINGDOM.MOUNT_WALK_SPEED
    inst.components.locomotor.runspeed = TUNING.SPIDERKINGDOM.MOUNT_RUN_SPEED

    inst:AddComponent("embarker")
    inst:AddComponent("drownable")

    inst:SetStateGraph("SGspider")
    -- No spider corpse (it would revive / mutate as a small stock spider) and no lunar corpse mutation.
    inst.sg.mem.nocorpse = true
    inst.sg.mem.nolunarmutate = true

    inst:AddComponent("lootdropper")
    inst.components.lootdropper:SetLoot(LOOT)

    MakeLargeBurnableCharacter(inst, "beefalo_body")
    MakeLargeFreezableCharacter(inst, "beefalo_body")
    inst.components.burnable.flammability = TUNING.SPIDER_FLAMMABILITY

    inst:AddComponent("health")
    inst.components.health:SetMaxHealth(TUNING.SPIDERKINGDOM.MOUNT_HEALTH)
    -- No automatic fade-out on death: a mount that dies while ridden waits for its rider to fall off,
    -- then plays "death" and erodes from the stategraph's "corpse" state (no corpse prefab, see above).
    inst.components.health.nofadeout = true

    inst:AddComponent("combat")
    inst.components.combat.hiteffectsymbol = "beefalo_body"
    inst.components.combat:SetDefaultDamage(TUNING.SPIDERKINGDOM.MOUNT_DAMAGE)
    inst.components.combat:SetAttackPeriod(TUNING.SPIDERKINGDOM.MOUNT_ATTACK_PERIOD)
    inst.components.combat:SetRange(TUNING.SPIDER_WARRIOR_ATTACK_RANGE, TUNING.SPIDER_WARRIOR_HIT_RANGE)
    inst.components.combat:SetRetargetFunction(2, Retarget)
    inst.components.combat:SetKeepTargetFunction(KeepTarget)

    inst:AddComponent("follower")
    inst.components.follower.keepdeadleader = true -- stays with a ghost owner, like Woby
    inst.components.follower.neverexpire = true    -- StopFollowing (e.g. Spider Repellent) does not release it
    inst.components.follower:KeepLeaderOnAttacked() -- an accidental hit from its owner does not release it

    -- Stock spider recruitment (prefabs/spider.lua OnGetItemFromPlayer) calls sleeper:IsAsleep() on every
    -- "spider" nearby. The steed never falls asleep on its own; sleep darts / pan flute still work.
    inst:AddComponent("sleeper")
    inst.components.sleeper:SetSleepTest(function() return false end)
    inst.components.sleeper:SetWakeTest(function() return true end)

    inst:AddComponent("knownlocations")

    inst:AddComponent("inspectable")
    inst.components.inspectable.getstatus = GetStatus

    inst:AddComponent("trader")
    inst.components.trader:SetAcceptTest(AcceptTest)
    inst.components.trader:SetAbleToAcceptTest(AbleToAcceptTest)
    inst.components.trader.onaccept = OnGetItemFromPlayer
    inst.components.trader.onrefuse = OnRefuseItem
    inst.components.trader.deleteitemonaccept = true

    inst:AddComponent("container")
    inst.components.container:WidgetSetup(MountCommon.MOUNT_PREFAB)
    inst.components.container.canbeopened = false -- sk_spidermount opens it for an owner with M4
    inst.components.container.skipclosesnd = true
    inst.components.container.skipopensnd = true

    inst:AddComponent("rideable")
    inst:RemoveTag("saddleable") -- added by the rideable constructor; no saddles on a spider
    inst.components.rideable:SetShouldSave(false)
    inst.components.rideable:SetCustomRiderTest(function(inst, rider)
        return inst.components.sk_spidermount:CanBeRiddenBy(rider)
    end)
    -- canride stays false until sk_spidermount links an owner with the skill.

    inst:AddComponent("sk_spidermount")

    MakeHauntablePanic(inst)

    inst:SetBrain(brain)

    inst:ListenForEvent("attacked", OnAttacked)

    return inst
end

return Prefab(MountCommon.MOUNT_PREFAB, fn, assets, prefabs)
