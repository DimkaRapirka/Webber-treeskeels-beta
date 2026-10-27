-- Spider Kingdom: load order only. Logic lives in scripts/spiderkingdom/.

PrefabFiles =
{
    "sk_spidereggsacks",
    "sk_debuffs",
    "sk_spiderclaws",
    "sk_silkglob",
    "sk_portable_cocoon",
    "sk_courierspider",
    "sk_royal_throne",
    "sk_colony_heart",
    "sk_royal_workshop",
    "sk_spider_mount",
    "sk_affinity_gear",
}

Assets = {}

modimport("scripts/spiderkingdom/tuning.lua")
modimport("scripts/spiderkingdom/strings.lua")
modimport("scripts/spiderkingdom/skilltree/register.lua")
modimport("scripts/spiderkingdom/visuals.lua")

-- Shared mechanics (no Insight cost)
modimport("scripts/spiderkingdom/spiders/keeper.lua")

-- AFFINITY (follower bonuses follow the official startfollowing / stopfollowing events)
modimport("scripts/spiderkingdom/affinity/followers.lua")

-- SYMBIOSIS
modimport("scripts/spiderkingdom/spiders/nobite.lua")

-- PREDATOR
modimport("scripts/spiderkingdom/combat/recipes.lua")

-- COLONY
modimport("scripts/spiderkingdom/colony/recipes.lua")
modimport("scripts/spiderkingdom/colony/denroles.lua")
modimport("scripts/spiderkingdom/colony/workers.lua")
modimport("scripts/spiderkingdom/colony/logistics.lua")

-- COURIERS
modimport("scripts/spiderkingdom/couriers/mail.lua")
modimport("scripts/spiderkingdom/couriers/shard.lua")

-- Basic spider commands (after T1 and courier: their combat wrappers are chained)
modimport("scripts/spiderkingdom/spiders/commands.lua")

-- T4 Shared Squad (after T1 / courier / commands: its combat wrappers are the outermost)
modimport("scripts/spiderkingdom/spiders/squad.lua")

-- RIDER
modimport("scripts/spiderkingdom/mounts/groomer.lua")
modimport("scripts/spiderkingdom/mounts/dash.lua")
modimport("scripts/spiderkingdom/mounts/faithful.lua")

-- Client action collectors shared by several skills (one per component per mod)
modimport("scripts/spiderkingdom/networking/sleep_actions.lua")
modimport("scripts/spiderkingdom/networking/item_actions.lua")

-- ROYAL COURT
modimport("scripts/spiderkingdom/royalty/audience.lua")
modimport("scripts/spiderkingdom/royalty/recipes.lua")
modimport("scripts/spiderkingdom/royalty/throne.lua")
modimport("scripts/spiderkingdom/royalty/workshop.lua")
modimport("scripts/spiderkingdom/royalty/expedition.lua")
modimport("scripts/spiderkingdom/affinity/rituals.lua")
modimport("scripts/spiderkingdom/affinity/gear.lua")
