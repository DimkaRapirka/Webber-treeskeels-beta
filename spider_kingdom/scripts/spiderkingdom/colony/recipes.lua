-- COLONY recipes. Gated by builder_skill, which builder and builder_replica already check
-- through skilltreeupdater:IsActivated (components/builder.lua, components/builder_replica.lua).

local Ingredient = GLOBAL.Ingredient
local TECH = GLOBAL.TECH

-- K1 Master of Dens
AddCharacterRecipe("sk_spidereggsack_2",
    {
        Ingredient("silk", 16),
        Ingredient("spidergland", 6),
        Ingredient("papyrus", 3),
        Ingredient("monstermeat", 4),
    },
    TECH.NONE,
    {
        builder_skill = "webber_sk_colony_dens",
        allowautopick = true,
    },
    { "STRUCTURES" }
)

-- K5 Portable Home
AddCharacterRecipe("sk_portable_cocoon_item",
    {
        Ingredient("silk", 10),
        Ingredient("spidergland", 2),
        Ingredient("rope", 2),
    },
    TECH.NONE,
    {
        builder_skill = "webber_sk_colony_portable",
    },
    { "STRUCTURES" }
)

AddCharacterRecipe("sk_spidereggsack_3",
    {
        Ingredient("silk", 24),
        Ingredient("spidergland", 8),
        Ingredient("papyrus", 4),
        Ingredient("monstermeat", 6),
    },
    TECH.NONE,
    {
        builder_skill = "webber_sk_colony_dens",
        allowautopick = true,
    },
    { "STRUCTURES" }
)
