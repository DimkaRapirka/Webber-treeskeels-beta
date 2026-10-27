-- B6 One in the Pack (server). +PACK_DAMAGE_MULT personal damage while between PACK_MIN and PACK_MAX
-- combat spiders follow Webber within PACK_RADIUS. Meant for small squads, not armies.

local Pack = {}

local MODIFIER_KEY = "sk_pack"

local function IsCombatSpider(follower)
    return follower:HasTag("spider")
        and not follower:HasTag("sk_worker")
        and follower.components.combat ~= nil
        and follower.components.health ~= nil
        and not follower.components.health:IsDead()
        and not (follower.components.inventoryitem ~= nil and follower.components.inventoryitem:IsHeld())
end

local function Refresh(inst)
    local tuning = TUNING.SPIDERKINGDOM
    local count = 0
    local radius_sq = tuning.PACK_RADIUS * tuning.PACK_RADIUS
    for follower in pairs(inst.components.leader.followers) do
        if IsCombatSpider(follower) and inst:GetDistanceSqToInst(follower) <= radius_sq then
            count = count + 1
        end
    end

    local combat = inst.components.combat
    if count >= tuning.PACK_MIN and count <= tuning.PACK_MAX then
        combat.externaldamagemultipliers:SetModifier(inst, tuning.PACK_DAMAGE_MULT, MODIFIER_KEY)
    else
        combat.externaldamagemultipliers:RemoveModifier(inst, MODIFIER_KEY)
    end
end

function Pack.Enable(inst)
    Pack.Disable(inst)
    inst._sk_pack_task = inst:DoPeriodicTask(TUNING.SPIDERKINGDOM.PACK_REFRESH_PERIOD, Refresh, 0)
end

function Pack.Disable(inst)
    if inst._sk_pack_task ~= nil then
        inst._sk_pack_task:Cancel()
        inst._sk_pack_task = nil
    end
    if inst.components.combat ~= nil then
        inst.components.combat.externaldamagemultipliers:RemoveModifier(inst, MODIFIER_KEY)
    end
end

return Pack
