-- Registers the Spider Kingdom tree for the stock "webber" prefab.
-- Runs at modmain time on both server and client: the client needs the same definitions for the UI and validation.

local skilltree_defs = require("prefabs/skilltree_defs")
local BuildSkillsData = require("spiderkingdom/skilltree/skilltree_webber")

if skilltree_defs.SKILLTREE_DEFS.webber ~= nil then
    print("[SpiderKingdom] WARNING: a skill tree for webber already exists (official update or another mod). It is being replaced by Spider Kingdom.")
end

local data = BuildSkillsData(skilltree_defs.FN)

skilltree_defs.CreateSkillTreeFor("webber", data.SKILLS)
skilltree_defs.SKILLTREE_ORDERS.webber = data.ORDERS

-- New keys are flagged automatically by SKILLTREE_DEFS.__newindex, but an existing key would not be.
-- Modded trees must never be pushed to the Klei online profile (skilltreedata:UpdateSaveState).
skilltree_defs.SKILLTREE_METAINFO.webber.modded = true
