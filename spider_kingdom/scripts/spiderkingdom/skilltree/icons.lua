-- Skill tree icons (Phase 6): one texture per skill in images/sk_skilltree_icons.xml, named after the skill.
-- Registered in spiderkingdom/visuals.lua; art sources and packer in art_src/ (skill_icons, tools/pack_atlas.py).

local SKILLS =
{
    "webber_sk_colony_dens", "webber_sk_colony_architecture", "webber_sk_colony_workers",
    "webber_sk_colony_logistics", "webber_sk_colony_portable", "webber_sk_colony_heart",
    "webber_sk_symbiosis_nobite", "webber_sk_symbiosis_mail", "webber_sk_symbiosis_cozy", "webber_sk_symbiosis_squad",
    "webber_sk_predator_chitin", "webber_sk_predator_reflexes", "webber_sk_predator_fangs",
    "webber_sk_predator_spit", "webber_sk_predator_molting", "webber_sk_predator_pack",
    "webber_sk_rider_groomer", "webber_sk_rider_dash", "webber_sk_rider_battle", "webber_sk_rider_faithful",
    "webber_sk_royal_audience", "webber_sk_royal_throne", "webber_sk_royal_workshop", "webber_sk_royal_expedition",
    "webber_sk_lunar_affinity", "webber_sk_shadow_affinity",
}

local ALL = {}
local BY_SKILL = {}
for _, skill in ipairs(SKILLS) do
    BY_SKILL[skill] = skill -- icon name without ".tex" (skilltreebuilder.lua adds it)
    table.insert(ALL, skill..".tex")
end

return
{
    SKILLS = SKILLS,
    ALL = ALL,
    BY_SKILL = BY_SKILL,
}
