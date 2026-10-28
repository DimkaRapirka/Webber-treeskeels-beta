-- Basic spider commands (no Insight cost): stances shared by the commander component, the combat
-- wrappers and the Stay brain node. Plain module: require("spiderkingdom/spiders/stances").
--
--   follow  - stock behaviour.
--   attack  - also goes after hostile creatures near Webber on its own.
--   defend  - never picks fights itself; still answers attacks on itself and on Webber
--             (spider OnAttacked, leader SuggestTarget).
--   passive - never fights.
--   stay    - holds the spot where the order was given and defends it (like defend).
--
-- The stance lives on the spider as inst._sk_stance (nil = follow). The stock flags defensive /
-- no_targeting are re-applied every second by the commander, because vanilla Webber resets them
-- (prefabs/webber.lua ReleaseSpiderFollowers). While the stock whistle buff is running
-- (prefabs/spider_buffs.lua spider_whistle_buff, 10 s recall) the buff owns those flags.

local Stances = {}

Stances.ORDER = { "follow", "attack", "defend", "passive", "stay" }

local VALID = {}
for _, stance in ipairs(Stances.ORDER) do
    VALID[stance] = true
end

function Stances.IsValid(stance)
    return stance ~= nil and VALID[stance] == true
end

function Stances.Next(stance)
    for i, v in ipairs(Stances.ORDER) do
        if v == stance then
            return Stances.ORDER[i % #Stances.ORDER + 1]
        end
    end
    return Stances.ORDER[1]
end

function Stances.Get(spider)
    return spider._sk_stance or "follow"
end

-- A T2 courier spider away on a delivery (flying, or waiting at the destination) runs its own state.
local function IsCouriering(spider)
    return spider.components.sk_mailspider ~= nil and spider.components.sk_mailspider:IsAway()
end
Stances.IsCouriering = IsCouriering

local function IsRecalled(spider)
    return spider:HasDebuff("spider_whistle_buff")
end
Stances.IsRecalled = IsRecalled

-- No own target search (combat.targetfn) in these stances.
function Stances.BlocksRetarget(spider)
    local stance = spider._sk_stance
    return stance == "defend" or stance == "passive" or stance == "stay"
end

-- No target at all.
function Stances.BlocksAllTargets(spider)
    return spider._sk_stance == "passive"
end

-- The stock whistle recall (10 s) beats Stay; the anchor is kept for afterwards.
function Stances.IsStaying(spider)
    return spider._sk_stance == "stay" and not IsCouriering(spider) and not IsRecalled(spider)
end

-- Where a staying spider holds. Normally set when the order is given; only a spider restored from a
-- save (or moved to a migration portal) takes the spot where it first stands afterwards.
function Stances.GetStayAnchor(spider)
    if spider._sk_stay_anchor == nil then
        spider._sk_stay_anchor = spider:GetPosition()
    end
    return spider._sk_stay_anchor
end

-- "follow" defaults for the stock flags.
local function ResetFlags(spider)
    spider.defensive = false
    spider.no_targeting = false
end

-- Stock flags for the stance. A courier away on a delivery (components/sk_mailspider.lua) is left
-- alone, and the whistle buff owns the flags while it runs.
function Stances.ApplyFlags(spider)
    if IsCouriering(spider) then
        return
    end
    local stance = spider._sk_stance
    local follower = spider.components.follower

    local recalled = IsRecalled(spider)

    if follower ~= nil then
        if stance == "stay" and not recalled then
            follower:DisableLeashing()
        elseif follower.noleashing then
            follower:EnableLeashing()
        end
    end

    if recalled then
        return
    end

    -- "follow" (nil) leaves the stock flags alone.
    if stance == "passive" then
        spider.defensive = true
        spider.no_targeting = true
        if spider.components.combat ~= nil and spider.components.combat:HasTarget() then
            spider.components.combat:DropTarget()
        end
    elseif stance == "defend" or stance == "stay" then
        spider.defensive = true
        spider.no_targeting = false
    elseif stance == "attack" then
        ResetFlags(spider)
    end
end

-- immediate_anchor: the order is given now (Stay holds the current spot). Without it (restored from
-- a save) the anchor is taken lazily, after a possible move to the migration portal.
function Stances.SetStance(spider, stance, immediate_anchor)
    if stance == "follow" then
        stance = nil
    elseif stance == "stay" and spider.prefab == "spider_water" then
        -- spider_water runs brains/spider_waterbrain.lua, which has no Stay node.
        stance = "defend"
    end

    if spider._sk_stance ~= stance then
        local was_commanded = spider._sk_stance ~= nil
        spider._sk_stance = stance
        spider._sk_stay_anchor = (stance == "stay" and immediate_anchor) and spider:GetPosition() or nil

        if stance == nil and was_commanded and not IsCouriering(spider) and not IsRecalled(spider) then
            ResetFlags(spider)
        end
    end
    if stance == "stay" and immediate_anchor then
        spider._sk_stay_anchor = spider:GetPosition()
    end
    Stances.ApplyFlags(spider)
end

function Stances.Clear(spider)
    if spider._sk_stance ~= nil then
        Stances.SetStance(spider, nil)
    end
end

return Stances
