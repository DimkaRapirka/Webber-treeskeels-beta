-- M1 Spider Groomer: rules shared by the mount prefab, its components and the client collector.
-- Plain module: require("spiderkingdom/mounts/mount_common").
--
-- Client and server: CanOfferMount (uses the follower replica and the player's skill tag).
-- Server only: IsGroomingFood, FindOwner, IsLeaving, Say.

local MountCommon = {}

MountCommon.SKILL = "webber_sk_rider_groomer"
MountCommon.SKILL_TAG = "sk_groomer"      -- on Webber while he has the skill (skill handler), for the client
MountCommon.MOUNT_TAG = "sk_mount"        -- on the mount (pristine)
MountCommon.MOUNT_PREFAB = "sk_spider_mount"
MountCommon.GROOM_PREFAB = "spider_warrior"

MountCommon.SKILL_DASH = "webber_sk_rider_dash"         -- M2 Cavalry Dash
MountCommon.SKILL_BATTLE = "webber_sk_rider_battle"     -- M3 Battle Rider
MountCommon.SKILL_FAITHFUL = "webber_sk_rider_faithful" -- M4 Faithful Mount
-- Skills the steed reacts to (components/sk_spidermount.lua refreshes riding and perks when one changes).
MountCommon.RIDER_SKILLS =
{
    [MountCommon.SKILL] = true,
    [MountCommon.SKILL_DASH] = true,
    [MountCommon.SKILL_BATTLE] = true,
    [MountCommon.SKILL_FAITHFUL] = true,
}

MountCommon.DASH_TAG = "sk_cavalry"              -- on Webber while he has M2 (skill handler), for the client
MountCommon.DASH_COOLDOWN_TAG = "sk_dashcooldown" -- on Webber while the dash recharges (server, networked)
MountCommon.BAG_TAG_PREFIX = "sk_steedbag"        -- + owner userid: container.restrictedtag of his steeds

-- Server: M2 cooldown, started when the stock dash state pushes "ondash_woby" on the mount (SGwilson
-- "dash_woby"). The tag is checked by the double-tap collector on both sides (mounts/dash.lua): the
-- server builds the double-tap action again from the same collector (playercontroller
-- OnRemoteDoubleTapAction / OnRemoteLeftClick), so a client cannot dash during the cooldown.
-- Not saved: a fresh player entity (load, shard migration) starts without a cooldown.
function MountCommon.StartDashCooldown(player)
    if player._sk_dashtask ~= nil then
        player._sk_dashtask:Cancel()
    end
    player:AddTag(MountCommon.DASH_COOLDOWN_TAG)
    player._sk_dashtask = player:DoTaskInTime(TUNING.SPIDERKINGDOM.MOUNT_DASH_COOLDOWN, function(player)
        player._sk_dashtask = nil
        player:RemoveTag(MountCommon.DASH_COOLDOWN_TAG)
    end)
end

-- Server: meat-type food that counts for grooming / heals the mount. Switcherdoodles (spider mutators)
-- are MEAT-type edibles too (prefabs/spider_mutators.lua), but they mutate the spider instead.
function MountCommon.IsGroomingFood(item)
    return item ~= nil
        and item.components.edible ~= nil
        and item.components.edible.foodtype == FOODTYPE.MEAT
        and item.components.spidermutator == nil
        and not item:HasTag("spidermutator")
end

-- Client and server: may doer get the stock MOUNT action on this mount? The server repeats the check in
-- the rideable custom rider test (components/sk_spidermount.lua); the "rideable" tag itself is only set
-- while the owner has the skill (rideable.canride).
function MountCommon.CanOfferMount(mount, doer)
    local follower = mount.replica.follower
    return follower ~= nil
        and follower:GetLeader() == doer
        and doer:HasTag(MountCommon.SKILL_TAG)
end

-- Server: a player is leaving this shard (logout, migration, reroll); see spiders/squad.lua and
-- components/sk_spiderkeeper.lua for the two flags.
function MountCommon.IsLeaving(player)
    return player._sk_despawning
        or (player.components.sk_spiderkeeper ~= nil and player.components.sk_spiderkeeper.despawning)
        or false
end

-- Server: the online Webber with this userid, if any.
function MountCommon.FindOwner(userid)
    if userid == nil or userid == "" then
        return nil
    end
    for _, player in ipairs(AllPlayers) do
        if player.userid == userid then
            return player
        end
    end
end

function MountCommon.Say(player, str)
    if player ~= nil and player:IsValid() and player.components.talker ~= nil and str ~= nil then
        player.components.talker:Say(str)
    end
end

return MountCommon
