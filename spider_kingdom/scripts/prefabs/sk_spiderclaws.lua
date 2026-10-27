-- B2 Spider Reflexes: "Spider Claws", a melee weapon whose AoE spell is the official lunge
-- (components/aoeweapon_lunge.lua + aoetargeting + rechargeable, same wiring as Wigfrid's
-- spear_wathgrithr_lightning in prefabs/spear_wathgrithr.lua). The lunge is only enabled while the
-- owner has the skill and the cooldown is over; SGwilson handles combat_lunge_start / combat_lunge.
-- Visuals: own art (build sk_spiderclaws: symbol "swap_spear" in the official spear frame layout, so the
-- stock "spear" bank plants it on the ground and the floater override works).

local SKILL = "webber_sk_predator_reflexes"

local assets =
{
    Asset("ANIM", "anim/spear.zip"),
    Asset("ANIM", "anim/sk_spiderclaws.zip"),
}

local prefabs =
{
    "reticuleline",
    "reticulelineping",
}

local BUILD = "sk_spiderclaws"

local function OwnerHasSkill(owner)
    return owner ~= nil and owner.components.skilltreeupdater ~= nil and owner.components.skilltreeupdater:IsActivated(SKILL)
end

local function RefreshLunge(inst)
    local owner = inst.components.equippable:IsEquipped() and inst.components.inventoryitem:GetGrandOwner() or nil
    inst.components.aoetargeting:SetEnabled(inst.components.rechargeable:IsCharged() and OwnerHasSkill(owner))
end

local function WatchSkills(inst, owner)
    if inst._owner ~= nil then
        inst:RemoveEventCallback("onactivateskill_server", inst._onskillrefresh, inst._owner)
        inst:RemoveEventCallback("ondeactivateskill_server", inst._onskillrefresh, inst._owner)
    end
    inst._owner = owner
    if owner ~= nil then
        inst:ListenForEvent("onactivateskill_server", inst._onskillrefresh, owner)
        inst:ListenForEvent("ondeactivateskill_server", inst._onskillrefresh, owner)
    end
end

local function OnEquip(inst, owner)
    owner.AnimState:OverrideSymbol("swap_object", BUILD, "swap_spear")
    owner.AnimState:Show("ARM_carry")
    owner.AnimState:Hide("ARM_normal")

    WatchSkills(inst, owner)
    RefreshLunge(inst)
end

local function OnUnequip(inst, owner)
    owner.AnimState:Hide("ARM_carry")
    owner.AnimState:Show("ARM_normal")

    WatchSkills(inst, nil)
    inst.components.aoetargeting:SetEnabled(false)
end

local function SpellFn(inst, doer, pos)
    doer:PushEvent("combat_lunge", { targetpos = pos, weapon = inst })
end

local function OnLunged(inst, doer, startingpos, targetpos)
    inst.components.rechargeable:Discharge(TUNING.SPIDERKINGDOM.REFLEXES_COOLDOWN)
end

-- Client-side reticule (same shape as the official lunge spear).
local LUNGE_DIST = 6

local function ReticuleTargetFn()
    return Vector3(ThePlayer.entity:LocalToWorldSpace(LUNGE_DIST, 0, 0))
end

local function ReticuleMouseTargetFn(inst, mousepos)
    if mousepos ~= nil then
        local x, y, z = inst.Transform:GetWorldPosition()
        local dx = mousepos.x - x
        local dz = mousepos.z - z
        local l = dx * dx + dz * dz
        if l <= 0 then
            return inst.components.reticule.targetpos
        end
        l = LUNGE_DIST / math.sqrt(l)
        return Vector3(x + dx * l, 0, z + dz * l)
    end
end

local function ReticuleUpdatePositionFn(inst, pos, reticule, ease, smoothing, dt)
    local x, y, z = inst.Transform:GetWorldPosition()
    reticule.Transform:SetPosition(x, 0, z)
    local rot = -math.atan2(pos.z - z, pos.x - x) / DEGREES
    if ease and dt ~= nil then
        local rot0 = reticule.Transform:GetRotation()
        local drot = rot - rot0
        rot = Lerp((drot > 180 and rot0 + 360) or (drot < -180 and rot0 - 360) or rot0, rot, dt * smoothing)
    end
    reticule.Transform:SetRotation(rot)
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    MakeInventoryPhysics(inst)

    inst.AnimState:SetBank("spear")
    inst.AnimState:SetBuild(BUILD)
    inst.AnimState:PlayAnimation("idle")

    inst:AddTag("sharp")
    inst:AddTag("pointy")
    inst:AddTag("weapon")

    -- aoeweapon_lunge and rechargeable (from their components) added to pristine state for optimization.
    inst:AddTag("aoeweapon_lunge")
    inst:AddTag("rechargeable")

    inst:AddComponent("aoetargeting")
    inst.components.aoetargeting:SetAllowRiding(false)
    inst.components.aoetargeting.reticule.reticuleprefab = "reticuleline"
    inst.components.aoetargeting.reticule.pingprefab = "reticulelineping"
    inst.components.aoetargeting.reticule.targetfn = ReticuleTargetFn
    inst.components.aoetargeting.reticule.mousetargetfn = ReticuleMouseTargetFn
    inst.components.aoetargeting.reticule.updatepositionfn = ReticuleUpdatePositionFn
    inst.components.aoetargeting.reticule.validcolour = { 0.7, 0.5, 1, 1 }
    inst.components.aoetargeting.reticule.invalidcolour = { .5, 0, 0, 1 }
    inst.components.aoetargeting.reticule.ease = true
    inst.components.aoetargeting.reticule.mouseenabled = true

    MakeInventoryFloatable(inst, "med", 0.05, {1.1, 0.5, 1.1}, true, -9, { sym_build = BUILD, sym_name = "swap_spear", bank = "spear" })

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst._onskillrefresh = function() RefreshLunge(inst) end

    inst:AddComponent("inspectable")

    inst:AddComponent("inventoryitem")

    inst:AddComponent("weapon")
    inst.components.weapon:SetDamage(TUNING.SPIDERKINGDOM.CLAWS_DAMAGE)

    inst:AddComponent("finiteuses")
    inst.components.finiteuses:SetMaxUses(TUNING.SPIDERKINGDOM.CLAWS_USES)
    inst.components.finiteuses:SetUses(TUNING.SPIDERKINGDOM.CLAWS_USES)
    inst.components.finiteuses:SetOnFinished(inst.Remove)

    inst:AddComponent("equippable")
    inst.components.equippable:SetOnEquip(OnEquip)
    inst.components.equippable:SetOnUnequip(OnUnequip)

    inst.components.aoetargeting:SetEnabled(false)

    inst:AddComponent("aoeweapon_lunge")
    inst.components.aoeweapon_lunge:SetDamage(TUNING.SPIDERKINGDOM.REFLEXES_LUNGE_DAMAGE)
    inst.components.aoeweapon_lunge:SetSound("meta3/wigfrid/spear_lighting_lunge") -- official sound, temporary
    inst.components.aoeweapon_lunge:SetSideRange(1)
    inst.components.aoeweapon_lunge:SetOnLungedFn(OnLunged)
    inst.components.aoeweapon_lunge:SetWorkActions()
    inst.components.aoeweapon_lunge:SetTags("_combat")

    inst:AddComponent("aoespell")
    inst.components.aoespell:SetSpellFn(SpellFn)

    inst:AddComponent("rechargeable")
    inst.components.rechargeable:SetOnDischargedFn(RefreshLunge)
    inst.components.rechargeable:SetOnChargedFn(RefreshLunge)

    MakeHauntableLaunch(inst)

    return inst
end

return Prefab("sk_spiderclaws", fn, assets, prefabs)
