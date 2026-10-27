-- B5 Molting (server). A single hit of at least MOLTING_HIT_THRESHOLD of max health grants
-- a damage-taken reduction for a few seconds, then a cooldown. Uses the player's timer component.

local Molting = {}

local MODIFIER_KEY = "sk_molting"
local TIMER_ACTIVE = "sk_molting_active"
local TIMER_COOLDOWN = "sk_molting_cd"

local function EndBuff(inst)
    if inst.components.combat ~= nil then
        inst.components.combat.externaldamagetakenmultipliers:RemoveModifier(inst, MODIFIER_KEY)
    end
end

local function OnAttacked(inst, data)
    if data == nil or data.redirected or inst.components.health:IsDead() then
        return
    end

    local timer = inst.components.timer
    if timer:TimerExists(TIMER_COOLDOWN) then
        return
    end

    local tuning = TUNING.SPIDERKINGDOM
    local damage = data.damageresolved or data.damage or 0
    if damage < inst.components.health.maxhealth * tuning.MOLTING_HIT_THRESHOLD then
        return
    end

    inst.components.combat.externaldamagetakenmultipliers:SetModifier(inst, tuning.MOLTING_DAMAGE_TAKEN_MULT, MODIFIER_KEY)
    timer:StartTimer(TIMER_ACTIVE, tuning.MOLTING_DURATION)
    timer:StartTimer(TIMER_COOLDOWN, tuning.MOLTING_COOLDOWN)
end

local function OnTimerDone(inst, data)
    if data ~= nil and data.name == TIMER_ACTIVE then
        EndBuff(inst)
    end
end

function Molting.Enable(inst)
    Molting.Disable(inst)
    -- The modifier itself is not saved: drop a buff left running from the previous session.
    -- The cooldown timer is saved by the timer component and keeps counting.
    if inst.components.timer:TimerExists(TIMER_ACTIVE) then
        inst.components.timer:StopTimer(TIMER_ACTIVE)
    end
    inst:ListenForEvent("attacked", OnAttacked)
    inst:ListenForEvent("timerdone", OnTimerDone)
end

function Molting.Disable(inst)
    inst:RemoveEventCallback("attacked", OnAttacked)
    inst:RemoveEventCallback("timerdone", OnTimerDone)
    EndBuff(inst)
end

return Molting
