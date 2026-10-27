-- sk_courier (legacy, server only): the first T2 Spider Mail version (a follower carrying one parcel as a
-- save record) was replaced by the drone-style courier spider (components/sk_mailspider.lua).
-- This shim only keeps old saves safe: a parcel that was on its way is dropped next to the spider.

local LegacyCourier = Class(function(self, inst)
    self.inst = inst
end)

function LegacyCourier:IsActive()
    return false
end

local function DropParcel(inst, record)
    if not inst:IsValid() then
        return
    end
    local item = SpawnSaveRecord(record)
    if item ~= nil then
        item.Transform:SetPosition(inst.Transform:GetWorldPosition())
        if item.components.inventoryitem ~= nil then
            item.components.inventoryitem:OnDropped(true)
        end
    end
    -- The old courier mode had switched these off.
    inst.no_targeting = false
    inst:RemoveTag("nobundling")
    if inst.components.follower ~= nil then
        inst.components.follower.canaccepttarget = true
        inst.components.follower:EnableLeashing()
    end
end

function LegacyCourier:OnLoad(data)
    if data ~= nil and data.parcel ~= nil then
        local record = data.parcel
        self.inst:DoTaskInTime(0, DropParcel, record)
    end
end

return LegacyCourier
