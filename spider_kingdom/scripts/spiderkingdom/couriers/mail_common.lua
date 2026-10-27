-- T2 Spider Mail: rules shared by the client collector and the server action.
-- Plain module: require("spiderkingdom/couriers/mail_common").

local MailCommon = {}

-- Spiders a Courier Kit can upgrade (stock land spiders; workers, couriers and the queen excluded).
MailCommon.KIT_TARGETS =
{
    spider = true, spider_warrior = true, spider_hider = true, spider_spitter = true,
    spider_dropper = true, spider_moon = true, spider_healer = true,
}

-- Client and server (uses the follower replica).
function MailCommon.CanUpgrade(doer, spider)
    local follower = spider.replica.follower
    return MailCommon.KIT_TARGETS[spider.prefab] == true
        and not spider:HasTag("sk_worker")
        and not spider:HasTag("sk_guardian") -- a borrowed T4 bodyguard stays its owner's
        and follower ~= nil and follower:GetLeader() == doer
end

return MailCommon
