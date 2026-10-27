-- Shared helpers. Plain module: require("spiderkingdom/util").

local SKUtil = {}

-- Server: works for any player. Client: only meaningful for ThePlayer.
function SKUtil.HasSkill(inst, skill)
    local updater = inst ~= nil and inst.components.skilltreeupdater or nil
    return updater ~= nil and updater:IsActivated(skill) or false
end

function SKUtil.Log(...)
    if TUNING.SPIDERKINGDOM ~= nil and TUNING.SPIDERKINGDOM.DEBUG then
        print("[SpiderKingdom]", ...)
    end
end

return SKUtil
