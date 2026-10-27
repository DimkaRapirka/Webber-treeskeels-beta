-- K3 Worker Brood: what each profession works on. Shared data (server).
--   chop_tags / chop_cant : trees a lumber worker chops (workable CHOP)
--   pickup                : loose items a worker carries home
--   pick_prefabs / pick_tags : pickables a farm worker harvests (Pickable:Pick puts the loot in its inventory)

return
{
    lumber =
    {
        chop_must = { "CHOP_workable", "tree" },
        chop_cant = { "stump", "burnt", "fire", "smolder", "leif", "monster", "event_trigger", "INLIMBO", "NOCLICK" },
        pickup =
        {
            log = true, pinecone = true, acorn = true, twiggy_nut = true, twigs = true, charcoal = true,
        },
    },
    farm =
    {
        pick_must = { "pickable" },
        pick_cant = { "fire", "burnt", "INLIMBO", "NOCLICK", "intense", "flower", "mushroom_farm" },
        pick_prefabs =
        {
            berrybush = true, berrybush2 = true, berrybush_juicy = true,
            grass = true, sapling = true, sapling_moon = true, reeds = true,
        },
        pick_tags = { "farm_plant" },
        pickup =
        {
            berries = true, berries_juicy = true, cutgrass = true, twigs = true, cutreeds = true,
        },
    },
}
