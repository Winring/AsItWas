local _, AIW = ...

local BADGE_SIZE = 16
local PIN_TEMPLATES = {
    "QuestPinTemplate",
    "QuestOfferPinTemplate",
    "WorldQuestPinTemplate",
    "QuestHubPinTemplate",
    "BonusObjectivePinTemplate",
}

local function IsMapAttached(frame)
    if not frame then
        return false
    end
    if frame.GetMap and frame:GetMap() then
        return true
    end
    local parent = frame:GetParent()
    while parent do
        if parent == Minimap or parent == MinimapCluster then
            return true
        end
        parent = parent:GetParent()
    end
    return false
end

local function EnsureBadge(pin)
    local badge = pin.AsItWasBadge
    if badge then
        return badge
    end
    badge = pin:CreateTexture(nil, "OVERLAY", nil, 7)
    badge:SetSize(BADGE_SIZE, BADGE_SIZE)
    badge:SetPoint("TOPRIGHT", pin, "TOPRIGHT", 3, 3)
    badge:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    pin.AsItWasBadge = badge
    return badge
end

local function RelatedQuestIDs(pin)
    local ids = {}
    if pin.GetQuestID then
        local questID = pin:GetQuestID()
        if questID and questID > 0 then
            ids[#ids + 1] = questID
        end
    end
    if pin.questID and pin.questID > 0 then
        ids[#ids + 1] = pin.questID
    end
    if pin.GetRelatedQuests then
        local related = pin:GetRelatedQuests()
        if related then
            for questID in pairs(related) do
                ids[#ids + 1] = questID
            end
        end
    end
    return ids
end

-- In-range quest on the same pin/giver wins: no hourglass over a wanted bang.
local function PinNeedsBadge(pin)
    local ids = RelatedQuestIDs(pin)
    if #ids == 0 then
        return false
    end
    local sawOutOfRange = false
    for _, questID in ipairs(ids) do
        if AIW.IsInRange(questID) then
            return false
        end
        sawOutOfRange = true
    end
    return sawOutOfRange
end

function AIW.ApplyPinOverlay(pin)
    if not pin or not pin.CreateTexture then
        return
    end
    if not IsMapAttached(pin) then
        return
    end
    local badge = EnsureBadge(pin)
    if PinNeedsBadge(pin) then
        badge:Show()
    else
        badge:Hide()
    end
end

local function RefreshCanvas(map)
    if not map then
        return
    end
    if map.RefreshAllDataProviders then
        map:RefreshAllDataProviders()
    end
    if not map.EnumeratePinsByTemplate then
        return
    end
    for _, template in ipairs(PIN_TEMPLATES) do
        local ok, iter = pcall(function()
            return map:EnumeratePinsByTemplate(template)
        end)
        if ok and iter then
            for pin in iter do
                AIW.ApplyPinOverlay(pin)
            end
        end
    end
end

function AIW.RefreshMapOverlays()
    RefreshCanvas(WorldMapFrame)
    if Minimap and Minimap.RefreshAllDataProviders then
        RefreshCanvas(Minimap)
    end
end

local function HookMixin(mixin, method)
    if mixin and mixin[method] then
        hooksecurefunc(mixin, method, function(self)
            AIW.ApplyPinOverlay(self)
        end)
    end
end

local hooked = false
local function HookPinMixins()
    if hooked then
        return
    end
    if not POIButtonMixin then
        return
    end
    hooked = true
    HookMixin(POIButtonMixin, "UpdateButtonStyle")
    HookMixin(POIButtonMixin, "SetQuestID")
    HookMixin(QuestPinMixin, "OnMouseEnter")
    HookMixin(QuestOfferPinMixin, "OnAcquired")
    HookMixin(WorldQuestPinMixin, "RefreshVisuals")
    HookMixin(WorldQuestPinMixin, "OnLoad")
    HookMixin(QuestHubPinMixin, "OnAcquired")
    HookMixin(QuestHubPinMixin, "UpdatePriorityQuestDisplay")
    HookMixin(BonusObjectivePinMixin, "OnAcquired")
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" or name == "Blizzard_POIButton"
        or name == "Blizzard_WorldMap" or name == "Blizzard_SharedMapDataProviders" then
        HookPinMixins()
    end
end)

AIW.OnFilterChanged(AIW.RefreshMapOverlays)
