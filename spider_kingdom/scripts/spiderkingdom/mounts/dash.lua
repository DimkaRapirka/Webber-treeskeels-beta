-- M2 Cavalry Dash (skill webber_sk_rider_dash): double-tap a direction (or double-click) while riding the own
-- Spider Steed -> the stock ACTIONS.DASH and the stock Woby dash states (SGwilson / SGwilson_client
-- "dash_woby_pre" -> "dash_woby" -> "dash_woby_pst"), MOUNT_DASH_COOLDOWN seconds apart.
--
--   * Input: like Walter (prefabs/walter.lua GetDoubleClickActions), through
--     playeractionpicker.doubleclickactionsfn. The picker exists on the server and on the owning client
--     (player_common OnSetOwner, "setowner"); the previous fn (another mod) is kept as the fallback.
--   * Riding is checked with the rider replica, the skill and the cooldown with tags (sk_cavalry from the
--     skill handler, sk_dashcooldown from mounts/mount_common.lua StartDashCooldown), so client and server
--     build the same action.
--   * Cooldown start: the "dash_woby" state pushes "ondash_woby" on the mount
--     (components/sk_spidermount.lua listens).
--   * Animations: the official anim/woby_big_mount_dash.zip (bank "wilsonbeefalo"), loaded as an asset of
--     the steed prefab (prefabs/sk_spider_mount.lua). Until the graphics phase the rider sits on a beefalo.

local _G = GLOBAL
local MountCommon = require("spiderkingdom/mounts/mount_common")

-- pos: double click coords; dir: WASD / analog direction; target: double click mouseover target
-- (playeractionpicker GetDoubleClickActions). Same aiming as Walter's.
local function GetDashActions(inst, pos, dir, target)
    if not inst:HasTag(MountCommon.DASH_TAG) or inst:HasTag(MountCommon.DASH_COOLDOWN_TAG) then
        return nil
    end
    local rider = inst.replica.rider
    local mount = rider ~= nil and rider:GetMount() or nil
    if mount == nil or not mount:HasTag(MountCommon.MOUNT_TAG) then
        return nil
    end

    local pos2
    if dir ~= nil then
        pos2 = inst:GetPosition()
        pos2.x = pos2.x + dir.x * 10
        pos2.y = 0
        pos2.z = pos2.z + dir.z * 10
    elseif target ~= nil then
        pos2 = target:GetPosition()
        pos2.y = 0
    end
    return { _G.ACTIONS.DASH }, pos2
end

-- No double-click actions (prefabs/walter.lua returns its own local EMPTY_TABLE; there is no global one).
local NO_ACTIONS = {}

local function OnSetOwner(inst)
    local picker = inst.components.playeractionpicker
    if picker == nil or picker._sk_dash then
        return
    end
    picker._sk_dash = true

    local old_fn = picker.doubleclickactionsfn
    picker.doubleclickactionsfn = function(inst, pos, dir, target)
        local actions, pos2 = GetDashActions(inst, pos, dir, target)
        if actions ~= nil then
            return actions, pos2
        elseif old_fn ~= nil then
            return old_fn(inst, pos, dir, target)
        end
        return NO_ACTIONS
    end
end

AddPrefabPostInit("webber", function(inst)
    inst:ListenForEvent("setowner", OnSetOwner)
    OnSetOwner(inst) -- in case the picker already exists

    -- The stock "dash_woby_pst" state calls inst:EnableWobySprintTrail(false) without a nil check
    -- (only Walter defines it, prefabs/walter.lua). Webber has no sprint trail: a no-op.
    if inst.EnableWobySprintTrail == nil then
        inst.EnableWobySprintTrail = function() end
    end
end)
