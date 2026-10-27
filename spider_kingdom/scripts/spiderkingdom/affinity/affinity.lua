-- Lunar / Shadow Affinity (server): the allegiance passives; unique spider interactions in spiders/affinity.lua.
-- Skill handlers call Enable / Disable; affinity/followers.lua handles later leader changes.

local SpiderAffinity = require("spiderkingdom/spiders/affinity")
local IsFollowerSpider = SpiderAffinity.IsFollowerSpider

local function MakeAffinity(alignment, opposite)
    local Affinity = {}
    local player_tag = "player_"..alignment.."_aligned"
    local resist_tag = alignment.."_aligned"
    local bonus_tag = opposite.."_aligned"
    local modifier_key = "sk_"..alignment.."_affinity"
    local enabled_field = "_sk_"..alignment.."_affinity"

    function Affinity.OnFollowerAdded(inst, follower)
        if not inst[enabled_field] or not IsFollowerSpider(inst, follower) then
            return
        end

        if follower.components.damagetypebonus == nil then
            follower:AddComponent("damagetypebonus")
        end
        follower.components.damagetypebonus:AddBonus(bonus_tag, inst, TUNING.SPIDERKINGDOM.AFFINITY_SPIDER_BONUS, modifier_key)
        SpiderAffinity.OnFollowerAdded(alignment, inst, follower)
    end

    function Affinity.OnFollowerRemoved(inst, follower)
        -- Do not check the skill, spider tags or current leader here: they may already have changed.
        -- Remove only this leader's source, so a transfer cannot erase the new leader's bonus.
        local damagetypebonus = follower.components.damagetypebonus
        if damagetypebonus ~= nil then
            damagetypebonus:RemoveBonus(bonus_tag, inst, modifier_key)
        end
        SpiderAffinity.OnFollowerRemoved(alignment, inst, follower)
    end

    function Affinity.Enable(inst)
        inst[enabled_field] = true
        inst:AddTag(player_tag)

        -- player_common.lua supplies both components, as for the official allegiance skills.
        local damagetyperesist = inst.components.damagetyperesist
        if damagetyperesist ~= nil then
            damagetyperesist:AddResist(resist_tag, inst, TUNING.SPIDERKINGDOM.AFFINITY_RESIST, modifier_key)
        end
        local damagetypebonus = inst.components.damagetypebonus
        if damagetypebonus ~= nil then
            damagetypebonus:AddBonus(bonus_tag, inst, TUNING.SPIDERKINGDOM.AFFINITY_BONUS, modifier_key)
        end

        -- Covers followers restored before skill activation. Later restores use startfollowing.
        local leader = inst.components.leader
        if leader ~= nil then
            for follower in pairs(leader.followers) do
                Affinity.OnFollowerAdded(inst, follower)
            end
        end
        SpiderAffinity.Enable(alignment, inst)
    end

    function Affinity.Disable(inst)
        inst[enabled_field] = nil
        SpiderAffinity.Disable(alignment, inst)
        inst:RemoveTag(player_tag)

        local damagetyperesist = inst.components.damagetyperesist
        if damagetyperesist ~= nil then
            damagetyperesist:RemoveResist(resist_tag, inst, modifier_key)
        end
        local damagetypebonus = inst.components.damagetypebonus
        if damagetypebonus ~= nil then
            damagetypebonus:RemoveBonus(bonus_tag, inst, modifier_key)
        end

        local leader = inst.components.leader
        if leader ~= nil then
            for follower in pairs(leader.followers) do
                Affinity.OnFollowerRemoved(inst, follower)
            end
        end
    end

    return Affinity
end

return
{
    Lunar = MakeAffinity("lunar", "shadow"),
    Shadow = MakeAffinity("shadow", "lunar"),
}
