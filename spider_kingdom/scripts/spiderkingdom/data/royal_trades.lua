-- R1 Royal Audience trade table: item given by Webber -> reward from the Spider Queen.
--   loot      : prefab dropped by the queen, `count` times
--   follower  : creature spawned next to the queen that follows the giver
--   cooldown  : optional timer name; the trade is refused while it runs

return
{
    monstermeat = { loot = "silk", count = 3 },
    meat        = { loot = "spidergland", count = 2 },
    honey       = { follower = "spider_healer" },
    pigskin     = { follower = "spider_warrior" },
    goldnugget  = { loot = "spidereggsack", count = 1, cooldown = "sk_royal_eggsack_cd" },
}
