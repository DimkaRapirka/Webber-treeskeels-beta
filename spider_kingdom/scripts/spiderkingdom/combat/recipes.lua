-- PREDATOR recipes, gated by builder_skill.

local Ingredient = GLOBAL.Ingredient
local TECH = GLOBAL.TECH

-- B2 Spider Reflexes
AddCharacterRecipe("sk_spiderclaws",
    {
        Ingredient("silk", 4),
        Ingredient("stinger", 6),
        Ingredient("twigs", 2),
    },
    TECH.NONE,
    {
        builder_skill = "webber_sk_predator_reflexes",
    },
    { "WEAPONS" }
)

-- B4 Silk Spit
AddCharacterRecipe("sk_silkglob",
    {
        Ingredient("silk", 2),
        Ingredient("spidergland", 1),
    },
    TECH.NONE,
    {
        builder_skill = "webber_sk_predator_spit",
        numtogive = 3,
    },
    { "WEAPONS" }
)
