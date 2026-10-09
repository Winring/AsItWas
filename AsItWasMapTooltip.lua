local _, AIW = ...

-- Never hide, show, own or hook GameTooltip from this file. Doing so runs
-- Blizzard's tooltip scripts (GameTooltip_OnHide clears the widget container)
-- under this addon's taint, and the next AreaPOI widget tooltip then reads those
-- fields and fails on secret text metrics. Only read-only widget getters
-- (IsShown, GetOwner, GetWidth, GetFrameLevel) are used on it.
--
-- An addon-owned tooltip with the era prefix is drawn on top of Blizzard's own
-- pin tooltip, so one tooltip is visible. The lines of Blizzard's two quest pin
-- handlers are rebuilt here; anything else Blizzard adds stays under ours.
--
-- Pin frames are pooled, and a pin positioned in a restricted context keeps
-- secret anchoring; GameTooltip anchored to it, and ours anchored to
-- GameTooltip, inherit it. No Lua here measures or does arithmetic on our own
-- or Blizzard's geometry: ours is a GameTooltip widget, so the client sizes and
-- lays it out, and a secret width or level is simply not used.

local PIN_TEMPLATES = {
    "QuestPinTemplate",
    "QuestOfferPinTemplate",
    -- Re-enable one at a time after the basic quest-pin path is stable:
    -- "WorldQuestPinTemplate",
    -- "QuestHubPinTemplate",
    -- "BonusObjectivePinTemplate",
}

local FLOOR_COLOR = { r = 0.5, g = 0.5, b = 0.5 }

local cover
local currentPin
local currentQuestID
local currentLines
local filledLines
local lastReport

-- /aiw debug: one chat line per hovered pin, repeated only when the outcome
-- changes, because Update runs every frame.
local function Report(questID, outcome)
    if not AsItWasDB or not AsItWasDB.debug then
        return
    end
    local message = string.format("map tooltip, quest %s: %s", tostring(questID), outcome)
    if message ~= lastReport then
        lastReport = message
        AIW.Print(message)
    end
end

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

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

-- SharedTooltipTemplate, not GameTooltipTemplate: its scripts only touch the
-- tooltip itself (SharedTooltipTemplates.lua), while GameTooltipTemplate's
-- OnHide also hides the shared BattlePetTooltip and clears
-- TooltipComparisonManager, both global Blizzard state.
local function EnsureCover()
    if cover then
        return cover
    end
    cover = CreateFrame("GameTooltip", "AsItWasMapTooltip", UIParent, "SharedTooltipTemplate")
    cover:Hide()
    -- The tooltip background art is semi-transparent, so Blizzard's tooltip
    -- text would show through ours. A solid fill in the same color sits under
    -- it, inset to stay inside the rounded border.
    local fill = cover:CreateTexture(nil, "BACKGROUND", nil, -8)
    fill:SetPoint("TOPLEFT", cover, "TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMRIGHT", cover, "BOTTOMRIGHT", -3, 3)
    local r, g, b = TOOLTIP_DEFAULT_BACKGROUND_COLOR:GetRGB()
    fill:SetColorTexture(r, g, b, 1)
    return cover
end

local function AddLine(lines, text, color, wrap)
    lines[#lines + 1] = { text = text, color = color, wrap = wrap }
end

-- The same lines Blizzard's pin handlers add (QuestPinMixin:OnMouseEnter in
-- QuestDataProvider.lua and the quest-start branch of GameTooltip_AddQuest in
-- GameTooltip.lua), rebuilt from C APIs and plain pin fields only.
-- Returns nil only while the quest title is not available yet.
local function BuildLines(pin, questID, prefix)
    local isOffer = pin.pinTemplate == "QuestOfferPinTemplate"
    local title = (isOffer and pin.questName) or C_QuestLog.GetTitleForQuestID(questID)
    if not title or IsSecret(title) then
        return nil
    end

    local lines = {}
    AddLine(lines, prefix .. " " .. title, NORMAL_FONT_COLOR, false)

    if isOffer then
        if pin.isCombatAllyQuest or C_QuestLog.GetQuestType(questID) == Enum.QuestTag.CombatAlly then
            AddLine(lines, AVAILABLE_FOLLOWER_QUEST, HIGHLIGHT_FONT_COLOR, true)
            AddLine(lines, GRANTS_FOLLOWER_XP, GREEN_FONT_COLOR, true)
        elseif pin.isQuestStart then
            AddLine(lines, AVAILABLE_QUEST, HIGHLIGHT_FONT_COLOR, true)
            if pin.floorLocation == Enum.QuestLineFloorLocation.Below then
                AddLine(lines, QUESTLINE_LOCATED_BELOW, FLOOR_COLOR, true)
            elseif pin.floorLocation == Enum.QuestLineFloorLocation.Above then
                AddLine(lines, QUESTLINE_LOCATED_ABOVE, FLOOR_COLOR, true)
            end
        end
        return lines
    end

    -- QuestUtils_AddQuestTypeToTooltip: only dungeon-type tags get a line.
    -- The tag tables are read directly (QuestUtils.lua, Constants.lua).
    local tagInfo = C_QuestLog.GetQuestTagInfo(questID)
    if tagInfo and tagInfo.tagName and not IsSecret(tagInfo.tagName) then
        local worldQuestType = tagInfo.worldQuestType
        local isDungeon, atlas
        if worldQuestType ~= nil then
            isDungeon = WORLD_QUEST_TYPE_DUNGEON_TYPES and WORLD_QUEST_TYPE_DUNGEON_TYPES[worldQuestType]
            atlas = WORLD_QUEST_TYPE_ATLAS and WORLD_QUEST_TYPE_ATLAS[worldQuestType]
        else
            isDungeon = QUEST_TAG_DUNGEON_TYPES and QUEST_TAG_DUNGEON_TYPES[tagInfo.tagID]
            atlas = QUEST_TAG_ATLAS and QUEST_TAG_ATLAS[tagInfo.tagID]
        end
        if isDungeon and atlas then
            AddLine(lines, CreateAtlasMarkup(atlas, 20, 20) .. " " .. tagInfo.tagName, NORMAL_FONT_COLOR, false)
        end
    end

    -- GameTooltip_CheckAddQuestTimeToTooltip via WorldMap_GetQuestTimeForTooltip.
    -- QuestUtils_GetQuestTimeColor and WorldQuestsSecondsFormatter:Format only
    -- read; neither writes Blizzard state.
    if C_QuestLog.ShouldDisplayTimeRemaining(questID) then
        local secondsRemaining = C_TaskQuest.GetQuestTimeLeftSeconds(questID)
        if secondsRemaining and not IsSecret(secondsRemaining) then
            local color = QuestUtils_GetQuestTimeColor(secondsRemaining)
            local formattedTime = WorldQuestsSecondsFormatter:Format(secondsRemaining)
            AddLine(lines, MAP_TOOLTIP_TIME_LEFT:format(color:WrapTextInColorCode(formattedTime)),
                NORMAL_FONT_COLOR, true)
        end
    end

    local focusedQuestID = QuestMapFrame and QuestMapFrame.DetailsFrame and QuestMapFrame.DetailsFrame.questID
    local isWaypointQuest = questID == C_SuperTrack.GetSuperTrackedQuestID() or questID == focusedQuestID
    local waypointText = isWaypointQuest and C_QuestLog.GetNextWaypointText(questID)
    if waypointText and not IsSecret(waypointText) then
        AddLine(lines, QUEST_DASH .. waypointText, HIGHLIGHT_FONT_COLOR, true)
    elseif POIButtonUtil and pin.style == POIButtonUtil.Style.QuestInProgress then
        local questLogIndex = C_QuestLog.GetLogIndexForQuestID(questID)
        if questLogIndex then
            local itemDrops = GetNumQuestItemDrops(questLogIndex)
            if itemDrops > 0 then
                for index = 1, itemDrops do
                    local text, _, finished = GetQuestLogItemDrop(index, questLogIndex)
                    if text and not finished and not IsSecret(text) then
                        AddLine(lines, QUEST_DASH .. text, HIGHLIGHT_FONT_COLOR, true)
                    end
                end
            else
                for index = 1, GetNumQuestLeaderBoards(questLogIndex) do
                    local text, _, finished = GetQuestLogLeaderBoard(index, questLogIndex)
                    if text and not finished and not IsSecret(text) then
                        AddLine(lines, QUEST_DASH .. text, HIGHLIGHT_FONT_COLOR, true)
                    end
                end
            end
        end
    end
    return lines
end

local function HideCover()
    if cover then
        cover:Hide()
    end
    filledLines = nil
end

local function HideAll()
    HideCover()
    currentPin = nil
    currentQuestID = nil
    currentLines = nil
end

-- SetOwner clears the lines; line 1 uses the header font from the template.
local function FillCover(frame, lines)
    frame:SetOwner(UIParent, "ANCHOR_NONE")
    frame:SetMinimumWidth(0)
    for _, line in ipairs(lines) do
        frame:AddLine(line.text, line.color.r, line.color.g, line.color.b, line.wrap)
    end
end

-- Covers Blizzard's tooltip with ours, one level above it. Both carry the same
-- lines and ours adds the prefix, so ours is at least as large; when
-- Blizzard's width is readable it is also used as our minimum width.
local function ShowCover(lines)
    local frame = EnsureCover()
    if filledLines ~= lines then
        FillCover(frame, lines)
        filledLines = lines
    end
    local nativeWidth = GameTooltip:GetWidth()
    local widthSecret = IsSecret(nativeWidth)
    if not widthSecret then
        frame:SetMinimumWidth(nativeWidth)
    end
    local nativeLevel = GameTooltip:GetFrameLevel()
    if not IsSecret(nativeLevel) then
        frame:SetFrameLevel(nativeLevel + 10)
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", GameTooltip, "TOPLEFT", 0, 0)
    frame:Show()
    return widthSecret
end

local function FindHoveredQuestPin(map)
    if not map or not map.EnumeratePinsByTemplate then
        return nil
    end
    for _, template in ipairs(PIN_TEMPLATES) do
        local ok, iterator = pcall(map.EnumeratePinsByTemplate, map, template)
        if ok and iterator then
            for pin in iterator do
                -- IsMouseMotionFocus() returns a plain boolean, while IsMouseOver()
                -- is secret-aware when the region is anchored to a secret object.
                -- Suppression is not checked: Blizzard can leave a pin flagged
                -- suppressed while it is still drawn, and a hidden pin can never
                -- have mouse focus anyway.
                if pin.IsMouseMotionFocus then
                    local okFocus, hovered = pcall(pin.IsMouseMotionFocus, pin)
                    if okFocus and hovered == true and GetQuestID(pin) then
                        return pin
                    end
                end
            end
        end
    end
end

local function Update()
    if not WorldMapFrame or not WorldMapFrame:IsShown() or not AIW.IsEnabled() then
        HideAll()
        return
    end

    local pin = FindHoveredQuestPin(WorldMapFrame)
    local questID = GetQuestID(pin)
    if not questID then
        HideAll()
        -- Debug only: say why the map pin Blizzard's tooltip belongs to was not
        -- picked up as the hovered quest pin.
        local owner = AsItWasDB and AsItWasDB.debug and GameTooltip:IsShown() and GameTooltip:GetOwner()
        if owner and owner.pinTemplate then
            local okFocus, focused = pcall(owner.IsMouseMotionFocus, owner)
            Report(owner.questID, string.format("not found as hovered pin, template %s, mouse focus %s, suppressed %s",
                tostring(owner.pinTemplate), okFocus and tostring(focused) or "error",
                tostring(owner.IsSuppressed and owner:IsSuppressed())))
        else
            lastReport = nil
        end
        return
    end

    local prefix = AIW.MapTitlePrefix(questID)
    if prefix == "" then
        HideAll()
        return
    end

    -- Rebuilt while the title is still missing, so a quest whose data loads
    -- during the hover gets our tooltip as soon as it arrives.
    if pin ~= currentPin or questID ~= currentQuestID or not currentLines then
        currentPin = pin
        currentQuestID = questID
        currentLines = BuildLines(pin, questID, prefix)
    end

    -- Wait until Blizzard has shown its tooltip for this pin; it can arrive a
    -- frame later, or grow when quest data loads, so this runs every tick.
    if not currentLines then
        Report(questID, "not shown, quest title not loaded yet")
        HideCover()
        return
    end
    if not GameTooltip:IsShown() then
        HideCover()
        return
    end
    if GameTooltip:GetOwner() ~= pin then
        Report(questID, "not shown, Blizzard's tooltip belongs to another frame")
        HideCover()
        return
    end

    -- Restrictions can change between patches; an error from our own frame
    -- must never reach the player, so ours simply stays hidden.
    local ok, result = pcall(ShowCover, currentLines)
    if not ok then
        Report(questID, "not shown, error: " .. tostring(result))
        HideCover()
    elseif result then
        Report(questID, "shown, Blizzard's width is secret")
    else
        Report(questID, "shown")
    end
end

-- Runs every frame, not throttled: Blizzard's tooltip appears first and ours
-- covers it on the next update, so any delay here shows as a visible blink.
-- Update returns at once while the world map is closed.
local frame = CreateFrame("Frame")
frame:SetScript("OnUpdate", Update)

AIW.OnFilterChanged(HideAll)
