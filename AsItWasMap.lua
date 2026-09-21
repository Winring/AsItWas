local _, AIW = ...

local BADGE_SIZE = 16
local BADGE_TEXTURE = {
    newer = "Interface\\AddOns\\AsItWas\\textures\\newer.png",
    older = "Interface\\AddOns\\AsItWas\\textures\\older.png",
    unknown = "Interface\\Icons\\INV_Misc_QuestionMark",
}
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

-- In-range quest on the same pin/giver wins: no badge over a wanted bang.
-- Mixed older+newer with no in-range quest: newer badge (later content first).
local function BadgeKindForQuestIDs(ids)
    local sawNewer, sawOlder, sawUnknown = false, false, false
    for _, questID in ipairs(ids) do
        if AIW.IsUnknown(questID) then
            sawUnknown = true
        elseif AIW.IsInRange(questID) then
            return nil
        end
        local kind = AIW.OutOfRangeKind(questID)
        if kind == "newer" then
            sawNewer = true
        elseif kind == "older" then
            sawOlder = true
        end
    end
    if sawNewer then
        return "newer"
    end
    if sawOlder then
        return "older"
    end
    if sawUnknown then
        return "unknown"
    end
    return nil
end

function AIW.ApplyPinOverlay(pin)
    if not pin or not pin.CreateTexture then
        return
    end
    if not IsMapAttached(pin) then
        return
    end
    local badge = EnsureBadge(pin)
    local kind = BadgeKindForQuestIDs(RelatedQuestIDs(pin))
    if kind then
        badge:SetTexture(BADGE_TEXTURE[kind])
        badge:Show()
    else
        badge:Hide()
    end
end

local function CanvasIsReady(map)
    if not map or not map:IsShown() then
        return false
    end
    if not map.RefreshAllDataProviders or not map.dataProviders then
        return false
    end
    local scroll = map.ScrollContainer
    if scroll and scroll.zoomLevels == nil then
        return false
    end
    return true
end

local function RefreshCanvas(map)
    if not CanvasIsReady(map) then
        return
    end
    securecallfunction(map.RefreshAllDataProviders, map)
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

-- Minimap quest bangs are engine-drawn. Overlay uses the same yard math as
-- HybridMinimapMixin:UpdateZoom: diameter = GetViewRadius() * 2, so zoom
-- in/out is whatever the current view radius is (MINIMAP_UPDATE_ZOOM).
-- rotateMinimap exists in Edit Mode but defaults off.

local minimapBadges = {}
local minimapUsed = 0
local lastQuestLineMapID
local cachedMapID
local cachedGroups = {}

local function HideUnusedMinimapBadges()
    for i = minimapUsed + 1, #minimapBadges do
        minimapBadges[i]:Hide()
    end
end

local function AcquireMinimapBadge()
    minimapUsed = minimapUsed + 1
    local badge = minimapBadges[minimapUsed]
    if not badge then
        badge = Minimap:CreateTexture(nil, "OVERLAY", nil, 7)
        badge:SetSize(BADGE_SIZE, BADGE_SIZE)
        minimapBadges[minimapUsed] = badge
    end
    return badge
end

local function MinimapRotateEnabled()
    if C_Minimap.IsRotateMinimapIgnored and C_Minimap.IsRotateMinimapIgnored() then
        return false
    end
    return GetCVarBool("rotateMinimap")
end

-- Map 0-1 coords to minimap pixel offset from center.
-- player.x, player.y are 0-1 map coordinates from GetPlayerMapPosition
-- x, y are 0-1 quest coordinates
-- radius is view radius in yards from GetViewRadius
local function MapPosToMinimapOffset(mapID, player, yardsW, yardsH, radius, x, y)
    local halfW = Minimap:GetWidth() / 2
    local halfH = Minimap:GetHeight() / 2

    -- Convert 0-1 map coords to yard offsets
    local dx = (x - player.x) * yardsW
    local dy = (player.y - y) * yardsH  -- y axis is inverted

    -- Scale to minimap pixels
    local scale = halfW / radius
    local px = dx * scale
    local py = dy * scale

    -- Apply rotation if enabled
    if MinimapRotateEnabled() then
        local facing = GetPlayerFacing()
        if facing then
            local sin, cos = math.sin(facing), math.cos(facing)
            px, py = px * cos - py * sin, px * sin + py * cos
        end
    end

    return px, py
end

local function AddQuestPoint(groups, questID, x, y)
    if not questID or not x or not y then
        return
    end
    local key = string.format("%.3f:%.3f", x, y)
    local group = groups[key]
    if not group then
        group = { x = x, y = y, ids = {} }
        groups[key] = group
    end
    group.ids[#group.ids + 1] = questID
end

-- Same gates as QuestOfferDataProviderMixin:ShouldAddQuestOffer
-- (Blizzard_SharedMapDataProviders/QuestOfferDataProvider.lua:79). An offer the
-- player already has in the log draws no bang, so inProgress has to go.
local function ShouldAddOffer(info, mapID)
    if not info or not info.questID then
        return false
    end
    if info.inProgress then
        return false
    end
    if info.startMapID and info.startMapID ~= mapID
        and not (MapUtil and MapUtil.IsChildMapCached and MapUtil.IsChildMapCached(info.startMapID, mapID)) then
        return false
    end
    if info.isHidden and C_Minimap.IsTrackingHiddenQuests and not C_Minimap.IsTrackingHiddenQuests() then
        return false
    end
    return true
end

-- The minimap only shows quest givers (bangs) and quests ready to hand in.
-- Objectives of quests in progress are engine blobs, not icons, so the quest
-- log is read for turn-ins only.
local function CollectMinimapQuestGroups(mapID)
    if cachedMapID == mapID then
        return cachedGroups
    end
    local groups = {}
    local seen = {}

    local function AddOffer(info)
        if ShouldAddOffer(info, mapID) and not seen[info.questID] then
            seen[info.questID] = true
            AddQuestPoint(groups, info.questID, info.x, info.y)
        end
    end

    -- Blizzard's own order: quest lines, force-visible, then tasks
    -- (QuestOfferDataProviderMixin:GetAllQuestOffersForMap).
    if C_QuestLine then
        if lastQuestLineMapID ~= mapID and C_QuestLine.RequestQuestLinesForMap then
            lastQuestLineMapID = mapID
            pcall(C_QuestLine.RequestQuestLinesForMap, mapID)
        end
        local ok, lines = pcall(C_QuestLine.GetAvailableQuestLines, mapID)
        if ok and lines then
            for _, info in ipairs(lines) do
                AddOffer(info)
            end
        end
        if C_QuestLine.GetForceVisibleQuests and C_QuestLine.GetQuestLineInfo then
            local okForced, forced = pcall(C_QuestLine.GetForceVisibleQuests, mapID)
            if okForced and forced then
                for _, questID in ipairs(forced) do
                    local okInfo, info = pcall(C_QuestLine.GetQuestLineInfo, questID, mapID)
                    if okInfo then
                        AddOffer(info)
                    end
                end
            end
        end
    end
    if C_TaskQuest and C_TaskQuest.GetQuestsOnMap then
        local tasks = C_TaskQuest.GetQuestsOnMap(mapID)
        if tasks then
            for _, info in ipairs(tasks) do
                AddOffer(info)
            end
        end
    end
    if C_QuestLog.GetQuestsOnMap and C_QuestLog.ReadyForTurnIn then
        local logQuests = C_QuestLog.GetQuestsOnMap(mapID)
        if logQuests then
            for _, info in ipairs(logQuests) do
                if not info.isMapIndicatorQuest and not seen[info.questID]
                    and C_QuestLog.ReadyForTurnIn(info.questID) then
                    seen[info.questID] = true
                    AddQuestPoint(groups, info.questID, info.x, info.y)
                end
            end
        end
    end

    cachedMapID = mapID
    cachedGroups = groups
    return groups
end

local function InvalidateMinimapQuestCache()
    cachedMapID = nil
    cachedGroups = {}
    lastQuestLineMapID = nil
end

local function GroupBadgeKind(ids)
    return BadgeKindForQuestIDs(ids)
end

function AIW.RefreshMinimapOverlays()
    if true then
        return -- Disabled for now till we will not figure out the all exclamation marks (quest) coverage
    end
    minimapUsed = 0
    if not Minimap or not AIW.IsEnabled() then
    HideUnusedMinimapBadges()
    return
    end
    local mapID = C_Minimap.GetUiMapID and C_Minimap.GetUiMapID() or C_Map.GetBestMapForUnit("player")
    if not mapID then
    HideUnusedMinimapBadges()
    return
    end
    local player = C_Map.GetPlayerMapPosition(mapID, "player")
    local yardsW, yardsH = C_Map.GetMapWorldSize(mapID)
    local radius = C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
    if not player or not yardsW or yardsW == 0 or not radius or radius <= 0 then
    AIW.Debug("minimap: no player/world size/view radius on map %s", tostring(mapID))
    HideUnusedMinimapBadges()
    return
    end
    local half = Minimap:GetWidth() / 2
    local edge = half - (BADGE_SIZE / 2)
    local groups = CollectMinimapQuestGroups(mapID)
    local groupCount, offMinimap = 0, 0
    for _, group in pairs(groups) do
    groupCount = groupCount + 1
    local kind = GroupBadgeKind(group.ids)
    if kind then
    local px, py = MapPosToMinimapOffset(mapID, player, yardsW, yardsH, radius, group.x, group.y)
    if px and (px * px + py * py) <= (edge * edge) then
    local badge = AcquireMinimapBadge()
    badge:SetTexture(BADGE_TEXTURE[kind])
    badge:ClearAllPoints()
    badge:SetPoint("CENTER", Minimap, "CENTER", px, py)
    badge:Show()
    else
    offMinimap = offMinimap + 1
    end
    end
    end
    AIW.Debug("minimap: map %s, %d groups, %d badges, %d off minimap",
    tostring(mapID), groupCount, minimapUsed, offMinimap)
    HideUnusedMinimapBadges()
    end

-- One-shot diagnostics for the owner: the summary line cannot tell a quest that
-- was never collected from one whose offset landed outside the minimap. Runs on
-- demand only, never from the OnUpdate pass.
function AIW.DumpMinimap()
    local mapID = C_Minimap.GetUiMapID and C_Minimap.GetUiMapID() or C_Map.GetBestMapForUnit("player")
    if not Minimap or not mapID then
        AIW.Print("dump: no minimap or map id")
        return
    end
    local player = C_Map.GetPlayerMapPosition(mapID, "player")
    local yardsW, yardsH = C_Map.GetMapWorldSize(mapID)
    local radius = C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
    if not player or not yardsW or yardsW == 0 or not radius or radius <= 0 then
        AIW.Print(string.format("dump: map %s has no player/world size/view radius", tostring(mapID)))
        return
    end
    local edge = (Minimap:GetWidth() / 2) - (BADGE_SIZE / 2)
    local px, py = player:GetXY()
    AIW.Print(string.format("dump: map %s player %.3f,%.3f yards %.0fx%.0f radius %.1f edge %.0f",
        tostring(mapID), px, py, yardsW, yardsH, radius, edge))
    local groups = CollectMinimapQuestGroups(mapID)
    for _, group in pairs(groups) do
        local parts = {}
        for _, questID in ipairs(group.ids) do
            local patch = AIW.QuestPatch(questID)
            parts[#parts + 1] = string.format("%d[%s%s]", questID,
                patch and AIW.FormatPatchCode(patch) or "?",
                AIW.IsInRange(questID) and " in" or "")
        end
        local kind = GroupBadgeKind(group.ids)
        local ox, oy = MapPosToMinimapOffset(mapID, player, yardsW, yardsH, radius, group.x, group.y)
        local onMinimap = ox and (ox * ox + oy * oy) <= (edge * edge)
        AIW.Print(string.format("dump: %.3f,%.3f kind=%s off=%.0f,%.0f %s %s",
            group.x, group.y, tostring(kind), ox or 0, oy or 0,
            onMinimap and "ON" or "OUT", table.concat(parts, " ")))
    end
end

function AIW.RefreshMapOverlays()
    InvalidateMinimapQuestCache()
    RefreshCanvas(WorldMapFrame)
    AIW.RefreshMinimapOverlays()
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

local minimapFrame = CreateFrame("Frame")
minimapFrame:RegisterEvent("MINIMAP_UPDATE_ZOOM")
minimapFrame:RegisterEvent("QUEST_POI_UPDATE")
minimapFrame:RegisterEvent("QUESTLINE_UPDATE")
minimapFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
minimapFrame:RegisterEvent("CVAR_UPDATE")
minimapFrame.elapsed = 0
minimapFrame:SetScript("OnEvent", function(_, event, cvar)
    if event == "CVAR_UPDATE" and cvar ~= "rotateMinimap" then
        return
    end
    if event == "QUESTLINE_UPDATE" or event == "QUEST_POI_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        InvalidateMinimapQuestCache()
    end
    AIW.RefreshMinimapOverlays()
end)
minimapFrame:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    -- Zoom animates GetViewRadius; keep this tight so in/out does not lag.
    if self.elapsed < 0.05 then
        return
    end
    self.elapsed = 0
    AIW.RefreshMinimapOverlays()
end)

AIW.OnFilterChanged(AIW.RefreshMapOverlays)
