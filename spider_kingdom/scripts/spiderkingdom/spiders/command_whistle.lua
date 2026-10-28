-- Craftable Webber command whistle. Native inventory spellbook RPC selects the command on the server.
local _G = GLOBAL
local action = _G.Action({ mount_valid = true })
action.id = "SK_COMMAND"
action.str = _G.STRINGS.ACTIONS.SK_COMMAND
action.fn = function(act)
    local doer, item = act.doer, act.invobject
    if doer == nil or doer.prefab ~= "webber" or doer:HasTag("playerghost")
        or (doer.components.health ~= nil and doer.components.health:IsDead())
        or item == nil or not item:IsValid() or item.prefab ~= "sk_command_whistle"
        or item.components.inventoryitem == nil or item.components.inventoryitem:GetGrandOwner() ~= doer
        or item.components.spellbook == nil or not item.components.spellbook:CanBeUsedBy(doer) then
        return false
    end
    return item.components.spellbook:CastSpell(doer)
end
AddAction(action)
AddStategraphActionHandler("wilson", _G.ActionHandler(action, "herd_followers"))
AddStategraphActionHandler("wilson_client", _G.ActionHandler(action, "herd_followers"))

-- Only this item gets command-specific inventory labels; preserve every other book's labels.
for _, id in ipairs({ "USESPELLBOOK", "CLOSESPELLBOOK" }) do
    local native = _G.ACTIONS[id]
    local oldstrfn = native.strfn
    native.strfn = function(act)
        if act.invobject ~= nil and act.invobject.prefab == "sk_command_whistle" then
            return "SK_SPIDERS"
        end
        return oldstrfn ~= nil and oldstrfn(act) or nil
    end
end

AddCharacterRecipe("sk_command_whistle", {
    _G.Ingredient("spider_whistle", 1),
    _G.Ingredient("silk", 4),
    _G.Ingredient("spidergland", 2),
}, _G.TECH.NONE, { builder_tag = "spiderwhisperer" }, { "TOOLS" })
