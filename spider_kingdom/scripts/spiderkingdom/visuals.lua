-- Phase 6 graphics: mod-wide assets and UI atlases (modimport, runs on server and client).
-- Sources and build tools: art_src/ (not loaded by the game). Prefab-specific anims stay in each prefab's assets.

local _G = GLOBAL

local function AddAsset(kind, path)
    table.insert(Assets, Asset(kind, path))
end

-- Skill tree: 26 icons in one atlas, the tree background (625x384 like the official ones,
-- widgets/redux/skilltreewidget.lua BG_WIDTH_ART / BG_HEIGHT_ART).
local ICONS_ATLAS = "images/sk_skilltree_icons.xml"
local BG_ATLAS = "images/sk_skilltree_bg.xml"

AddAsset("ATLAS", ICONS_ATLAS)
AddAsset("IMAGE", "images/sk_skilltree_icons.tex")
AddAsset("ATLAS", BG_ATLAS)
AddAsset("IMAGE", "images/sk_skilltree_bg.tex")

-- One entry per icon: the skill tree looks up icon atlases by texture name (simutil.lua GetSkilltreeIconAtlas).
local SKILL_ICONS = require("spiderkingdom/skilltree/icons")
for _, tex in ipairs(SKILL_ICONS.ALL) do
    RegisterSkilltreeIconsAtlas(ICONS_ATLAS, tex)
end
RegisterSkilltreeBGForCharacter(BG_ATLAS, "webber")

-- Spider Queen variants (affinity/rituals_common.lua VARIANTS[*].build; bank "spider_queen").
AddAsset("ANIM", "anim/sk_spider_queen_lunar.zip")
AddAsset("ANIM", "anim/sk_spider_queen_shadow.zip")

-- Mobs: job hats of workers and the courier cap (stock "swap_hat" slot), the shared structure bank and the
-- den role models (data/den_roles.lua; vanilla spiderden prefab, so not in a mod prefab's assets).
AddAsset("ANIM", "anim/sk_spider_hats.zip")
for _, job in ipairs({ "lumber", "farm", "hauler" }) do
    AddAsset("ANIM", "anim/sk_spider_worker_"..job..".zip") -- components/sk_worker.lua BUILDS
end
AddAsset("ANIM", "anim/sk_cocoon.zip")
for _, build in ipairs({ "sk_cocoon_base", "sk_cocoon_storage", "sk_cocoon_living", "sk_cocoon_lumber", "sk_cocoon_farm", "sk_cocoon_guard" }) do
    AddAsset("ANIM", "anim/"..build..".zip")
end

-- Inventory icons: one atlas, element = prefab name (the stock default inventory image and recipe image name),
-- found through the stock lookup (simutil.lua GetInventoryItemAtlas). Item builds are in each prefab's assets.
local INVENTORY_ATLAS = "images/sk_inventoryimages.xml"
AddAsset("ATLAS", INVENTORY_ATLAS)
AddAsset("IMAGE", "images/sk_inventoryimages.tex")
for _, prefab in ipairs({
    "sk_spidereggsack_2", "sk_spidereggsack_3",
    "sk_royal_eggsack_warrior", "sk_royal_eggsack_hider", "sk_royal_eggsack_spitter",
    "sk_royal_eggsack_dropper", "sk_royal_eggsack_healer", "sk_royal_eggsack_moon",
    "sk_silkglob", "sk_portable_cocoon_item", "sk_courier_kit", "sk_royal_invitation", "sk_brood_jelly",
    "sk_spiderclaws", "sk_lunar_fang", "sk_shadow_fang", "sk_lunar_carapace", "sk_shadow_carapace",
    "sk_royal_throne", "sk_colony_heart", -- crafting menu pictures of the structures
}) do
    RegisterInventoryItemAtlas(INVENTORY_ATLAS, prefab..".tex")
end
