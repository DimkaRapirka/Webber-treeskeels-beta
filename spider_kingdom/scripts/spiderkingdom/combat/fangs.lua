-- B3 Predator Fangs (server). Consecutive hits on the same target within a short window
-- apply stacking venom (sk_venom_debuff). The first hit only starts the chain.

local Fangs = {}

local DEBUFF_NAME = "sk_venom"
local EXCLUDE_TAGS = { "structure", "wall", "INLIMBO" }

local function OnHitOther(inst, data)
    local target = data ~= nil and data.target or nil
    if target == nil or not target:IsValid() or data.redirected then
        return
    end

    local health = target.components.health
    if health == nil or health:IsDead() or target:HasAnyTag(EXCLUDE_TAGS) then
        return
    end

    local tuning = TUNING.SPIDERKINGDOM
    local now = GetTime()
    local chain = inst._sk_fangs_chain
    if chain ~= nil and chain.target == target and now - chain.time <= tuning.FANGS_CHAIN_WINDOW then
        chain.hits = chain.hits + 1
    else
        chain = { target = target, hits = 1 }
        inst._sk_fangs_chain = chain
    end
    chain.time = now

    local stacks = math.min(chain.hits - 1, tuning.FANGS_MAX_STACKS)
    if stacks > 0 and target:AddDebuff(DEBUFF_NAME, "sk_venom_debuff", { attacker = inst, stacks = stacks }) then
        inst._sk_venom_targets[target] = true
    end
end

function Fangs.Enable(inst)
    Fangs.Disable(inst)
    inst._sk_venom_targets = setmetatable({}, { __mode = "k" })
    inst:ListenForEvent("onhitother", OnHitOther)
end

-- Also stops venom this Webber already applied ("sk_venom" is shared, so check who owns it).
function Fangs.Disable(inst)
    inst:RemoveEventCallback("onhitother", OnHitOther)
    inst._sk_fangs_chain = nil

    local targets = inst._sk_venom_targets
    inst._sk_venom_targets = nil
    if targets ~= nil then
        for target in pairs(targets) do
            if target:IsValid() then
                local debuff = target:GetDebuff(DEBUFF_NAME)
                if debuff ~= nil and debuff.attacker == inst then
                    target:RemoveDebuff(DEBUFF_NAME)
                end
            end
        end
    end
end

return Fangs
