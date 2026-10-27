-- 5.6 Unique spider interactions of Lunar / Shadow Affinity (server). Plain module, used by
-- affinity/affinity.lua (Enable / Disable / follower changes) and affinity/followers.lua ("killed").
-- Applies to the leader's follower spiders (IsFollowerSpider: not the queen; the steed counts).
--
--   Lunar, moonlight: at night on the surface, unless the moon is new, follower spiders regenerate
--     (worldstate.lua isnight / moonphase / isfullmoon; double at full moon).
--   Lunar, Shattered Spiders (spider_moon, already lunar_aligned): planar damage bonus. Their moon
--     spikes attack through the spider's own combat (moonspider_spike.lua DoAttack), so spikes get it too
--     (combat.lua CalcDamage -> SpDamageUtil.CollectSpDamage on the attacker).
--   Shadow, darkness: follower spiders out of the light deal more damage (combat externaldamagemultipliers;
--     a steed's multiplier is also its rider's mounted damage, combat.lua CalcDamage).
--   Shadow, feast: a follower spider that kills something heals a share of the victim's max health
--     (combat.lua GetAttacked_Internal pushes "killed" on the attacker).
--
-- Every modifier uses the leader as source and its own key, so it is removed with the leader
-- (sourcemodifierlist.lua listens to the source's "onremove") and never touches another leader's.

local SpiderAffinity = {}

local PLANAR_KEY = "sk_lunar_shattered"
local DARK_KEY = "sk_shadow_darkness"
local MOON_SPIDER = "spider_moon"

function SpiderAffinity.IsFollowerSpider(leader_inst, follower)
    local leader = leader_inst.components.leader
    return follower ~= nil
        and follower:IsValid()
        and follower:HasTag("spider")
        and not follower:HasTag("spiderqueen")
        and leader ~= nil
        and leader.followers[follower] ~= nil
        and follower.components.follower ~= nil
        and follower.components.follower:GetLeader() == leader_inst
end

-- A ridden steed is in limbo (rider.lua Mount -> RemoveFromScene) but still fights: its rider is where it is.
local function GetRider(follower)
    local rideable = follower.components.rideable
    return rideable ~= nil and rideable:IsBeingRidden() and rideable:GetRider() or nil
end

local function IsAlive(follower)
    return (not follower:IsInLimbo() or GetRider(follower) ~= nil)
        and follower.components.health ~= nil
        and not follower.components.health:IsDead()
end

local function ForEachFollowerSpider(inst, fn)
    local leader = inst.components.leader
    if leader == nil then
        return
    end
    for follower in pairs(leader.followers) do
        if SpiderAffinity.IsFollowerSpider(inst, follower) then
            fn(inst, follower)
        end
    end
end

-- Lunar ------------------------------------------------------------------------------------------

local function IsMoonlit()
    local state = TheWorld.state
    return state.isnight and state.moonphase ~= "new" and not TheWorld:HasTag("cave")
end

local function LunarTick(inst)
    if not IsMoonlit() then
        return
    end
    local tuning = TUNING.SPIDERKINGDOM
    local amount = tuning.AFFINITY_MOON_REGEN * (TheWorld.state.isfullmoon and tuning.AFFINITY_FULLMOON_REGEN_MULT or 1)
    ForEachFollowerSpider(inst, function(_, follower)
        if IsAlive(follower) and follower.components.health:IsHurt() then
            follower.components.health:DoDelta(amount, true, "sk_moonlight")
        end
    end)
end

-- Shadow -----------------------------------------------------------------------------------------

local function SetDark(inst, follower, dark)
    local combat = follower.components.combat
    if combat == nil then
        return
    end
    if dark then
        combat.externaldamagemultipliers:SetModifier(inst, TUNING.SPIDERKINGDOM.AFFINITY_DARK_DAMAGE_MULT, DARK_KEY)
    else
        combat.externaldamagemultipliers:RemoveModifier(inst, DARK_KEY)
    end
end

local function ShadowTick(inst)
    local threshold = TUNING.SPIDERKINGDOM.AFFINITY_DARK_LIGHT
    ForEachFollowerSpider(inst, function(_, follower)
        -- Stateless light test (entityscript.lua IsLightGreaterThan; IsInLight would store hysteresis on her).
        local spot = GetRider(follower) or follower
        SetDark(inst, follower, IsAlive(follower) and not spot:IsLightGreaterThan(threshold))
    end)
end

-- Followers --------------------------------------------------------------------------------------

local TICKS =
{
    lunar = { field = "_sk_lunar_spiders_task", fn = LunarTick },
    shadow = { field = "_sk_shadow_spiders_task", fn = ShadowTick },
}

function SpiderAffinity.OnFollowerAdded(alignment, inst, follower)
    -- The caller has checked the skill and IsFollowerSpider.
    if alignment == "lunar" and follower.prefab == MOON_SPIDER then
        if follower.components.planardamage == nil then
            follower:AddComponent("planardamage")
        end
        follower.components.planardamage:AddBonus(inst, TUNING.SPIDERKINGDOM.AFFINITY_SHATTERED_PLANAR, PLANAR_KEY)
    end
    -- Darkness is applied by the next ShadowTick.
end

function SpiderAffinity.OnFollowerRemoved(alignment, inst, follower)
    -- Like affinity.lua: no tag / leader checks, remove only this leader's sources.
    if alignment == "lunar" then
        if follower.components.planardamage ~= nil then
            follower.components.planardamage:RemoveBonus(inst, PLANAR_KEY)
        end
    elseif follower.components.combat ~= nil then
        follower.components.combat.externaldamagemultipliers:RemoveModifier(inst, DARK_KEY)
    end
end

function SpiderAffinity.Enable(alignment, inst)
    local tick = TICKS[alignment]
    if inst[tick.field] == nil then
        local period = TUNING.SPIDERKINGDOM.AFFINITY_SPIDER_TICK
        inst[tick.field] = inst:DoPeriodicTask(period, tick.fn, period * math.random())
    end
end

function SpiderAffinity.Disable(alignment, inst)
    local tick = TICKS[alignment]
    if inst[tick.field] ~= nil then
        inst[tick.field]:Cancel()
        inst[tick.field] = nil
    end
    -- Follower effects are removed by affinity.lua through OnFollowerRemoved.
end

-- Called from affinity/followers.lua on "stopfollowing": remembers who a dying follower followed.
function SpiderAffinity.OnStopFollowing(follower, leader)
    local health = follower.components.health
    if health ~= nil and health:IsDead() then
        follower._sk_deadleader = leader
    end
end

-- Feast: "killed" on any follower (affinity/followers.lua); the rules are checked when it arrives.
function SpiderAffinity.OnKilled(follower, data)
    local victim = data ~= nil and data.victim or nil
    if victim == nil or data.incinerated or victim == follower then
        return
    end
    local leader = follower.components.follower ~= nil and follower.components.follower:GetLeader() or nil
    if leader == nil or not leader._sk_shadow_affinity or not SpiderAffinity.IsFollowerSpider(leader, follower) then
        return
    end
    -- No heal from the leader's own followers (accidents or deliberate farming). A dead follower has
    -- already left its leader when "killed" arrives (health "death" -> leader RemoveFollower, before
    -- combat pushes "killed"), so its last leader is kept by OnStopFollowing.
    local victim_follower = victim.components.follower
    if victim._sk_deadleader == leader or (victim_follower ~= nil and victim_follower:GetLeader() == leader) then
        return
    end
    local victim_health = victim.components.health
    if victim_health == nil or not IsAlive(follower) or not follower.components.health:IsHurt() then
        return
    end
    local tuning = TUNING.SPIDERKINGDOM
    local amount = math.min(victim_health.maxhealth * tuning.AFFINITY_FEAST_PERCENT, tuning.AFFINITY_FEAST_MAX)
    if amount > 0 then
        follower.components.health:DoDelta(amount, false, "sk_feast")
    end
end

return SpiderAffinity
