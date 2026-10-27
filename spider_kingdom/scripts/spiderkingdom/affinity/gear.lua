local _G = GLOBAL
local Ingredient = _G.Ingredient

-- Affinity gear requires the matching skill and a Royal Throne providing SPIDERCRAFT level 2.
-- nounlock keeps every craft at the throne; CHARACTER matches the Royal Workshop recipes.
-- Official inventory images resolve their own atlases, as in royalty/recipes.lua.
AddRecipe2("sk_lunar_fang",
    {
        Ingredient("purebrilliance", 2),
        Ingredient("moonglass", 4),
        Ingredient("silk", 6),
    },
    { SPIDERCRAFT = 2 },
    {
        nounlock = true,
        builder_skill = "webber_sk_lunar_affinity",
    },
    { "CHARACTER" }
)

AddRecipe2("sk_lunar_carapace",
    {
        Ingredient("purebrilliance", 3),
        Ingredient("moonglass", 6),
        Ingredient("silk", 10),
    },
    { SPIDERCRAFT = 2 },
    {
        nounlock = true,
        builder_skill = "webber_sk_lunar_affinity",
    },
    { "CHARACTER" }
)

AddRecipe2("sk_shadow_fang",
    {
        Ingredient("horrorfuel", 2),
        Ingredient("nightmarefuel", 6),
        Ingredient("silk", 6),
    },
    { SPIDERCRAFT = 2 },
    {
        nounlock = true,
        builder_skill = "webber_sk_shadow_affinity",
    },
    { "CHARACTER" }
)

AddRecipe2("sk_shadow_carapace",
    {
        Ingredient("horrorfuel", 3),
        Ingredient("nightmarefuel", 8),
        Ingredient("silk", 10),
    },
    { SPIDERCRAFT = 2 },
    {
        nounlock = true,
        builder_skill = "webber_sk_shadow_affinity",
    },
    { "CHARACTER" }
)
