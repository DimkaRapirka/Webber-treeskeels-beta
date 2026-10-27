-- Spider Kingdom balance values. Everything tunable lives here.

TUNING.SPIDERKINGDOM =
{
    DEBUG = GetModConfigData("debug") == true,

    -- Affinity: same threshold as the official trees (e.g. wurt_allegiance_lock_1).
    AFFINITY_SKILLS_REQUIRED = 12,

    -- B1 Chitin Armor: multiplier on damage taken, applied after armor.
    CHITIN_DAMAGE_TAKEN_MULT = 0.92,

    -- B3 Predator Fangs: the first hit starts the chain, each further hit adds a stack.
    FANGS_CHAIN_WINDOW = 3,
    FANGS_MAX_STACKS = 3,
    FANGS_DAMAGE_PER_STACK = 2,
    FANGS_TICK_PERIOD = 1,
    FANGS_DURATION = 5,

    -- B5 Molting
    MOLTING_HIT_THRESHOLD = 0.2, -- share of max health in a single hit
    MOLTING_DAMAGE_TAKEN_MULT = 0.7,
    MOLTING_DURATION = 5,
    MOLTING_COOLDOWN = 30,

    -- B2 Spider Reflexes: Spider Claws weapon with the official lunge as its AoE spell.
    CLAWS_DAMAGE = 27,
    CLAWS_USES = 150,
    REFLEXES_LUNGE_DAMAGE = 34,
    REFLEXES_COOLDOWN = 8,

    -- B4 Silk Spit: Silk Glob throwable.
    SILKSPIT_RADIUS = 2.5,
    SILKSPIT_SPEED_MULT = 0.6,
    SILKSPIT_SLOW_DURATION = 4,
    SILKSPIT_MARK_DURATION = 6,
    SILKSPIT_SPIDER_RADIUS = 15,

    -- B6 One in the Pack
    PACK_MIN = 1,
    PACK_MAX = 3,
    PACK_RADIUS = 12,
    PACK_DAMAGE_MULT = 1.15,
    PACK_REFRESH_PERIOD = 1,

    -- T2 Spider Mail
    MAIL_SPEED = 8,                        -- flight speed (units per second), like a WX delivery drone trip
    MAIL_WAIT_TIME = TUNING.TOTAL_DAY_TIME, -- how long a courier waits at the destination before flying back
    MAIL_REJOIN_DIST = 12,                 -- a waiting courier rejoins its owner who comes this close
    MAIL_PORTAL_RADIUS = 8,                -- a map point this close to an open world portal sends it across
    MAIL_PORTAL_EXIT_DIST = 3,             -- lands this far from the portal on the other side
    MAIL_SHARD_RESEND = 10,                -- seconds between sends of an unanswered parcel
    MAIL_SHARD_RETRY = TUNING.TOTAL_DAY_TIME, -- after the other shard refused it, wait this long to try again
    MAIL_SAY_DIST = 20,                    -- the owner comments the crossing this close
    MAIL_SHARD_FORCE_SAVE = true,          -- request a world save after a crossing step instead of waiting
                                           -- for the daily autosave (components/sk_mailregistry.lua)
    MAIL_SHARD_SAVE_DELAY = 3,             -- seconds; coalesces requests into one save

    -- Basic spider commands
    COMMAND_ATTACK_RADIUS = 10, -- "attack": spiders look for hostiles this close to Webber
    COMMAND_HOME_RADIUS = 16,   -- "send home": spiders this close to Webber move into the den

    -- T4 Shared Squad
    SQUAD_MAX_GUARDS = 2,     -- spiders one Webber can have lent out at a time (over all players)
    SQUAD_LEND_RADIUS = 12,   -- only spiders this close to Webber are lent
    SQUAD_RELEASE_DELAY = 1,  -- seconds after joining / revival before stored spiders come back

    -- T1 We Don't Bite: how long a deliberate PvP attacker stays a valid target.
    NOBITE_PROVOKE_TIME = 10,

    -- K3 Worker Brood
    WORKERS_PER_STAGE = { 2, 3, 4 }, -- by den stage
    WORKER_SPAWN_TIME = 60,          -- seconds between new workers while below the limit
    WORKER_RADIUS = 12,              -- work area around the den
    WORKER_CARRY_SLOTS = 3,          -- inventory slots filled before a trip home
    WORKER_WORK_PERIOD = 1.5,        -- seconds per chop / harvest
    WORKER_IDLE_SEARCH_PERIOD = 5,   -- seconds between searches after finding nothing

    -- K4 Web Logistics
    LOGISTICS_RADIUS = 20,           -- without a heart: dens a storage den's haulers serve
    HAULERS_PER_STAGE = { 1, 1, 2 }, -- by storage den stage
    LOGISTICS_SEARCH_PERIOD = 5,     -- seconds between retries when nothing to haul / no room
    LOGISTICS_TRIP_TIME = 40,        -- a den not reached in time is skipped for a while

    -- K6 Colony Heart
    HEART_RADIUS = 30,               -- the owner's dens this close to the heart form one network
    HEART_WORK = 4,                  -- hammer hits

    -- K5 Portable Home (same as Walter's portable tent)
    PORTABLE_COCOON_USES = TUNING.PORTABLE_TENT_USES,

    -- R2 Royal Throne
    ROYAL_THRONE_INVITE_RANGE = 20,   -- max queen-to-throne distance for an invitation
    ROYAL_THRONE_WALK_TIME = 12,      -- seconds of walking before she is placed inside anyway
    ROYAL_THRONE_ARRIVE_DIST = 4,     -- she enters when this close to the throne
    ROYAL_THRONE_RELEASE_RADIUS = 4,
    ROYAL_THRONE_WORK = 6,            -- hammer hits

    -- R3 Royal Workshop
    ROYAL_WORKSHOP_BROOD_RANGE = 25,  -- den-to-open-workshop distance for choosing / keeping a brood
    BROOD_JELLY_HEALTH = TUNING.HEALING_MEDSMALL,
    BROOD_JELLY_HUNGER = TUNING.CALORIES_SMALL,
    BROOD_JELLY_SANITY = TUNING.SANITY_SMALL,

    -- M1 Spider Groomer
    MOUNT_FEED_NEEDED = 10,      -- meat-type meals for a Spider Warrior to grow into a Spider Steed
    MOUNT_MIN_DAYS = 2,          -- world days from the first meal before it may grow
    MOUNT_SCALE = 1,             -- on foot it is the ridden model (beefalo-sized), drawn at the rider's scale
    MOUNT_HEALTH = 600,
    MOUNT_DAMAGE = 34,           -- also the rider's melee damage while mounted (combat.lua CalcDamage), = beefalo
    MOUNT_ATTACK_PERIOD = 3,
    MOUNT_WALK_SPEED = 5,
    MOUNT_RUN_SPEED = 7,         -- the rider's speed (copied into player_classified.riderrunspeed on mount)
    MOUNT_FEED_HEAL = 60,        -- health per meat-type meal from its owner
    MOUNT_TARGET_DIST = 10,      -- defends against enemies targeting the owner / itself this close to the owner
    MOUNT_KEEP_TARGET_DIST = 20, -- drops a target when this far from the owner
    MOUNT_RECLAIM_RADIUS = 20,   -- a steed that lost its leader rejoins its owner this close

    -- M2 Cavalry Dash
    MOUNT_DASH_COOLDOWN = 6,     -- seconds between dashes (stock Woby dash states, mounts/dash.lua)

    -- M3 Battle Rider
    MOUNT_BATTLE_DAMAGE_MULT = 1.2, -- on the steed's combat while its owner rides it (mounted damage = steed's)
    MOUNT_BITE_EVERY = 4,           -- every Nth mounted hit also bites around the target
    MOUNT_BITE_RADIUS = 2,
    MOUNT_BITE_DAMAGE_MULT = 0.5,   -- of the hit that triggered it

    -- M4 Faithful Mount
    MOUNT_REGEN_PERCENT = 0.02,      -- of max health per MOUNT_REGEN_PERIOD
    MOUNT_REGEN_PERIOD = 1,
    MOUNT_REGEN_DELAY = 10,          -- seconds without hitting or being hit (steed or its rider)
    MOUNT_FAITHFUL_SPEED_MULT = 1.1, -- on MOUNT_RUN_SPEED

    -- R4 Royal Expedition
    ROYAL_EXPEDITION_FOLLOW_MIN = 4,
    ROYAL_EXPEDITION_FOLLOW_TARGET = 6,
    ROYAL_EXPEDITION_FOLLOW_MAX = 10,
    ROYAL_EXPEDITION_CHASE_TIME = 8,
    ROYAL_EXPEDITION_LEASH = 20,        -- drops a target when this far from Webber
    ROYAL_EXPEDITION_DEFEND_RANGE = 12, -- attacks whoever targets Webber / her within this range
    ROYAL_EXPEDITION_WALK_RANGE = 30,   -- farther from the throne: she appears inside at once
    ROYAL_EXPEDITION_SKILL_CHECK = 5,   -- s, owner without R4 -> she goes home when she can
    ROYAL_EXPEDITION_SPEED_MULT = 2.5,  -- stock queen walk speed is 1.75

    -- Affinity: same multipliers as the official allegiance passives (TUNING.SKILLS.WURT.ALLEGIANCE_*)
    AFFINITY_RESIST = 0.9,
    AFFINITY_BONUS = 1.1,
    AFFINITY_SPIDER_BONUS = 1.1,

    -- 5.6 Unique spider interactions (spiders/affinity.lua), follower spiders only
    AFFINITY_SPIDER_TICK = 2,             -- seconds between moonlight / darkness checks
    AFFINITY_MOON_REGEN = 2,              -- health per tick at night on the surface, moon not new
    AFFINITY_FULLMOON_REGEN_MULT = 2,
    AFFINITY_SHATTERED_PLANAR = 10,       -- planar damage bonus of a Shattered Spider (its spikes too)
    AFFINITY_DARK_LIGHT = 0.1,            -- light level below which a spider is "in darkness"
    AFFINITY_DARK_DAMAGE_MULT = 1.2,
    AFFINITY_FEAST_PERCENT = 0.2,         -- of the victim's max health, healed on a kill
    AFFINITY_FEAST_MAX = 40,

    -- Affinity rituals (Phase 5.3): materials per side (the key item is only checked, never spent)
    QUEEN_RITUAL_LUNAR = { moonglass = 20, purebrilliance = 5 },
    QUEEN_RITUAL_SHADOW = { horrorfuel = 10, nightmarefuel = 20 },
    -- Variant queen on an R4 expedition while her owner has the matching affinity
    QUEEN_VARIANT_PLANAR = 20,  -- planar damage bonus
    QUEEN_VARIANT_BONUS = 1.1,  -- damage mult vs the opposite alignment
    QUEEN_VARIANT_RESIST = 0.9, -- damage taken mult from her own alignment

    -- Affinity gear (Phase 5.4, prefabs/sk_affinity_gear.lua): crafted at a ritual throne (SPIDERCRAFT 2)
    AFFINITY_FANG_DAMAGE = 50,          -- Dark Sword 68, Brightshade 38 + 30 planar
    AFFINITY_FANG_PLANAR = 15,
    AFFINITY_FANG_USES = 150,
    AFFINITY_CARAPACE_CONDITION = 800,
    AFFINITY_CARAPACE_ABSORB = 0.85,
    AFFINITY_CARAPACE_PLANAR = 5,
    AFFINITY_GEAR_BONUS = 1.1,          -- fang vs the opposite alignment
    AFFINITY_GEAR_RESIST = 0.9,         -- carapace vs its own alignment

    -- R1 Royal Audience
    ROYAL_EGGSACK_COOLDOWN = TUNING.TOTAL_DAY_TIME * 2,
    ROYAL_SPAWN_RADIUS = 3,
}
