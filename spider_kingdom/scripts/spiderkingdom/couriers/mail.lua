-- T2 Spider Mail, drone style (like the WX-78 delivery drone):
--   1. craft a Courier Kit (skill webber_sk_symbiosis_mail) and use it on one of your spiders:
--      it becomes a courier spider (scripts/prefabs/sk_courierspider.lua) with a 6-slot container;
--   2. put items into it (left click opens it), right click it -> "Send" opens the map, pick a point;
--   3. it flies there, waits as an open container until emptied (or for a while), then flies back.
-- The flight itself is the official mapdeliverable component; the courier's logic is
-- components/sk_mailspider.lua. Works in solo play: any reachable point on the map is a valid target.

local _G = GLOBAL
local SKUtil = require("spiderkingdom/util")
local MailCommon = require("spiderkingdom/couriers/mail_common")

local SKILL = "webber_sk_symbiosis_mail"

-- Legacy: the first T2 version stored parcels on ordinary spiders (components/sk_courier.lua shim).
local LEGACY_PREFABS = { "spider", "spider_warrior", "spider_hider", "spider_spitter", "spider_dropper", "spider_moon", "spider_healer" }
for _, prefab in ipairs(LEGACY_PREFABS) do
    AddPrefabPostInit(prefab, function(inst)
        if _G.TheWorld.ismastersim then
            inst:AddComponent("sk_courier")
        end
    end)
end

-- A courier waiting at the destination stands still (otherwise the stock brain would wander off
-- with the cargo). Inserted right after the stock panic nodes of brains/spiderbrain.lua.
_G.require("behaviours/standstill")

AddBrainPostInit("spiderbrain", function(brain)
    local inst = brain.inst
    local courier = inst.components.sk_mailspider
    local root = brain.bt ~= nil and brain.bt.root or nil
    if courier == nil or root == nil or root.children == nil then
        return
    end
    local node = _G.WhileNode(function() return courier.phase == "waiting" end, "SKCourierWait", _G.StandStill(inst))
    node.parent = root
    table.insert(root.children, math.min(2, #root.children + 1), node)
end)

-- Container widget (same layout as the official tackle box, 3x2) -----------------------------------

local containers = require("containers")

local params =
{
    widget =
    {
        slotpos = {},
        animbank = "ui_tacklecontainer_3x2",
        animbuild = "ui_tacklecontainer_3x2",
        pos = _G.Vector3(0, 200, 0),
        side_align_tip = 160,
    },
    type = "chest",
}
for y = 1, 0, -1 do
    for x = 0, 2 do
        table.insert(params.widget.slotpos, _G.Vector3(80 * x - 80 * 2 + 80, 80 * y - 80 * 2 + 120, 0))
    end
end
containers.params.sk_courierspider = params

-- Kit: turns one of your spiders into a courier ------------------------------------------------

local CanUpgrade = MailCommon.CanUpgrade

AddCharacterRecipe("sk_courier_kit",
    {
        _G.Ingredient("silk", 6),
        _G.Ingredient("spidergland", 2),
        _G.Ingredient("rope", 1),
    },
    _G.TECH.NONE,
    {
        builder_skill = SKILL,
    }
)

local SK_MAKECOURIER = _G.Action({ priority = 2 })
SK_MAKECOURIER.id = "SK_MAKECOURIER"
SK_MAKECOURIER.str = _G.STRINGS.ACTIONS.SK_MAKECOURIER
SK_MAKECOURIER.fn = function(act)
    local doer, spider, kit = act.doer, act.target, act.invobject
    if doer == nil or spider == nil or kit == nil or kit.prefab ~= "sk_courier_kit"
        or not SKUtil.HasSkill(doer, SKILL) or not CanUpgrade(doer, spider)
        or (spider.components.health ~= nil and spider.components.health:IsDead()) then
        return false
    end

    local courier = _G.SpawnPrefab("sk_courierspider")
    if courier == nil then
        return false
    end

    local x, y, z = spider.Transform:GetWorldPosition()
    courier.Transform:SetPosition(x, y, z)
    courier.Transform:SetRotation(spider.Transform:GetRotation())
    if spider.components.health ~= nil and courier.components.health ~= nil then
        courier.components.health:SetPercent(spider.components.health:GetPercent())
    end
    -- Anything the spider wore stays on the ground (its hat).
    if spider.components.inventory ~= nil then
        spider.components.inventory:DropEverything()
    end
    courier.components.sk_mailspider:SetOwner(doer)

    local used = kit.components.stackable ~= nil and kit.components.stackable:Get() or kit
    used:Remove()

    spider:Remove()
    doer.components.leader:AddFollower(courier) -- bonded by sk_spiderkeeper through the follower hooks

    local fx = _G.SpawnPrefab("spider_mutate_fx")
    if fx ~= nil then
        fx.Transform:SetPosition(x, y, z)
    end
    return true
end
AddAction(SK_MAKECOURIER)

AddStategraphActionHandler("wilson", _G.ActionHandler(_G.ACTIONS.SK_MAKECOURIER, "give"))
AddStategraphActionHandler("wilson_client", _G.ActionHandler(_G.ACTIONS.SK_MAKECOURIER, "give"))

-- The client collector for SK_MAKECOURIER lives in networking/item_actions.lua (one USEITEM
-- "inventoryitem" collector per mod).
