-- ROYAL COURT recipes. Gated by builder_skill, which builder and builder_replica already check
-- through skilltreeupdater:IsActivated (components/builder.lua, components/builder_replica.lua).

local Ingredient = GLOBAL.Ingredient
local TECH = GLOBAL.TECH
local Thrones = require("spiderkingdom/royalty/thrones")
local Workshops = require("spiderkingdom/royalty/workshops")

-- R2 Royal Throne: one usable throne per player per shard. canbuild runs on the server only
-- (builder:DoBuild), before any ingredient is taken; the refusal line is ACTIONFAIL.BUILD.SK_HASTHRONE
-- (royalty/throne.lua). A burnt throne does not count: hammer it or build a new one.
AddCharacterRecipe(Thrones.THRONE_PREFAB,
    {
        Ingredient("silk", 40),
        Ingredient("spidergland", 10),
        Ingredient("thulecite", 4),
        Ingredient("cutstone", 10),
    },
    TECH.NONE,
    {
        builder_skill = Thrones.SKILL,
        placer = Thrones.THRONE_PREFAB.."_placer",
        canbuild = function(recipe, builder, pt, rotation, station, skin)
            return not Thrones.HasThrone(builder.userid), "SK_HASTHRONE"
        end,
    },
    { "STRUCTURES" }
)

-- R2 Royal Invitation: the "five monster meat" the spec asks for to tame a queen, as a craft.
AddCharacterRecipe(Thrones.INVITATION_PREFAB,
    {
        Ingredient("papyrus", 1),
        Ingredient("monstermeat", 5),
        Ingredient("silk", 4),
    },
    TECH.NONE,
    {
        builder_skill = Thrones.SKILL,
    }
)

-- R3 Royal Workshop goods. TECH.SPIDERCRAFT_ONE is only provided by an open workshop (a Royal Throne
-- with its queen, owner online with R3: royalty/workshops.lua). nounlock: crafting one does not teach the
-- recipe, so these stay workshop-only (components/builder.lua UnlockRecipe / KnowsRecipe; the crafting
-- menu shows nounlock recipes only while CanPrototypeRecipe holds, widgets/redux/craftingmenu_hud.lua).
-- The stock mutators (recipes.lua, TECH.SPIDERCRAFT_ONE, builder_tag spiderwhisperer) need no change:
-- the workshop provides their tech, and crafting one there prototypes it like any research recipe.
AddCharacterRecipe(Workshops.JELLY_PREFAB,
    {
        Ingredient("honey", 2),
        Ingredient("spidergland", 2),
        Ingredient("monstermeat", 1),
    },
    TECH.SPIDERCRAFT_ONE,
    {
        builder_skill = Workshops.SKILL,
        nounlock = true,
        numtogive = 2,
    }
)

-- One Royal Egg Sack per brood type: the stock egg sack plus that type's mutators.
for _, brood in ipairs(Workshops.BROODS) do
    AddCharacterRecipe(Workshops.GetEggSackPrefab(brood),
        {
            Ingredient("spidereggsack", 1),
            Ingredient(brood.mutator, 2),
            Ingredient("silk", 6),
        },
        TECH.SPIDERCRAFT_ONE,
        {
            builder_skill = Workshops.SKILL,
            nounlock = true,
        },
        { "STRUCTURES" }
    )
end
