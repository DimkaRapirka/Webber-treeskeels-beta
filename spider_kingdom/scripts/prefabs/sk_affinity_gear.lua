-- Visuals (Phase 6): own fang art (build with symbol "swap_spear" in the official spear frame layout: stock
-- "spear" bank on the ground, OverrideSymbol("swap_object", build, "swap_spear") in the hand) and carapaces made
-- from the official marble suit recoloured (stock "armor_marble" bank; every torso pose of swap_body).
-- Builds and icons: art_src/tools/gen_items.py, recolor_build.py. Icons: images/sk_inventoryimages.xml.
local lunar_fang_assets = { Asset("ANIM", "anim/spear.zip"), Asset("ANIM", "anim/sk_lunar_fang.zip") }
local shadow_fang_assets = { Asset("ANIM", "anim/spear.zip"), Asset("ANIM", "anim/sk_shadow_fang.zip") }
local lunar_carapace_assets = { Asset("ANIM", "anim/armor_marble.zip"), Asset("ANIM", "anim/sk_lunar_carapace.zip") }
local shadow_carapace_assets = { Asset("ANIM", "anim/armor_marble.zip"), Asset("ANIM", "anim/sk_shadow_carapace.zip") }

local function OnUnequipFang(inst, owner)
    owner.AnimState:Hide("ARM_carry")
    owner.AnimState:Show("ARM_normal")
end

local function OnUnequipCarapace(inst, owner)
    owner.AnimState:ClearOverrideSymbol("swap_body")
end

local function MakeFangFn(bank, build, swap_build, swap_symbol, bonus_tag, loop)
    local function OnEquip(inst, owner)
        owner.AnimState:OverrideSymbol("swap_object", swap_build, swap_symbol)
        owner.AnimState:Show("ARM_carry")
        owner.AnimState:Hide("ARM_normal")
    end

    return function()
        local inst = CreateEntity()

        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddNetwork()

        MakeInventoryPhysics(inst)

        inst.AnimState:SetBank(bank)
        inst.AnimState:SetBuild(build)
        inst.AnimState:PlayAnimation("idle", loop)

        inst:AddTag("sharp")

        --weapon (from weapon component) added to pristine state for optimization
        inst:AddTag("weapon")

        local swap_data = { sym_build = swap_build, sym_name = swap_symbol, bank = bank }
        MakeInventoryFloatable(inst, "med", 0.05, { 1, 0.4, 1 }, true, -17.5, swap_data)

        inst.entity:SetPristine()

        if not TheWorld.ismastersim then
            return inst
        end

        inst:AddComponent("inspectable")

        inst:AddComponent("inventoryitem")

        inst:AddComponent("weapon")
        inst.components.weapon:SetDamage(TUNING.SPIDERKINGDOM.AFFINITY_FANG_DAMAGE)

        inst:AddComponent("planardamage")
        inst.components.planardamage:SetBaseDamage(TUNING.SPIDERKINGDOM.AFFINITY_FANG_PLANAR)

        inst:AddComponent("damagetypebonus")
        inst.components.damagetypebonus:AddBonus(bonus_tag, inst, TUNING.SPIDERKINGDOM.AFFINITY_GEAR_BONUS)

        inst:AddComponent("finiteuses")
        inst.components.finiteuses:SetMaxUses(TUNING.SPIDERKINGDOM.AFFINITY_FANG_USES)
        inst.components.finiteuses:SetUses(TUNING.SPIDERKINGDOM.AFFINITY_FANG_USES)
        inst.components.finiteuses:SetOnFinished(inst.Remove)

        inst:AddComponent("equippable")
        inst.components.equippable.restrictedtag = "spiderwhisperer"
        inst.components.equippable:SetOnEquip(OnEquip)
        inst.components.equippable:SetOnUnequip(OnUnequipFang)

        return inst
    end
end

local function MakeCarapaceFn(bank, build, resist_tag)
    local function OnEquip(inst, owner)
        owner.AnimState:OverrideSymbol("swap_body", build, "swap_body")
    end

    return function()
        local inst = CreateEntity()

        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddNetwork()

        MakeInventoryPhysics(inst)

        inst.AnimState:SetBank(bank)
        inst.AnimState:SetBuild(build)
        inst.AnimState:PlayAnimation("anim")

        local swap_data = { bank = bank, anim = "anim" }
        MakeInventoryFloatable(inst, "small", 0.2, 0.80, nil, nil, swap_data)

        inst.entity:SetPristine()

        if not TheWorld.ismastersim then
            return inst
        end

        inst:AddComponent("inspectable")

        inst:AddComponent("inventoryitem")

        -- Ordinary armor is removed when its condition reaches zero.
        inst:AddComponent("armor")
        inst.components.armor:InitCondition(TUNING.SPIDERKINGDOM.AFFINITY_CARAPACE_CONDITION,
            TUNING.SPIDERKINGDOM.AFFINITY_CARAPACE_ABSORB)

        inst:AddComponent("planardefense")
        inst.components.planardefense:SetBaseDefense(TUNING.SPIDERKINGDOM.AFFINITY_CARAPACE_PLANAR)

        inst:AddComponent("damagetyperesist")
        inst.components.damagetyperesist:AddResist(resist_tag, inst, TUNING.SPIDERKINGDOM.AFFINITY_GEAR_RESIST)

        inst:AddComponent("equippable")
        inst.components.equippable.equipslot = EQUIPSLOTS.BODY
        inst.components.equippable.restrictedtag = "spiderwhisperer"
        inst.components.equippable:SetOnEquip(OnEquip)
        inst.components.equippable:SetOnUnequip(OnUnequipCarapace)

        return inst
    end
end

-- The official equipment's set bonuses and special mechanics are not copied, only stock banks are reused.
return Prefab("sk_lunar_fang",
        MakeFangFn("spear", "sk_lunar_fang", "sk_lunar_fang", "swap_spear", "shadow_aligned", false), lunar_fang_assets),
    Prefab("sk_shadow_fang",
        MakeFangFn("spear", "sk_shadow_fang", "sk_shadow_fang", "swap_spear", "lunar_aligned", false), shadow_fang_assets),
    Prefab("sk_lunar_carapace",
        MakeCarapaceFn("armor_marble", "sk_lunar_carapace", "lunar_aligned"), lunar_carapace_assets),
    Prefab("sk_shadow_carapace",
        MakeCarapaceFn("armor_marble", "sk_shadow_carapace", "shadow_aligned"), shadow_carapace_assets)
