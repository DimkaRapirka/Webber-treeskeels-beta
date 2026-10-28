-- Spider Kingdom strings. English is the base; Russian replaces it when selected.

local STRINGS = GLOBAL.STRINGS

local function ShouldUseRussian()
    local option = GetModConfigData("language")
    if option == "ru" then
        return true
    elseif option == "en" then
        return false
    end
    local translator = GLOBAL.rawget(GLOBAL, "LanguageTranslator")
    if translator ~= nil and translator.defaultlang == "ru" then
        return true
    end

    -- Russification Pack for DST exposes this marker, including in local/GitHub installs.
    -- Optional globals must use rawget: strict.lua rejects reads of undeclared names.
    local mods = GLOBAL.rawget(GLOBAL, "mods")
    if type(mods) == "table" and GLOBAL.rawget(mods, "RussianLanguagePack") ~= nil then
        return true
    end

    -- Enablement is available even before the pack's modmain creates its marker.
    -- IsModEnabledAny also honours temporary and forced enable/disable flags (modindex.lua).
    local index = GLOBAL.rawget(GLOBAL, "KnownModIndex")
    if index ~= nil and (index:IsModEnabledAny("workshop-1240565842")
        or index:IsModEnabledAny("workshop-2286791724")) then
        return true
    end
    return false
end

local LANG =
{
    en =
    {
        PANELS =
        {
            SK_COLONY = "COLONY",
            SK_SYMBIOSIS = "SYMBIOSIS",
            SK_PREDATOR = "PREDATOR",
            SK_RIDER = "RIDER",
            SK_ROYAL = "ROYAL COURT",
        },

        IN_DEVELOPMENT = "\n[In development]",

        ACTIONS =
        {
            SK_SETDENROLE = "Assign role", SK_MAKECOURIER = "Make courier", SK_ROYALINVITE = "Invite to the throne",
            SK_ROYALEXPEDITION = { GENERIC = "Call the queen", CALL = "Call the queen", HOME = "Send the queen home" },
            SK_QUEENRITUAL = "Offer to the queen",
            SK_SETBROOD = "Choose the brood",
            SK_SQUAD = { GENERIC = "Lend bodyguards", LEND = "Lend bodyguards", RECALL = "Recall bodyguards" },
            SK_COMMAND = "Give spider orders", SK_SPIDERSTANCE = "Change orders", SK_SENDHOME = "Send spiders home",
            SK_HEARTTOGGLE = { GENERIC = "Toggle workers", PAUSE = "Let workers rest", RESUME = "Wake workers" },
        },
        COMMAND_WHEEL = {
            FOLLOW = "Follow", ATTACK = "Attack", DEFEND = "Defend", PASSIVE = "No fighting",
            STAY = "Stay here", HOME = "Return home", HOME_SPEECH = "Time to go home, friends!",
            OPEN = "Spider commands", CLOSE = "Close commands",
        },
        STANCES =
        {
            FOLLOW = "Everybody, follow me!",
            ATTACK = "Get 'em, everyone!",
            DEFEND = "Only bite back if they bite first!",
            PASSIVE = "No biting at all, please.",
            STAY = "Wait right here for us!",
        },
        ACTIONFAIL =
        {
            SK_SETDENROLE = { NOTOWNER = "That's someone else's den.", SAMEROLE = "It already does that job." },
            SK_SETBROOD = { NOTLIVING = "Only a living den can raise a brood.", NOTOWNER = "That's someone else's den.", NOWORKSHOP = "Our queen needs to be closer to see it." },
            SK_SENDHOME = { NOSPIDERS = "None of our friends are close enough.", FULL = "There's no room left in there." },
            SK_COMMAND = { WEBBERONLY = "Only our spider friends understand this.", NOSPIDERS = "None of our friends are close enough.", NOHOME = "Our friends need a suitable den with room nearby." },
            SK_SQUAD = { NOSPIDERS = "None of our friends are close enough.", LIMIT = "We've already lent out enough friends." },
            SK_HEARTTOGGLE = { NOTOWNER = "That's someone else's heart.", DORMANT = "It isn't beating right now." },
            SK_ROYALINVITE = { NOTHRONE = "We need to build her a throne first.", TOOFAR = "Our throne is too far away for her.", HASQUEEN = "We already have a queen!", BUSY = "She's too busy to listen right now." },
            SK_QUEENRITUAL = { NOTOWNER = "That's someone else's throne.", NOQUEEN = "There's no queen on this throne.", AWAY = "Her Majesty is out with us right now.", SAMEVARIANT = "She's already blessed by that side!", NOKEY = "We need to hold the right relic for this.", ENOUGH = "She has enough of that already.", BUSY = "Not now, the throne is in danger!" },
            SK_ROYALEXPEDITION = { NOTOWNER = "That's someone else's throne.", ALREADYOUT = "A queen is already traveling with us!", NOQUEEN = "Her Majesty isn't with us.", OTHERWORLD = "Her throne is in another world.", NOTHRONE = "She has no throne to go back to!", NOTHERTHRONE = "That isn't her throne.", BUSY = "She can't right now.", CANNOT = "Something keeps her from coming with us." },
        },
        SQUAD = { LENT = "%s is under your protection now, friends!", RECALLED = "Come back to us, friends!" },
        MAIL = { CROSSED = "Off you go to the other world, little courier!" },
        MOUNT = { PROGRESS = "Eat up, big friend! (%d/%d)", FULL_WAIT = "It's full! It just needs a little more time to grow.", GROWN = "Wow, look how big you are! Can we ride you?", DIED = "No! Our steed...!", OWNERONLY = "It only takes food from its own friend." },
        RITUAL = { PROGRESS = "Offerings so far: %s", PART = "%s %d/%d", SEPARATOR = ", ", DONE_LUNAR = "Her Majesty shines like the moon!", DONE_SHADOW = "Her Majesty is wrapped in shadow!" },
        ROYAL = { THRONE_OCCUPIED_NAME = "Royal Throne (Spider Queen)", BUILD_HASTHRONE = "We already have a throne!", INVITED = "Welcome home, Your Majesty!",
            THRONE_AWAY_NAME = "Royal Throne (Queen away)", EXPEDITION_CALLED = "Come along, Your Majesty!", EXPEDITION_HOME = "Time to go home, Your Majesty.", EXPEDITION_NOTHRONE = "Oh no, her throne is gone!",
            EGGSACK_NAME = "Royal Egg Sack: %s", EGGSACK_RECIPE_DESC = "Hatches into a den of %s.", EGGSACK_DESCRIBE = "A present from Her Majesty.",
            BROOD_SET = "This den will raise %s now!", BROOD_CLEARED = "Back to plain spiders, then.",
            WORKSHOP_NOTWEBBER = "I'd need a lot more legs to work this.",
            BROOD_NAMES = { SPIDER_WARRIOR = "Spider Warriors", SPIDER_HIDER = "Cave Spiders", SPIDER_SPITTER = "Spitter Spiders", SPIDER_DROPPER = "Dangling Depth Dwellers", SPIDER_HEALER = "Nurse Spiders", SPIDER_MOON = "Shattered Spiders" },
        },
        COLONYHEART = { SUMMARY = "Dens: %d. Workers: %d, haulers: %d. Free storage slots: %d.", SUMMARY_PAUSED = "Everyone is resting.", PAUSED = "Time for a rest, everyone!", RESUMED = "Back to work, friends!", BUILD_HASHEART = "Our colony already has a heart!" },
        DENROLE_NAMES = { STORAGE = "Storage", LIVING = "Living", LUMBER = "Lumber", FARM = "Farm", GUARD = "Guard" },

        SKILLS =
        {
            -- COLONY
            WEBBER_SK_COLONY_DENS_TITLE = "Master of Dens",
            WEBBER_SK_COLONY_DENS_DESC = "Learn to craft Spider Eggs that hatch straight into tier 2 and tier 3 Spider Dens.",
            WEBBER_SK_COLONY_ARCHITECTURE_TITLE = "Spider Architecture",
            WEBBER_SK_COLONY_ARCHITECTURE_DESC = "Give your den a role with an item: Boards - storage (9 slots), Monster Meat - living (+1 spider), Log - lumber, Seeds - farm, Stinger - guard (+50% defenders). Other roles have 4 slots.",
            WEBBER_SK_COLONY_WORKERS_TITLE = "Worker Brood",
            WEBBER_SK_COLONY_WORKERS_DESC = "Your lumber and farm dens hatch worker spiders (2-4 by den size). By day they chop trees or harvest bushes, grass and crops nearby and fill the den's storage.",
            WEBBER_SK_COLONY_LOGISTICS_TITLE = "Web Logistics",
            WEBBER_SK_COLONY_LOGISTICS_DESC = "Your storage dens hatch hauler spiders (1-2 by den size). By day they carry goods from your nearby lumber and farm dens to storage dens, preferring a den that already holds the same item.",
            WEBBER_SK_COLONY_PORTABLE_TITLE = "Portable Home",
            WEBBER_SK_COLONY_PORTABLE_DESC = "Learn to craft a Portable Cocoon: deploy it, sleep in it and pack it up again (10 uses).",
            WEBBER_SK_COLONY_HEART_TITLE = "Colony Heart",
            WEBBER_SK_COLONY_HEART_DESC = "Build a Colony Heart (one per player). Your dens near it form one network, and haulers serve all of it. Inspect the heart for a summary; use Twigs on it to rest or wake all its workers.",

            -- SYMBIOSIS
            WEBBER_SK_SYMBIOSIS_NOBITE_TITLE = "We Don't Bite",
            WEBBER_SK_SYMBIOSIS_NOBITE_DESC = "Your spiders stop attacking allies, no longer drain their sanity and ignore accidental hits.",
            WEBBER_SK_SYMBIOSIS_MAIL_TITLE = "Spider Mail",
            WEBBER_SK_SYMBIOSIS_MAIL_DESC = "Craft a Courier Kit and use it on one of your spiders. Fill the courier with items, right-click it and pick a spot on the map: it flies there, waits to be emptied and comes back. Pick a cave entrance or stairs and it delivers to the other world.",
            WEBBER_SK_SYMBIOSIS_COZY_TITLE = "Cozy Place",
            WEBBER_SK_SYMBIOSIS_COZY_DESC = "Allies can rest in your dens with a role and in your portable cocoons.",
            WEBBER_SK_SYMBIOSIS_SQUAD_TITLE = "Shared Squad",
            WEBBER_SK_SYMBIOSIS_SQUAD_DESC = "Right-click another player with a Spider Whistle on the cursor: up to two of your nearby spiders guard them. Do it again to call them back. They come back to you if that player leaves or dies.",

            -- PREDATOR
            WEBBER_SK_PREDATOR_CHITIN_TITLE = "Chitin Armor",
            WEBBER_SK_PREDATOR_CHITIN_DESC = "Take 8% less damage.",
            WEBBER_SK_PREDATOR_REFLEXES_TITLE = "Spider Reflexes",
            WEBBER_SK_PREDATOR_REFLEXES_DESC = "Learn to craft Spider Claws. While wielding them, lunge forward through enemies (8 s cooldown).",
            WEBBER_SK_PREDATOR_FANGS_TITLE = "Predator Fangs",
            WEBBER_SK_PREDATOR_FANGS_DESC = "Repeated attacks on the same target add stacking venom damage over time.",
            WEBBER_SK_PREDATOR_SPIT_TITLE = "Silk Spit",
            WEBBER_SK_PREDATOR_SPIT_DESC = "Learn to craft Silk Globs. Thrown webbing slows enemies and sends your spiders after them.",
            WEBBER_SK_PREDATOR_MOLTING_TITLE = "Molting",
            WEBBER_SK_PREDATOR_MOLTING_DESC = "After a heavy blow, gain extra protection for a short time.",
            WEBBER_SK_PREDATOR_PACK_TITLE = "One in the Pack",
            WEBBER_SK_PREDATOR_PACK_DESC = "Deal 15% more damage while one to three combat spiders are near you.",

            -- RIDER
            WEBBER_SK_RIDER_GROOMER_TITLE = "Spider Groomer",
            WEBBER_SK_RIDER_GROOMER_DESC = "Feed one of your Spider Warriors 10 pieces of meat over at least 2 days: it grows into a Spider Steed with 600 health that only you can ride (right-click it). It follows you and fights at your side; give it meat to heal it.",
            WEBBER_SK_RIDER_DASH_TITLE = "Cavalry Dash",
            WEBBER_SK_RIDER_DASH_DESC = "While riding your Spider Steed, double-tap a direction (or double-click) to dash forward. 6 second cooldown.",
            WEBBER_SK_RIDER_BATTLE_TITLE = "Battle Rider",
            WEBBER_SK_RIDER_BATTLE_DESC = "Your mounted attacks deal 20% more damage. Every 4th mounted hit also bites enemies around the target for half the damage; it never hurts your allies.",
            WEBBER_SK_RIDER_FAITHFUL_TITLE = "Faithful Mount",
            WEBBER_SK_RIDER_FAITHFUL_DESC = "Your Spider Steed carries a 4-slot saddlebag only you can open (click it), runs 10% faster and regenerates 2% health per second after 10 seconds out of combat. The bag travels with it between worlds.",

            -- ROYAL COURT
            WEBBER_SK_ROYAL_AUDIENCE_TITLE = "Royal Audience",
            WEBBER_SK_ROYAL_AUDIENCE_DESC = "Trade with Spider Queens. Offer Monster Meat, Meat, Honey, Pig Skin or Gold.",
            WEBBER_SK_ROYAL_THRONE_TITLE = "Royal Throne",
            WEBBER_SK_ROYAL_THRONE_DESC = "Build a Royal Throne and craft Royal Invitations. Give one to a calm Spider Queen near your throne and she moves in. One throne and one queen per player.",
            WEBBER_SK_ROYAL_WORKSHOP_TITLE = "Royal Workshop",
            WEBBER_SK_ROYAL_WORKSHOP_DESC = "While your queen sits on your throne, it becomes a Spider Care workshop: Webbers nearby can craft every mutator without befriending those spiders first. Unlocks Brood Jelly and Royal Egg Sacks. Use a mutator on your living den near the throne to choose its brood.",
            WEBBER_SK_ROYAL_EXPEDITION_TITLE = "Royal Expedition",
            WEBBER_SK_ROYAL_EXPEDITION_DESC = "Use the Spider Whistle on your throne to call your queen out: she follows you everywhere, even into the caves, and fights for you. Whistle at the throne again to send her home. While she is away, the throne's workshop is closed.",

            -- AFFINITY
            WEBBER_SK_LUNAR_AFFINITY_TITLE = "Lunar Affinity",
            WEBBER_SK_LUNAR_AFFINITY_DESC = "Align with the Moon: take 10% less lunar-aligned damage. You and your follower spiders deal 10% more damage to shadow-aligned targets. Ritual: holding an Enlightened Crown, offer 20 Moon Glass and 5 Pure Brilliance to your queen on her throne. A Lunar queen hits harder on expeditions and lets the throne craft lunar spider gear. Your spiders heal in moonlight (twice as fast at full moon), and your Shattered Spiders deal planar damage.",
            WEBBER_SK_SHADOW_AFFINITY_TITLE = "Shadow Affinity",
            WEBBER_SK_SHADOW_AFFINITY_DESC = "Align with the Shadows: take 10% less shadow-aligned damage. You and your follower spiders deal 10% more damage to lunar-aligned targets. Ritual: holding a Possessed Shadow Atrium, offer 10 Pure Horror and 20 Nightmare Fuel to your queen on her throne. A Shadow queen hits harder on expeditions and lets the throne craft shadow spider gear. Your spiders deal 20% more damage in darkness and heal by devouring the creatures they kill.",

            WEBBER_SK_ALLEGIANCE_LOCK_COUNT_DESC = "Learn 12 other skills to unlock an affinity.",
        },

        NAMES =
        {
            SK_SPIDEREGGSACK_2 = "Hardy Spider Eggs",
            SK_SPIDEREGGSACK_3 = "Mighty Spider Eggs",
            SK_COMMAND_WHISTLE = "Spider Command Whistle",
            SK_SPIDERCLAWS = "Spider Claws",
            SK_SILKGLOB = "Silk Glob",
            SK_PORTABLE_COCOON = "Portable Cocoon",
            SK_PORTABLE_COCOON_ITEM = "Portable Cocoon",
            SK_COURIERSPIDER = "Courier Spider",
            SK_COURIER_KIT = "Courier Kit",
            SK_ROYAL_THRONE = "Royal Throne",
            SK_ROYAL_INVITATION = "Royal Invitation",
            SK_COLONY_HEART = "Colony Heart",
            SK_SPIDER_MOUNT = "Spider Steed",
            SK_BROOD_JELLY = "Brood Jelly",
            SK_LUNAR_FANG = "Moonsilk Fang",
            SK_SHADOW_FANG = "Umbral Fang",
            SK_LUNAR_CARAPACE = "Moonsilk Carapace",
            SK_SHADOW_CARAPACE = "Umbral Carapace",
        },

        RECIPE_DESC =
        {
            SK_COMMAND_WHISTLE = "Choose orders for all your spiders.",
            SK_SPIDEREGGSACK_2 = "Hatches into a tier 2 den.",
            SK_SPIDEREGGSACK_3 = "Hatches into a tier 3 den.",
            SK_SPIDERCLAWS = "Pounce like a spider.",
            SK_SILKGLOB = "Sticky! Slows enemies down.",
            SK_PORTABLE_COCOON_ITEM = "A cozy nest to go.",
            SK_COURIER_KIT = "Turns one of your spiders into a courier.",
            SK_ROYAL_THRONE = "A seat fit for a Spider Queen.",
            SK_ROYAL_INVITATION = "Ask a Spider Queen to move into your throne.",
            SK_COLONY_HEART = "Links your nearby dens into one colony.",
            SK_BROOD_JELLY = "A royal treat that heals a spider completely.",
            SK_LUNAR_FANG = "Weave moonlight into a fang that bites the shadows.",
            SK_SHADOW_FANG = "Bind living nightmares into a fang that bites the moon.",
            SK_LUNAR_CARAPACE = "A silken shell against the moon's wrath.",
            SK_SHADOW_CARAPACE = "A silken shell against the shadows' wrath.",
        },

        DESCRIBE =
        {
            SK_COMMAND_WHISTLE = "Six little tunes for all our friends!",
            SK_SPIDEREGGSACK_2 = "They're already big and strong!",
            SK_SPIDEREGGSACK_3 = "A whole palace is waiting in there.",
            SK_SPIDERCLAWS = "Now we can pounce!",
            SK_SILKGLOB = "It sticks to everything. Even us.",
            SK_PORTABLE_COCOON = "Our little home away from home.",
            SK_PORTABLE_COCOON_ITEM = "We can sleep anywhere now!",
            SK_COURIERSPIDER = "Our fastest friend. It never loses a package!",
            SK_COURIER_KIT = "A little backpack for a little friend.",
            SK_ROYAL_THRONE = { GENERIC = "It's waiting for a queen.", OCCUPIED = "Shh, Her Majesty is resting.", WORKSHOP = "Her Majesty is ready to work with us!", AWAY = "Her Majesty is out exploring with us.", BURNING = "Save the throne!", BURNT = "Our poor throne..." },
            SK_ROYAL_INVITATION = "We wrote it in our very best handwriting.",
            SK_BROOD_JELLY = "Our friends love it. We kind of like it too.",
            SK_SPIDER_MOUNT = { GENERIC = "Our biggest, bestest friend! Giddy-up!", HURT = "Our poor friend needs some meat and a rest.", WILD = "It's looking for us, isn't it?" },
            SK_LUNAR_FANG = "Moonlight gives this fang a peculiar edge.",
            SK_SHADOW_FANG = "Even its edge casts a shadow.",
            SK_LUNAR_CARAPACE = "A surprisingly sturdy weave of silk and moonlight.",
            SK_SHADOW_CARAPACE = "The darkness seems tightly woven.",
            SK_COLONY_HEART = { GENERIC = "It beats for the whole colony.", DORMANT = "It's so quiet without us.", BURNING = "Save the heart!", BURNT = "Our colony lost its heart..." },
        },
    },

    ru =
    {
        PANELS =
        {
            SK_COLONY = "КОЛОНИЯ",
            SK_SYMBIOSIS = "СИМБИОЗ",
            SK_PREDATOR = "ХИЩНИК",
            SK_RIDER = "НАЕЗДНИК",
            SK_ROYAL = "КОРОЛЕВСКИЙ ДВОР",
        },

        IN_DEVELOPMENT = "\n[В разработке]",

        ACTIONS =
        {
            SK_SETDENROLE = "Назначить роль", SK_MAKECOURIER = "Сделать курьером", SK_ROYALINVITE = "Пригласить на трон",
            SK_ROYALEXPEDITION = { GENERIC = "Позвать королеву", CALL = "Позвать королеву", HOME = "Отправить королеву домой" },
            SK_QUEENRITUAL = "Поднести королеве",
            SK_SETBROOD = "Выбрать выводок",
            SK_SQUAD = { GENERIC = "Одолжить телохранителей", LEND = "Одолжить телохранителей", RECALL = "Отозвать телохранителей" },
            SK_HEARTTOGGLE = { GENERIC = "Переключить рабочих", PAUSE = "Отпустить рабочих отдыхать", RESUME = "Разбудить рабочих" },
            SK_COMMAND = "Отдать приказ паукам", SK_SPIDERSTANCE = "Сменить приказ", SK_SENDHOME = "Отправить пауков домой",
        },
        COMMAND_WHEEL = {
            FOLLOW = "Следовать", ATTACK = "Атаковать", DEFEND = "Защищать", PASSIVE = "Не вступать в бой",
            STAY = "Стоять на месте", HOME = "Домой", HOME_SPEECH = "Пора домой, друзья!",
            OPEN = "Команды паукам", CLOSE = "Закрыть команды",
        },
        STANCES =
        {
            FOLLOW = "Все за мной!",
            ATTACK = "Взять их!",
            DEFEND = "Кусайте, только если укусят нас!",
            PASSIVE = "Никого не кусать, пожалуйста.",
            STAY = "Ждите нас здесь!",
        },
        ACTIONFAIL =
        {
            SK_SETDENROLE = { NOTOWNER = "Это чужой кокон.", SAMEROLE = "Он уже этим занят." },
            SK_SETBROOD = { NOTLIVING = "Выводок растёт только в жилом коконе.", NOTOWNER = "Это чужой кокон.", NOWORKSHOP = "Наша королева должна быть поближе." },
            SK_SENDHOME = { NOSPIDERS = "Наших друзей нет рядом.", FULL = "Там больше нет места." },
            SK_COMMAND = { WEBBERONLY = "Этот свисток понимают только наши друзья.", NOSPIDERS = "Наших друзей нет рядом.", NOHOME = "Друзьям нужен подходящий кокон со свободным местом." },
            SK_SQUAD = { NOSPIDERS = "Наших друзей нет рядом.", LIMIT = "Мы и так одолжили достаточно друзей." },
            SK_HEARTTOGGLE = { NOTOWNER = "Это чужое сердце.", DORMANT = "Сейчас оно не бьётся." },
            SK_ROYALINVITE = { NOTHRONE = "Сначала нужно построить ей трон.", TOOFAR = "Наш трон слишком далеко от неё.", HASQUEEN = "У нас уже есть королева!", BUSY = "Ей сейчас не до нас." },
            SK_QUEENRITUAL = { NOTOWNER = "Это чужой трон.", NOQUEEN = "На этом троне нет королевы.", AWAY = "Её Величество сейчас путешествует с нами.", SAMEVARIANT = "Она уже благословлена этой стороной!", NOKEY = "Для этого нужно держать при себе нужную реликвию.", ENOUGH = "Этого ей уже хватит.", BUSY = "Не сейчас, трон в опасности!" },
            SK_ROYALEXPEDITION = { NOTOWNER = "Это чужой трон.", ALREADYOUT = "С нами уже путешествует королева!", NOQUEEN = "Её Величества нет с нами.", OTHERWORLD = "Её трон в другом мире.", NOTHRONE = "Ей некуда возвращаться!", NOTHERTHRONE = "Это не её трон.", BUSY = "Ей сейчас не до этого.", CANNOT = "Что-то не пускает её с нами." },
        },
        SQUAD = { LENT = "%s теперь под вашей защитой, друзья!", RECALLED = "Возвращайтесь к нам, друзья!" },
        MAIL = { CROSSED = "Лети в другой мир, маленький курьер!" },
        MOUNT = { PROGRESS = "Кушай, дружище! (%d/%d)", FULL_WAIT = "Он наелся! Теперь ему нужно чуть-чуть времени, чтобы вырасти.", GROWN = "Ух ты, какой ты большой! Можно на тебе покататься?", DIED = "Нет! Наш скакун...!", OWNERONLY = "Он берёт еду только у своего друга." },
        RITUAL = { PROGRESS = "Подношения: %s", PART = "%s %d/%d", SEPARATOR = ", ", DONE_LUNAR = "Её Величество сияет, как луна!", DONE_SHADOW = "Её Величество окутана тенью!" },
        ROYAL = { THRONE_OCCUPIED_NAME = "Королевский трон (королева пауков)", BUILD_HASTHRONE = "У нас уже есть трон!", INVITED = "Добро пожаловать домой, Ваше Величество!",
            THRONE_AWAY_NAME = "Королевский трон (королевы нет)", EXPEDITION_CALLED = "Идёмте с нами, Ваше Величество!", EXPEDITION_HOME = "Пора домой, Ваше Величество.", EXPEDITION_NOTHRONE = "Ой, её трона больше нет!",
            EGGSACK_NAME = "Королевские яйца: %s", EGGSACK_RECIPE_DESC = "Вырастает в кокон с выводком: %s.", EGGSACK_DESCRIBE = "Подарок от Её Величества.",
            BROOD_SET = "Теперь здесь вырастут: %s!", BROOD_CLEARED = "Снова обычные паучки.",
            WORKSHOP_NOTWEBBER = "Мне бы побольше лапок для этого.",
            BROOD_NAMES = { SPIDER_WARRIOR = "Пауки-воины", SPIDER_HIDER = "Пещерные пауки", SPIDER_SPITTER = "Пауки-плеваки", SPIDER_DROPPER = "Глубинные пауки", SPIDER_HEALER = "Пауки-медсёстры", SPIDER_MOON = "Расколотые пауки" },
        },
        COLONYHEART = { SUMMARY = "Коконов: %d. Рабочих: %d, носильщиков: %d. Свободных слотов на складах: %d.", SUMMARY_PAUSED = "Все отдыхают.", PAUSED = "Всем отдыхать!", RESUMED = "За работу, друзья!", BUILD_HASHEART = "У нашей колонии уже есть сердце!" },
        DENROLE_NAMES = { STORAGE = "склад", LIVING = "жилой", LUMBER = "дровосеки", FARM = "фермеры", GUARD = "сторожевой" },

        SKILLS =
        {
            WEBBER_SK_COLONY_DENS_TITLE = "Мастер коконов",
            WEBBER_SK_COLONY_DENS_DESC = "Открывает рецепты паучьих яиц, из которых сразу вырастает кокон 2-го или 3-го уровня.",
            WEBBER_SK_COLONY_ARCHITECTURE_TITLE = "Паучья архитектура",
            WEBBER_SK_COLONY_ARCHITECTURE_DESC = "Назначьте кокону роль предметом: доски — склад (9 слотов), монстрятина — жилой (+1 паук), бревно — дровосеки, семена — фермеры, жало — сторожевой (+50% защитников). У остальных ролей 4 слота.",
            WEBBER_SK_COLONY_WORKERS_TITLE = "Рабочий выводок",
            WEBBER_SK_COLONY_WORKERS_DESC = "Ваши коконы дровосеков и фермеров выводят пауков-работников (2–4 по размеру кокона). Днём они рубят деревья или собирают кусты, траву и урожай рядом и складывают добычу в кокон.",
            WEBBER_SK_COLONY_LOGISTICS_TITLE = "Паутинная логистика",
            WEBBER_SK_COLONY_LOGISTICS_DESC = "Ваши коконы-склады выводят пауков-носильщиков (1–2 по размеру кокона). Днём они переносят добычу из ближайших коконов дровосеков и фермеров на склады, выбирая склад, где такой предмет уже есть.",
            WEBBER_SK_COLONY_PORTABLE_TITLE = "Переносной дом",
            WEBBER_SK_COLONY_PORTABLE_DESC = "Открывает переносной кокон: поставьте, поспите в нём и сверните обратно (10 использований).",
            WEBBER_SK_COLONY_HEART_TITLE = "Сердце колонии",
            WEBBER_SK_COLONY_HEART_DESC = "Постройте сердце колонии (одно на игрока). Ваши коконы рядом с ним образуют одну сеть, и носильщики обслуживают её целиком. Осмотрите сердце, чтобы увидеть сводку; веточки на сердце отправляют всех его рабочих отдыхать или будят их.",

            WEBBER_SK_SYMBIOSIS_NOBITE_TITLE = "Мы не кусаемся",
            WEBBER_SK_SYMBIOSIS_NOBITE_DESC = "Ваши пауки не нападают на союзников, не снижают им рассудок и не реагируют на случайные удары.",
            WEBBER_SK_SYMBIOSIS_MAIL_TITLE = "Паучья почта",
            WEBBER_SK_SYMBIOSIS_MAIL_DESC = "Создайте набор курьера и примените к своему пауку. Положите в курьера вещи, ПКМ по нему и выберите точку на карте: он долетит туда, дождётся, пока его опустошат, и вернётся. Укажите вход в пещеру или лестницу — и он доставит груз в другой мир.",
            WEBBER_SK_SYMBIOSIS_COZY_TITLE = "Уютное место",
            WEBBER_SK_SYMBIOSIS_COZY_DESC = "Союзники могут отдыхать в ваших коконах с назначенной ролью и в переносных коконах.",
            WEBBER_SK_SYMBIOSIS_SQUAD_TITLE = "Общий отряд",
            WEBBER_SK_SYMBIOSIS_SQUAD_DESC = "ПКМ по другому игроку со свистком на курсоре: до двух ваших пауков рядом охраняют его. Повторно — отозвать. Если игрок уйдёт или погибнет, пауки вернутся к вам.",

            WEBBER_SK_PREDATOR_CHITIN_TITLE = "Хитиновая броня",
            WEBBER_SK_PREDATOR_CHITIN_DESC = "Получаемый урон снижен на 8%.",
            WEBBER_SK_PREDATOR_REFLEXES_TITLE = "Паучьи рефлексы",
            WEBBER_SK_PREDATOR_REFLEXES_DESC = "Открывает паучьи когти. С ними в руках можно сделать выпад вперёд сквозь врагов (перезарядка 8 с).",
            WEBBER_SK_PREDATOR_FANGS_TITLE = "Клыки хищника",
            WEBBER_SK_PREDATOR_FANGS_DESC = "Серия атак по одной цели накладывает накапливающийся яд.",
            WEBBER_SK_PREDATOR_SPIT_TITLE = "Шёлковый плевок",
            WEBBER_SK_PREDATOR_SPIT_DESC = "Открывает шёлковые комки. Брошенная паутина замедляет врагов и натравливает на них ваших пауков.",
            WEBBER_SK_PREDATOR_MOLTING_TITLE = "Линька",
            WEBBER_SK_PREDATOR_MOLTING_DESC = "После сильного удара вы ненадолго получаете дополнительную защиту.",
            WEBBER_SK_PREDATOR_PACK_TITLE = "Один из стаи",
            WEBBER_SK_PREDATOR_PACK_DESC = "+15% урона, пока рядом от одного до трёх боевых пауков.",

            WEBBER_SK_RIDER_GROOMER_TITLE = "Паучий конюх",
            WEBBER_SK_RIDER_GROOMER_DESC = "Откормите своего паука-воина: 10 кусков мяса, не меньше чем за 2 дня. Он вырастет в паука-скакуна (600 здоровья), на котором можете ездить только вы (ПКМ). Скакун ходит за вами и сражается рядом; мясо его лечит.",
            WEBBER_SK_RIDER_DASH_TITLE = "Кавалерийский рывок",
            WEBBER_SK_RIDER_DASH_DESC = "Верхом на пауке-скакуне дважды нажмите направление (или дважды кликните), чтобы сделать рывок вперёд. Перезарядка 6 секунд.",
            WEBBER_SK_RIDER_BATTLE_TITLE = "Боевой наездник",
            WEBBER_SK_RIDER_BATTLE_DESC = "Атаки верхом наносят на 20% больше урона. Каждый 4-й удар верхом ещё и кусает врагов вокруг цели на половину урона; союзников укус не задевает.",
            WEBBER_SK_RIDER_FAITHFUL_TITLE = "Верный скакун",
            WEBBER_SK_RIDER_FAITHFUL_DESC = "У паука-скакуна появляется седельная сумка на 4 ячейки, которую открываете только вы (клик по скакуну). Он бегает на 10% быстрее и через 10 секунд вне боя восстанавливает 2% здоровья в секунду. Сумка переезжает с ним между мирами.",

            WEBBER_SK_ROYAL_AUDIENCE_TITLE = "Королевская аудиенция",
            WEBBER_SK_ROYAL_AUDIENCE_DESC = "Торгуйте с королевой пауков: монстрятина, мясо, мёд, свиная кожа или золото.",
            WEBBER_SK_ROYAL_THRONE_TITLE = "Королевский трон",
            WEBBER_SK_ROYAL_THRONE_DESC = "Постройте королевский трон и создавайте королевские приглашения. Вручите приглашение спокойной королеве пауков рядом с троном — и она поселится в нём. Один трон и одна королева на игрока.",
            WEBBER_SK_ROYAL_WORKSHOP_TITLE = "Королевская мастерская",
            WEBBER_SK_ROYAL_WORKSHOP_DESC = "Пока королева сидит на троне, он становится мастерской «Забота о пауках»: Вебберы рядом могут создавать любые мутаторы, не приручая сначала этих пауков. Открывает желе выводка и королевские яйца. Примените мутатор к своему жилому кокону рядом с троном, чтобы выбрать его выводок.",
            WEBBER_SK_ROYAL_EXPEDITION_TITLE = "Королевская экспедиция",
            WEBBER_SK_ROYAL_EXPEDITION_DESC = "Примените паучий свисток к своему трону, чтобы позвать королеву: она следует за вами повсюду, даже в пещеры, и сражается за вас. Свисток по трону ещё раз — отправить её домой. Пока её нет, мастерская трона закрыта.",

            WEBBER_SK_LUNAR_AFFINITY_TITLE = "Лунная преданность",
            WEBBER_SK_LUNAR_AFFINITY_DESC = "Сторона Луны: на 10% меньше урона от лунных атак. Вы и ваши пауки наносите на 10% больше урона теневым существам. Ритуал: держа при себе корону Небесного чемпиона (Enlightened Crown), поднесите королеве на троне 20 лунного стекла и 5 чистого сияния. Лунная королева сильнее в походах, а трон позволяет создавать лунное паучье снаряжение. Ваши пауки лечатся в лунном свете (в полнолуние вдвое быстрее), а Расколотые пауки наносят планарный урон.",
            WEBBER_SK_SHADOW_AFFINITY_TITLE = "Теневая преданность",
            WEBBER_SK_SHADOW_AFFINITY_DESC = "Сторона Теней: на 10% меньше урона от теневых атак. Вы и ваши пауки наносите на 10% больше урона лунным существам. Ритуал: держа при себе одержимый теневой атриум (Possessed Shadow Atrium), поднесите королеве на троне 10 чистого ужаса и 20 топлива кошмаров. Теневая королева сильнее в походах, а трон позволяет создавать теневое паучье снаряжение. Ваши пауки наносят на 20% больше урона в темноте и лечатся, пожирая убитых существ.",

            WEBBER_SK_ALLEGIANCE_LOCK_COUNT_DESC = "Изучите 12 других навыков, чтобы открыть преданность.",
        },

        NAMES =
        {
            SK_SPIDEREGGSACK_2 = "Крепкие паучьи яйца",
            SK_SPIDEREGGSACK_3 = "Могучие паучьи яйца",
            SK_COMMAND_WHISTLE = "Командный паучий свисток",
            SK_SPIDERCLAWS = "Паучьи когти",
            SK_SILKGLOB = "Шёлковый комок",
            SK_PORTABLE_COCOON = "Переносной кокон",
            SK_PORTABLE_COCOON_ITEM = "Переносной кокон",
            SK_COURIERSPIDER = "Паук-курьер",
            SK_COURIER_KIT = "Набор курьера",
            SK_ROYAL_THRONE = "Королевский трон",
            SK_ROYAL_INVITATION = "Королевское приглашение",
            SK_COLONY_HEART = "Сердце колонии",
            SK_SPIDER_MOUNT = "Паук-скакун",
            SK_BROOD_JELLY = "Желе выводка",
            SK_LUNAR_FANG = "Лунный клык",
            SK_SHADOW_FANG = "Теневой клык",
            SK_LUNAR_CARAPACE = "Лунный панцирь",
            SK_SHADOW_CARAPACE = "Теневой панцирь",
        },

        RECIPE_DESC =
        {
            SK_COMMAND_WHISTLE = "Выбирайте приказы паукам через колесо.",
            SK_SPIDEREGGSACK_2 = "Вырастает в кокон 2-го уровня.",
            SK_SPIDEREGGSACK_3 = "Вырастает в кокон 3-го уровня.",
            SK_SPIDERCLAWS = "Прыгай, как паук.",
            SK_SILKGLOB = "Липкий! Замедляет врагов.",
            SK_PORTABLE_COCOON_ITEM = "Уютное гнёздышко с собой.",
            SK_COURIER_KIT = "Превращает вашего паука в курьера.",
            SK_ROYAL_THRONE = "Трон, достойный королевы пауков.",
            SK_ROYAL_INVITATION = "Пригласите королеву пауков в свой трон.",
            SK_COLONY_HEART = "Объединяет ближайшие коконы в одну колонию.",
            SK_BROOD_JELLY = "Королевское лакомство, полностью лечит паука.",
            SK_LUNAR_FANG = "Сплетите лунный свет в клык, разящий тени.",
            SK_SHADOW_FANG = "Скуйте из живых кошмаров клык, разящий луну.",
            SK_LUNAR_CARAPACE = "Шёлковый панцирь против гнева луны.",
            SK_SHADOW_CARAPACE = "Шёлковый панцирь против гнева теней.",
        },

        DESCRIBE =
        {
            SK_COMMAND_WHISTLE = "Шесть мелодий для наших друзей!",
            SK_SPIDEREGGSACK_2 = "Они уже большие и сильные!",
            SK_SPIDEREGGSACK_3 = "Внутри ждёт целый дворец.",
            SK_SPIDERCLAWS = "Теперь мы умеем прыгать!",
            SK_SILKGLOB = "Липнет ко всему. Даже к нам.",
            SK_PORTABLE_COCOON = "Наш маленький дом вдали от дома.",
            SK_PORTABLE_COCOON_ITEM = "Теперь мы можем спать где угодно!",
            SK_COURIERSPIDER = "Наш самый быстрый друг. Посылки он не теряет!",
            SK_COURIER_KIT = "Маленький рюкзачок для маленького друга.",
            SK_ROYAL_THRONE = { GENERIC = "Он ждёт свою королеву.", OCCUPIED = "Тсс, Её Величество отдыхает.", WORKSHOP = "Её Величество готова работать с нами!", AWAY = "Её Величество путешествует с нами.", BURNING = "Спасите трон!", BURNT = "Бедный наш трон..." },
            SK_ROYAL_INVITATION = "Мы писали самым красивым почерком.",
            SK_BROOD_JELLY = "Наши друзья его обожают. Мы, честно говоря, тоже.",
            SK_SPIDER_MOUNT = { GENERIC = "Наш самый большой и самый лучший друг! Но-о!", HURT = "Нашему другу нужно мясо и отдых.", WILD = "Он ведь нас ищет, правда?" },
            SK_LUNAR_FANG = "Лунный свет придаёт этому клыку особую остроту.",
            SK_SHADOW_FANG = "Даже его лезвие отбрасывает тень.",
            SK_LUNAR_CARAPACE = "Удивительно прочное плетение шёлка и лунного света.",
            SK_SHADOW_CARAPACE = "Кажется, тьма здесь плотно соткана.",
            SK_COLONY_HEART = { GENERIC = "Оно бьётся для всей колонии.", DORMANT = "Без нас оно затихает.", BURNING = "Спасите сердце!", BURNT = "Наша колония потеряла сердце..." },
        },
    },
}

local lang = ShouldUseRussian() and LANG.ru or LANG.en

for k, v in pairs(lang.PANELS) do
    STRINGS.SKILLTREE.PANELS[k] = v
end

STRINGS.SKILLTREE.WEBBER = STRINGS.SKILLTREE.WEBBER or {}
for k, v in pairs(lang.SKILLS) do
    STRINGS.SKILLTREE.WEBBER[k] = v
end
STRINGS.SKILLTREE.WEBBER.SK_IN_DEVELOPMENT = lang.IN_DEVELOPMENT

for k, v in pairs(lang.ACTIONS) do
    STRINGS.ACTIONS[k] = v
end
for k, v in pairs(lang.ACTIONFAIL) do
    STRINGS.CHARACTERS.GENERIC.ACTIONFAIL[k] = v
    STRINGS.CHARACTERS.WEBBER.ACTIONFAIL[k] = v
end
STRINGS.SK_DENROLE_NAMES = lang.DENROLE_NAMES
STRINGS.SK_STANCES = lang.STANCES
STRINGS.SK_COMMAND_WHEEL = lang.COMMAND_WHEEL
STRINGS.ACTIONS.USESPELLBOOK.SK_SPIDERS = lang.COMMAND_WHEEL.OPEN
STRINGS.ACTIONS.CLOSESPELLBOOK.SK_SPIDERS = lang.COMMAND_WHEEL.CLOSE
STRINGS.SK_ROYAL = lang.ROYAL
STRINGS.SK_SQUAD = lang.SQUAD
STRINGS.SK_COLONYHEART = lang.COLONYHEART
STRINGS.SK_MOUNT = lang.MOUNT
STRINGS.SK_MAIL = lang.MAIL
STRINGS.SK_RITUAL = lang.RITUAL
-- M1: merged into the stock GIVE fail table (assigning lang.ACTIONFAIL.GIVE would replace it).
for _, speech in ipairs({ STRINGS.CHARACTERS.GENERIC, STRINGS.CHARACTERS.WEBBER }) do
    if speech.ACTIONFAIL.GIVE ~= nil then
        speech.ACTIONFAIL.GIVE.SK_MOUNTOWNERONLY = lang.MOUNT.OWNERONLY
    end
end

for k, v in pairs(lang.NAMES) do
    STRINGS.NAMES[k] = v
end
for k, v in pairs(lang.RECIPE_DESC) do
    STRINGS.RECIPE_DESC[k] = v
end
for k, v in pairs(lang.DESCRIBE) do
    STRINGS.CHARACTERS.GENERIC.DESCRIBE[k] = v
    STRINGS.CHARACTERS.WEBBER.DESCRIBE[k] = v
end
