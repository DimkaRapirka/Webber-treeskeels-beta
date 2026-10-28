-- Native spellbook / Wheel UI. Same item order on client and server; no custom RPC or client authority.
local Home = require("spiderkingdom/spiders/home")
local Stances = require("spiderkingdom/spiders/stances")
local Wheel = {}
Wheel.ORDER = { "follow", "attack", "defend", "passive", "stay", "home" }

local function CastCommand(inst, doer)
    local commander = doer.components.sk_spidercommander
    if commander == nil then
        return false, "WEBBERONLY"
    end
    local command = inst._sk_command
    -- Native Inventory:CastSpellBookFromInv does not check SelectSpell's return value.
    -- Reject an invalid index instead of replaying the last valid command.
    local index = inst.components.spellbook:GetSelectedSpell()
    if index == nil or Wheel.ORDER[index] ~= command then
        return false
    end
    if command == "home" then
        local ok, reason = Home.Send(doer)
        if not ok then
            return false, reason
        end
    elseif not Stances.IsValid(command) or not commander:SetStance(command, true) then
        return false
    end
    if doer.components.talker ~= nil then
        doer.components.talker:Say(command == "home" and STRINGS.SK_COMMAND_WHEEL.HOME_SPEECH
            or STRINGS.SK_STANCES[string.upper(command)])
    end
    return true
end

local function MakeItem(command)
    return {
        label = STRINGS.SK_COMMAND_WHEEL[string.upper(command)],
        atlas = "images/sk_commandwheel.xml",
        normal = "sk_command_"..command..".tex",
        widget_scale = 0.85,
        hit_radius = 62,
        onselect = function(inst)
            inst._sk_command = command
            inst.components.spellbook:SetSpellName(STRINGS.SK_COMMAND_WHEEL[string.upper(command)])
            inst.components.spellbook:SetSpellAction(ACTIONS.SK_COMMAND)
            if TheWorld.ismastersim then
                inst.components.spellbook:SetSpellFn(CastCommand)
            end
        end,
        execute = function(inst)
            local player = rawget(_G, "ThePlayer")
            local inventory = player ~= nil and player.replica.inventory or nil
            if inventory ~= nil then
                inventory:CastSpellBookFromInv(inst)
            end
        end,
    }
end

function Wheel.MakeItems()
    local items = {}
    for _, command in ipairs(Wheel.ORDER) do
        items[#items + 1] = MakeItem(command)
    end
    return items
end

function Wheel.CanUse(inst, user)
    return user.prefab == "webber" and not user:HasTag("playerghost")
end

return Wheel
