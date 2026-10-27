-- B4 Silk Spit: "Silk Glob", a stackable throwable made by Webbers with the skill.
-- Same throw wiring as Wurt's skill item prefabs/mosquitobomb.lua (complexprojectile + weapon + equipstack).
-- On impact: slows and marks enemies in a small radius (sk_webbed_debuff), leaves a short web patch
-- (the official, otherwise unused spider_web_spit_creep) and sends the thrower's spiders after the target.
-- Visuals: own art (bank sk_item, build sk_silkglob: the glob, its splat and the hand symbol).

local assets =
{
    Asset("ANIM", "anim/sk_item.zip"),
    Asset("ANIM", "anim/sk_silkglob.zip"),
}

local prefabs =
{
    "sk_webbed_debuff",
    "spider_web_spit_creep",
    "reticule",
}


local TARGET_MUST_TAGS = { "_combat", "_health" }
local TARGET_CANT_TAGS = { "INLIMBO", "flight", "invisible", "notarget", "noattack", "playerghost", "wall", "structure" }

local function IsFriend(ent, attacker)
    -- Prefer the official alliance rules (components/combat_replica.lua CanBeAlly: bedazzled,
    -- player_aligned, same leader, ...); the checks below also cover a thrower that is gone.
    local combat = attacker ~= nil and attacker.components.combat or nil
    if combat ~= nil and (not combat:CanTarget(ent) or combat:IsAlly(ent)) then
        return true
    end
    if ent == attacker or ent:HasTag("companion") then
        return true
    end
    if ent:HasTag("player") then
        return not TheNet:GetPVPEnabled()
    end
    local follower = ent.components.follower
    local leader = follower ~= nil and follower:GetLeader() or nil
    return leader ~= nil and (leader == attacker or (leader:HasTag("player") and not TheNet:GetPVPEnabled()))
end

local function SendSpiders(attacker, target)
    local leader = attacker ~= nil and attacker:IsValid() and attacker.components.leader or nil
    if leader == nil then
        return
    end
    local radius_sq = TUNING.SPIDERKINGDOM.SILKSPIT_SPIDER_RADIUS * TUNING.SPIDERKINGDOM.SILKSPIT_SPIDER_RADIUS
    for follower in pairs(leader.followers) do
        if follower:HasTag("spider") and not follower:HasTag("sk_worker")
            and follower.components.combat ~= nil
            and not (follower.components.health ~= nil and follower.components.health:IsDead())
            and follower:GetDistanceSqToInst(attacker) <= radius_sq
            and follower.components.combat:CanTarget(target)
            and not follower.components.combat:IsAlly(target) then
            follower.components.combat:SetTarget(target)
        end
    end
end

local function OnHit(inst, attacker, target)
    local x, y, z = inst.Transform:GetWorldPosition()
    local tuning = TUNING.SPIDERKINGDOM

    local creep = SpawnPrefab("spider_web_spit_creep")
    if creep ~= nil then
        creep.Transform:SetPosition(x, 0, z)
    end

    if attacker ~= nil and not attacker:IsValid() then
        attacker = nil
    end

    -- FindEntities returns the closest first: the first enemy is the one the spiders go after.
    local primary = nil
    for _, ent in ipairs(TheSim:FindEntities(x, 0, z, tuning.SILKSPIT_RADIUS, TARGET_MUST_TAGS, TARGET_CANT_TAGS)) do
        if ent:IsValid() and not ent:IsInLimbo()
            and not (ent.components.health ~= nil and ent.components.health:IsDead())
            and not IsFriend(ent, attacker) then
            ent:AddDebuff("sk_webbed", "sk_webbed_debuff")
            primary = primary or ent
        end
    end

    if primary ~= nil then
        SendSpiders(attacker, primary)
    end

    inst.SoundEmitter:PlaySound("dontstarve/creatures/spider/spider_egg_sack")
    inst.AnimState:PlayAnimation("used")
    inst:ListenForEvent("animover", inst.Remove)
end

local function OnThrown(inst, attacker)
    inst:AddTag("NOCLICK")
    inst.persists = false

    inst.AnimState:PlayAnimation("spin_loop", true)

    inst.Physics:SetMass(1)
    inst.Physics:SetFriction(0)
    inst.Physics:SetDamping(0)
    inst.Physics:SetCollisionGroup(COLLISION.CHARACTERS)
    inst.Physics:SetCollisionMask(
        COLLISION.GROUND,
        COLLISION.OBSTACLES,
        COLLISION.ITEMS
    )
    inst.Physics:SetCapsule(.2, .2)
end

local function OnEquip(inst, owner)
    owner.AnimState:OverrideSymbol("swap_object", "sk_silkglob", "swap_silkglob")
    owner.AnimState:Show("ARM_carry")
    owner.AnimState:Hide("ARM_normal")
end

local function OnUnequip(inst, owner)
    owner.AnimState:Hide("ARM_carry")
    owner.AnimState:Show("ARM_normal")
end

local function ReticuleTargetFn()
    local player = ThePlayer
    local ground = TheWorld.Map
    local pos = Vector3()

    --Attack range is 8, leave room for error. Min range so the web doesn't land on the thrower.
    for r = 6.5, 3.5, -.25 do
        pos.x, pos.y, pos.z = player.entity:LocalToWorldSpace(r, 0, 0)

        if ground:IsPassableAtPoint(pos:Get()) and not ground:IsGroundTargetBlocked(pos) then
            return pos
        end
    end

    return pos
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()

    inst.Transform:SetTwoFaced()

    MakeInventoryPhysics(inst)

    inst.AnimState:SetBank("sk_item")
    inst.AnimState:SetBuild("sk_silkglob")
    inst.AnimState:PlayAnimation("idle")

    inst:AddComponent("reticule")
    inst.components.reticule.targetfn = ReticuleTargetFn
    inst.components.reticule.twinstickcheckscheme = true
    inst.components.reticule.twinstickmode = 1
    inst.components.reticule.twinstickrange = 8
    inst.components.reticule.ease = true

    MakeInventoryFloatable(inst, "small", 0.23, 1.15)

    -- weapon and complexprojectile (from their components) added to pristine state for optimization.
    inst:AddTag("weapon")
    inst:AddTag("projectile")
    inst:AddTag("complexprojectile")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("inspectable")

    inst:AddComponent("inventoryitem")

    inst:AddComponent("locomotor")

    inst:AddComponent("stackable")
    inst.components.stackable.maxsize = TUNING.STACK_SIZE_SMALLITEM

    inst:AddComponent("complexprojectile")
    inst.components.complexprojectile:SetHorizontalSpeed(15)
    inst.components.complexprojectile:SetGravity(-35)
    inst.components.complexprojectile:SetLaunchOffset(Vector3(.25, 1, 0))
    inst.components.complexprojectile:SetOnLaunch(OnThrown)
    inst.components.complexprojectile:SetOnHit(OnHit)

    inst:AddComponent("weapon")
    inst.components.weapon:SetDamage(0)
    inst.components.weapon:SetRange(8, 10)

    inst:AddComponent("equippable")
    inst.components.equippable:SetOnEquip(OnEquip)
    inst.components.equippable:SetOnUnequip(OnUnequip)
    inst.components.equippable.equipstack = true

    MakeHauntableLaunch(inst)

    return inst
end

return Prefab("sk_silkglob", fn, assets, prefabs)
