-- onactivate / ondeactivate per skill id. Called on the server only (skilltreeupdater:ActivateSkill_Server).
-- Every handler must be idempotent: it also runs on load with fromload = true.

local Affinity = require("spiderkingdom/affinity/affinity")
local Fangs = require("spiderkingdom/combat/fangs")
local Molting = require("spiderkingdom/combat/molting")
local NoBite = require("spiderkingdom/spiders/nobite_common")
local Pack = require("spiderkingdom/combat/pack")
local Ownership = require("spiderkingdom/colony/ownership")
local Network = require("spiderkingdom/colony/network")
local Squad = require("spiderkingdom/spiders/squad_common")
local Workshops = require("spiderkingdom/royalty/workshops")
local Expeditions = require("spiderkingdom/royalty/expeditions")

local CHITIN_KEY = "sk_chitin"

local function TagSkill(tag)
    return {
        onactivate = function(inst, fromload) inst:AddTag(tag) end,
        ondeactivate = function(inst, fromload) inst:RemoveTag(tag) end,
    }
end

local function Wrap(system)
    return {
        onactivate = function(inst, fromload) system.Enable(inst) end,
        ondeactivate = function(inst, fromload) system.Disable(inst) end,
    }
end

local HANDLERS =
{
    -- B1 Chitin Armor
    webber_sk_predator_chitin =
    {
        onactivate = function(inst, fromload)
            local combat = inst.components.combat
            if combat ~= nil then
                combat.externaldamagetakenmultipliers:SetModifier(inst, TUNING.SPIDERKINGDOM.CHITIN_DAMAGE_TAKEN_MULT, CHITIN_KEY)
            end
        end,
        ondeactivate = function(inst, fromload)
            local combat = inst.components.combat
            if combat ~= nil then
                combat.externaldamagetakenmultipliers:RemoveModifier(inst, CHITIN_KEY)
            end
        end,
    },

    -- B3 Predator Fangs
    webber_sk_predator_fangs = Wrap(Fangs),

    -- B5 Molting
    webber_sk_predator_molting = Wrap(Molting),

    -- B6 One in the Pack
    webber_sk_predator_pack = Wrap(Pack),

    -- B2 Spider Reflexes / B4 Silk Spit: recipes gated by builder_skill; the claws' lunge
    -- also checks the owner's skill (prefabs/sk_spiderclaws.lua).

    -- T1 We Don't Bite
    webber_sk_symbiosis_nobite = Wrap(NoBite),

    -- K2 Spider Architecture: the tag lets the client offer SK_SETDENROLE; the server re-checks the skill.
    webber_sk_colony_architecture = TagSkill("sk_architect"),

    -- T2 Spider Mail: the tag lets the client offer the mail actions; the server re-checks the skill.
    webber_sk_symbiosis_mail = TagSkill("sk_mailer"),

    -- T4 Shared Squad: the tag lets the client offer SK_SQUAD; respec recalls the bodyguards.
    webber_sk_symbiosis_squad = Wrap(Squad),

    -- T3 Cozy Place: tags the owner's dens with a role and portable cocoons "sk_cozy".
    webber_sk_symbiosis_cozy = Wrap(Ownership.Cozy),

    -- K3 Worker Brood: tags the owner's dens "sk_workforce" (colony/ownership.lua, colony/workers.lua).
    webber_sk_colony_workers = Wrap(Ownership.Workforce),

    -- K4 Web Logistics: tags the owner's dens "sk_logistics"; storage dens raise haulers.
    webber_sk_colony_logistics = Wrap(Ownership.Logistics),

    -- K6 Colony Heart: player tag "sk_heartkeeper" (twigs action) + "sk_heartlink" on the owner's hearts.
    webber_sk_colony_heart = Wrap(Network.HeartSkill),

    -- K5 Portable Home: recipe gated by builder_skill, no handler needed.

    -- R2 Royal Throne: the tag lets the client offer SK_ROYALINVITE; the server re-checks the skill.
    webber_sk_royal_throne = TagSkill("sk_monarch"),

    -- R3 Royal Workshop: opens the owner's throne as a SPIDERCRAFT prototyper while he is online;
    -- tags him "sk_royalartisan" for SK_SETBROOD (royalty/workshops.lua).
    webber_sk_royal_workshop = Wrap(Workshops),

    -- R4 Royal Expedition: tag "sk_regent" for SK_ROYALEXPEDITION; respec sends a queen out with him home.
    webber_sk_royal_expedition = Wrap(Expeditions),

    -- M1 Spider Groomer: the tag lets the client offer MOUNT on the own steed (mounts/groomer.lua);
    -- steeds watch their owner's skill themselves (components/sk_spidermount.lua).
    webber_sk_rider_groomer = TagSkill("sk_groomer"),

    -- M2 Cavalry Dash: the tag lets both sides build the double-tap DASH (mounts/dash.lua).
    webber_sk_rider_dash = TagSkill("sk_cavalry"),

    -- Lunar / Shadow Affinity: player allegiance passives and follower spider damage (affinity/affinity.lua).
    webber_sk_lunar_affinity = Wrap(Affinity.Lunar),
    webber_sk_shadow_affinity = Wrap(Affinity.Shadow),

    -- K1 Master of Dens: recipes are gated by builder_skill, no handler needed.
    -- R1 Royal Audience: checked by the queen's trader on the server, no handler needed.
    -- M3 Battle Rider, M4 Faithful Mount: steeds watch their owner's skills (components/sk_spidermount.lua).
}

return HANDLERS
