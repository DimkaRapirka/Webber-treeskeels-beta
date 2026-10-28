local Wheel = require("spiderkingdom/spiders/command_wheel")
local assets = {
    Asset("ANIM", "anim/sk_item.zip"),
    Asset("ANIM", "anim/sk_command_whistle.zip"),
    Asset("ATLAS", "images/sk_commandwheel.xml"),
    Asset("IMAGE", "images/sk_commandwheel.tex"),
}

local function fn()
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()
    MakeInventoryPhysics(inst)
    inst.AnimState:SetBank("sk_item")
    inst.AnimState:SetBuild("sk_command_whistle")
    inst.AnimState:PlayAnimation("idle")
    MakeInventoryFloatable(inst, "small", 0.15, 0.9)

    -- Native spellbook is deliberately a component on BOTH sides, before SetPristine (like Abigail's flower).
    local spellbook = inst:AddComponent("spellbook")
    spellbook:SetRequiredTag("spiderwhisperer")
    spellbook:SetCanUseFn(Wheel.CanUse)
    spellbook:SetRadius(150)
    spellbook:SetFocusRadius(165)
    spellbook:SetItems(Wheel.MakeItems())
    inst.entity:SetPristine()
    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("inspectable")
    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem.atlasname = "images/sk_inventoryimages.xml"
    MakeSmallBurnable(inst, TUNING.SMALL_BURNTIME)
    MakeSmallPropagator(inst)
    MakeHauntableLaunch(inst)
    return inst
end

return Prefab("sk_command_whistle", fn, assets)
