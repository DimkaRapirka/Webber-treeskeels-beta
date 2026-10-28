-- Server-only home command, shared by the stock whistle action and the command wheel.
local Stances = require("spiderkingdom/spiders/stances")
local Home = {}

local function IsDenUsable(den)
    return den ~= nil and den:IsValid() and not den:IsInLimbo()
        and den.components.childspawner ~= nil and not den:HasTag("burnt")
        and not (den.components.health ~= nil and den.components.health:IsDead())
end

local function GetAdmitPool(spawner, spider)
    if spider.prefab == spawner.childname
        and spawner.childreninside + spawner.numchildrenoutside < spawner.maxchildren then
        return "regular"
    end
    if spider.prefab == spawner.emergencychildname
        and spawner:NumEmergencyChildren() < spawner.maxemergencychildren then
        return "emergency"
    end
end

local function SendIntoDen(spider, spawner, pool)
    spider.components.follower:StopFollowing()
    if pool == "emergency" then
        spawner:TakeEmergencyOwnership(spider)
    elseif pool == "regular" then
        spawner:TakeOwnership(spider)
    end
    local fx = SpawnPrefab("spawn_fx_small")
    if fx ~= nil then
        fx.Transform:SetPosition(spider.Transform:GetWorldPosition())
    end
    spawner:GoHome(spider) -- stock den handler drops a worn hat
end

function Home.Send(doer, selected_den)
    if doer == nil or not doer:HasTag("spiderwhisperer") or doer.components.leader == nil
        or (selected_den ~= nil and not IsDenUsable(selected_den)) then
        return false
    end
    local radius = TUNING.SPIDERKINGDOM.COMMAND_HOME_RADIUS
    local spiders = {}
    for spider in pairs(doer.components.leader.followers) do
        if spider:IsValid() and not spider:IsInLimbo() and spider:HasTag("spider")
            and spider.components.follower ~= nil and spider.components.follower:GetLeader() == doer
            and not spider:HasTag("spiderqueen") and not spider:HasTag("sk_worker")
            and not spider:HasTag("sk_guardian") and not spider:HasTag("sk_mount")
            and not Stances.IsCouriering(spider)
            and not (spider.components.health ~= nil and spider.components.health:IsDead())
            and spider:GetDistanceSqToInst(doer) <= radius * radius then
            spiders[#spiders + 1] = spider
        end
    end
    if #spiders == 0 then
        return false, "NOSPIDERS"
    end

    local dens
    if selected_den ~= nil then
        dens = { selected_den }
    else
        local x, y, z = doer.Transform:GetWorldPosition()
        dens = TheSim:FindEntities(x, y, z, radius, { "spiderden" }, { "INLIMBO", "burnt" })
        table.sort(dens, function(a, b) return a:GetDistanceSqToInst(doer) < b:GetDistanceSqToInst(doer) end)
    end

    local sent = 0
    for _, spider in ipairs(spiders) do
        local home = spider.components.homeseeker ~= nil and spider.components.homeseeker.home or nil
        if home ~= nil then
            if IsDenUsable(home) then
                local spawner = home.components.childspawner
                if spawner.childrenoutside[spider] ~= nil or spawner.emergencychildrenoutside[spider] ~= nil then
                    SendIntoDen(spider, spawner)
                    sent = sent + 1
                end
            end
        else
            -- Only matching normal / warrior broods can enter a new den; mutations keep their type.
            for _, den in ipairs(dens) do
                if IsDenUsable(den) then
                    local pool = GetAdmitPool(den.components.childspawner, spider)
                    if pool ~= nil then
                        SendIntoDen(spider, den.components.childspawner, pool)
                        sent = sent + 1
                        break
                    end
                end
            end
        end
    end
    if sent == 0 then
        return false, selected_den ~= nil and "FULL" or "NOHOME"
    end
    return true
end

return Home
