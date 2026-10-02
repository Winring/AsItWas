local _, AIW = ...

-- Do not hook QuestPinMixin:OnMouseEnter and do not read GameTooltip's
-- FontStrings. Blizzard's map hover path can run in a secure/tainted range,
-- and its title may be a secret string. Instead, observe already-acquired
-- pins from our own ticker and render an addon-owned tooltip.

local PIN_TEMPLATES = {
    "QuestPinTemplate",
    "QuestOfferPinTemplate",
    "WorldQuestPinTemplate",
    "QuestHubPinTemplate",
    "BonusObjectivePinTemplate",
}

local TITLE_CACHE = setmetatable({}, { __mode = "k" })
local tooltip
local currentPin
local elapsed = 0

local function GetQuestID(pin)
    if not pin then
        return nil
    end
    if pin.GetQuestID then
        local ok, questID = pcall(pin.GetQuestID, pin)
        if ok and questID then
            return questID
        end
    end
    return pin.questID
end

local function ReadQuestTitle(pin, questID)
    -- Use the same source as QuestPinMixin. The returned title is passed
    -- directly to the addon-owned tooltip; it is never compared or parsed.
    -- QuestOfferPinMixin carries its display title as questName because an
    -- available quest is not necessarily in the quest log yet.
    if pin then
        if pin.questName then
            return pin.questName
        end
    end
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
        if ok and title then
            return title
        end
    end
end

local function GetBlizzardQuestTitleColor(pin, questID, isQuestOffer)
    -- Match GameTooltip_AddQuest's title-color branches instead of assigning
    -- one fixed addon color. World-quest quality is data-driven by Blizzard.
    local isWorldQuest = pin.worldQuest
    if not isWorldQuest and C_QuestLog.IsWorldQuest then
        isWorldQuest = C_QuestLog.IsWorldQuest(questID)
    end
    if isWorldQuest and ColorManager and ColorManager.GetColorDataForWorldQuestQuality then
        local tagInfo = C_QuestLog.GetQuestTagInfo(questID)
        local quality = tagInfo and tagInfo.quality or Enum.WorldQuestQuality.Common
        local colorData = ColorManager.GetColorDataForWorldQuestQuality(quality)
        if colorData and colorData.color then
            return colorData.color
        end
    end

    -- Blizzard's NORMAL_FONT_COLOR is the gold quest-title color. The
    -- confusingly named HIGHLIGHT_FONT_COLOR is white and is used by the
    -- secondary available/type/objective lines.
    return NORMAL_FONT_COLOR
end

local function AddOfficialQuestLines(frame, pin, questID, title)
    -- Keep our decoration directly before the title on the same line. The
    -- prefix is addon-owned and the title comes from the pin/quest API; we
    -- never read or rewrite Blizzard's existing tooltip text.
    local prefix = AIW.MapTitlePrefix(questID)
    local isQuestOffer = pin.pinTemplate == "QuestOfferPinTemplate" or pin.questName ~= nil
    local titleColor = GetBlizzardQuestTitleColor(pin, questID, isQuestOffer)
    local displayTitle = title
    if prefix ~= "" then
        displayTitle = prefix .. " " .. title
    end
    GameTooltip_AddColoredLine(frame, displayTitle, titleColor)
    local titleLine = frame.TextLeft1
    if titleLine then
        titleLine:SetFontObject(GameTooltipHeaderText)
        titleLine:SetTextColor(titleColor:GetRGB())
    end

    if QuestUtils_AddQuestTypeToTooltip and not isQuestOffer then
        -- This matches QuestPinMixin: only dungeon/raid type data is added
        -- here; the helper supplies Blizzard's native icon markup and color.
        QuestUtils_AddQuestTypeToTooltip(frame, questID, NORMAL_FONT_COLOR)
    end
    if isQuestOffer then
        -- This is the non-world-quest branch from Blizzard's GameTooltip_AddQuest.
        -- QuestOfferPinMixin provides this state in the acquired pin data; it
        -- is not present in the quest log yet.
        local isCombatAlly = pin.isCombatAllyQuest
        if not isCombatAlly and C_QuestLog.GetQuestType and Enum.QuestTag.CombatAlly then
            isCombatAlly = C_QuestLog.GetQuestType(questID) == Enum.QuestTag.CombatAlly
        end
        if isCombatAlly then
            GameTooltip_AddColoredLine(frame, AVAILABLE_FOLLOWER_QUEST, HIGHLIGHT_FONT_COLOR, true)
            GameTooltip_AddColoredLine(frame, GRANTS_FOLLOWER_XP, GREEN_FONT_COLOR, true)
        elseif pin.isQuestStart then
            GameTooltip_AddColoredLine(frame, AVAILABLE_QUEST, HIGHLIGHT_FONT_COLOR, true)
            if pin.floorLocation == Enum.QuestLineFloorLocation.Above then
                GameTooltip_AddNormalLine(frame, QUESTLINE_LOCATED_ABOVE)
            elseif pin.floorLocation == Enum.QuestLineFloorLocation.Below then
                GameTooltip_AddNormalLine(frame, QUESTLINE_LOCATED_BELOW)
            end
        end
    end
    if not isQuestOffer and GameTooltip_CheckAddQuestTimeToTooltip then
        GameTooltip_CheckAddQuestTimeToTooltip(frame, questID)
    end

    local superTracked = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
        and C_SuperTrack.GetSuperTrackedQuestID()
    local focused = QuestMapFrame_GetFocusedQuestID and QuestMapFrame_GetFocusedQuestID()
    local isWaypointQuest = questID == superTracked or questID == focused
    local waypointText = isWaypointQuest and C_QuestLog.GetNextWaypointText(questID)
    if waypointText then
        -- Do not concatenate QUEST_DASH with a possibly secret string.
        GameTooltip_AddColoredLine(frame, waypointText, HIGHLIGHT_FONT_COLOR)
    elseif pin.GetStyle and POIButtonUtil
        and pin:GetStyle() == POIButtonUtil.Style.QuestInProgress then
        local questLogIndex = C_QuestLog.GetLogIndexForQuestID(questID)
        if questLogIndex then
            local itemDrops = GetNumQuestItemDrops and GetNumQuestItemDrops(questLogIndex) or 0
            if itemDrops > 0 then
                for index = 1, itemDrops do
                    local text, _, finished = GetQuestLogItemDrop(index, questLogIndex)
                    if text and not finished then
                        -- Blizzard prefixes every displayed step with its
                        -- localized quest dash, including multiple steps.
                        frame:AddLine(QUEST_DASH .. text, 1, 1, 1, true)
                    end
                end
            else
                local objectives = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(questLogIndex) or 0
                for index = 1, objectives do
                    local text, _, finished = GetQuestLogLeaderBoard(index, questLogIndex)
                    if text and not finished then
                        -- Keep the dash on every objective, not only the first.
                        frame:AddLine(QUEST_DASH .. text, 1, 1, 1, true)
                    end
                end
            end
        end
    end
end

local function EnsureTooltip()
    if tooltip then
        return tooltip
    end

    -- Use Blizzard's own tooltip layout on an addon-owned GameTooltip. This
    -- gives us the normal font, padding, wrapping, and content-based size
    -- without touching the global GameTooltip instance.
    tooltip = CreateFrame("GameTooltip", "AsItWasMapTooltip", UIParent, "GameTooltipTemplate")
    tooltip:SetFrameStrata("TOOLTIP")
    return tooltip
end

local function IsHovered(pin)
    if not pin or not pin.IsMouseMotionFocus then
        return false
    end
    -- IsMouseOver() is secret-aware when the region is anchored to a secret
    -- object. IsMouseMotionFocus() returns an ordinary boolean and is the
    -- appropriate read-only focus query for this polling path.
    local ok, hovered = pcall(pin.IsMouseMotionFocus, pin)
    return ok and hovered == true
end

local function FindHoveredQuestPin(map)
    if not map or not map.EnumeratePinsByTemplate then
        return nil
    end
    for _, template in ipairs(PIN_TEMPLATES) do
        local ok, iterator = pcall(map.EnumeratePinsByTemplate, map, template)
        if ok and iterator then
            for pin in iterator do
                if IsHovered(pin) and GetQuestID(pin) then
                    return pin
                end
            end
        end
    end
end

local function HideTooltip()
    if tooltip then
        tooltip:Hide()
    end
    currentPin = nil
end

local function ShowForPin(pin, questID, title)
    local frame = EnsureTooltip()
    frame:SetOwner(pin, "ANCHOR_RIGHT", 8, 0)
    frame:ClearLines()
    -- Do not compare, concatenate, or otherwise inspect title. Passing it
    -- directly to Blizzard's title setter on our own tooltip is the only
    -- operation performed on this value.
    pcall(AddOfficialQuestLines, frame, pin, questID, title)
    frame:Show()

    -- Blizzard already displayed its native tooltip from the pin's own hover
    -- handler. Hide only that tooltip after we have found the pin; no Blizzard
    -- title or FontString is read or rewritten.
    if GameTooltip then
        GameTooltip:Hide()
    end
    currentPin = pin
end

local function Update()
    if not WorldMapFrame then
        HideTooltip()
        return
    end

    -- With no active filter there is nothing to decorate. Leave Blizzard's
    -- native quest tooltip completely untouched.
    if not AIW.IsEnabled() then
        if tooltip and currentPin and GameTooltip then
            GameTooltip:Show()
        end
        HideTooltip()
        return
    end

    local pin = FindHoveredQuestPin(WorldMapFrame)
    if not pin then
        HideTooltip()
        return
    end

    local questID = GetQuestID(pin)
    if not questID then
        HideTooltip()
        return
    end

    local title = TITLE_CACHE[questID]
    if not title then
        title = ReadQuestTitle(pin, questID)
        if title then
            TITLE_CACHE[questID] = title
        end
    end
    if not title then
        return
    end

    if pin ~= currentPin then
        ShowForPin(pin, questID, title)
    else
        -- Keep the native tooltip suppressed if Blizzard refreshed it while
        -- the cursor stayed on the same pin.
        if GameTooltip then
            GameTooltip:Hide()
        end
    end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < 0.05 then
        return
    end
    elapsed = 0
    Update()
end)
