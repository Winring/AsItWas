local ADDON_NAME, AIW = ...
AsItWas = AIW

AsItWasDB = AsItWasDB or {}

local EXPANSION_NAME = {
    [7] = "Legion",
    [8] = "Battle for Azeroth",
    [9] = "Shadowlands",
    [10] = "Dragonflight",
    [11] = "The War Within",
    [12] = "Midnight",
}

-- Wiki-style tokens ({{bfa-inline}}, {{mn-inline}}, …). Same string
-- everywhere: HUD, titles, dropdown, future chip files. Full names stay
-- in EXPANSION_NAME only and are never mixed into those labels.
local EXPANSION_SHORT = {
    [7] = "Legion",
    [8] = "BfA",
    [9] = "SL",
    [10] = "DF",
    [11] = "TWW",
    [12] = "MN",
}

-- File stem for textures/chips/<stem>.png — matches the token, lowercase.
local EXPANSION_CHIP = {
    [7] = "legion",
    [8] = "bfa",
    [9] = "sl",
    [10] = "df",
    [11] = "tww",
    [12] = "mn",
}

-- Light brand tint only. Letters do the identifying.
local EXPANSION_HEX = {
    [7] = "6cc13f",
    [8] = "e8c34a",
    [9] = "b08ae6",
    [10] = "4eb6d4",
    [11] = "e0a24a",
    [12] = "9b87e0",
}

local function ExpansionMajorFromCode(code)
    if not code then
        return nil
    end
    return math.floor(code / 10000)
end

function AIW.ExpansionShort(major)
    return EXPANSION_SHORT[major] or ("Exp" .. tostring(major))
end

function AIW.ExpansionChipStem(major)
    return EXPANSION_CHIP[major]
end

function AIW.ColorizeExpansion(major, text)
    local hex = EXPANSION_HEX[major]
    if not hex or not text then
        return text
    end
    return "|cff" .. hex .. text .. "|r"
end

local filterOptions
local listeners = {}

local defaults = {
    filterId = "off",
    seenSetup = false,
    includeOlder = true,
    doNotAbandonOlder = true,
}

function AIW.Defaults()
    return defaults
end

function AIW.EnsureDB()
    if type(AsItWasDB) ~= "table" then
        AsItWasDB = {}
    end
    if AsItWasDB.filterId == nil then
        AsItWasDB.filterId = defaults.filterId
    end
    if AsItWasDB.seenSetup == nil then
        AsItWasDB.seenSetup = defaults.seenSetup
    end
    if AsItWasDB.includeOlder == nil then
        AsItWasDB.includeOlder = defaults.includeOlder
    end
    if AsItWasDB.doNotAbandonOlder == nil then
        AsItWasDB.doNotAbandonOlder = defaults.doNotAbandonOlder
    end
end

function AIW.FormatPatchCode(code)
    if not code then
        return "?"
    end
    local major = math.floor(code / 10000)
    local minor = math.floor((code % 10000) / 100)
    local patch = code % 100
    return string.format("%d.%d.%d", major, minor, patch)
end

function AIW.GetFilterOptions()
    if filterOptions then
        return filterOptions
    end
    local options = {
        { id = "off", kind = "off", label = "Off (do not mark quests)", min = 0, max = 0 },
    }
    local patches = AsItWasPatches or {}
    local byMajor = {}
    local majorOrder = {}
    for _, row in ipairs(patches) do
        local major = tonumber(string.match(row.patch, "^(%d+)"))
        if major then
            if not byMajor[major] then
                byMajor[major] = {}
                majorOrder[#majorOrder + 1] = major
            end
            byMajor[major][#byMajor[major] + 1] = row
        end
    end
    table.sort(majorOrder)
    for _, major in ipairs(majorOrder) do
        local group = byMajor[major]
        local first = group[1]
        local last = group[#group]
        local short = AIW.ExpansionShort(major)
        if major == 7 then
            options[#options + 1] = {
                id = first.patch,
                kind = "baseline",
                major = major,
                label = short .. " and older",
                min = first.code,
                max = first.code,
                patch = first.patch,
            }
        else
            options[#options + 1] = {
                id = tostring(major),
                kind = "expansion",
                major = major,
                label = short .. " (whole)",
                min = first.code,
                max = last.code,
                patch = last.patch,
            }
            for _, row in ipairs(group) do
                options[#options + 1] = {
                    id = row.patch,
                    kind = "patch",
                    major = major,
                    label = short .. " " .. row.patch,
                    min = row.code,
                    max = row.code,
                    patch = row.patch,
                }
            end
        end
    end
    filterOptions = options
    return options
end

function AIW.GetFilterById(id)
    for _, opt in ipairs(AIW.GetFilterOptions()) do
        if opt.id == id then
            return opt
        end
    end
    return AIW.GetFilterOptions()[1]
end

function AIW.GetActiveFilter()
    AIW.EnsureDB()
    return AIW.GetFilterById(AsItWasDB.filterId)
end

-- Abbreviation + the bit that changes. Off stays hidden.
function AIW.GetFilterHudText()
    local filter = AIW.GetActiveFilter()
    if not filter or filter.kind == "off" then
        return nil
    end
    local short = AIW.ExpansionShort(filter.major)
    local text
    if filter.kind == "patch" then
        text = short .. " " .. filter.patch
    elseif filter.kind == "baseline" then
        text = short .. " and older"
    else
        text = short .. " (whole)"
    end
    return AIW.ColorizeExpansion(filter.major, text)
end

function AIW.IsEnabled()
    local filter = AIW.GetActiveFilter()
    return filter and filter.kind ~= "off"
end

function AIW.QuestPatch(questID)
    if not questID then
        return nil
    end
    return AsItWasQuestPatch and AsItWasQuestPatch[questID]
end

-- Unknown IDs are not treated as in-range for titles; overlay handles them separately.
function AIW.IsUnknown(questID)
    if not AIW.IsEnabled() or not questID then
        return false
    end
    return AIW.QuestPatch(questID) == nil
end
function AIW.IsInRange(questID)
    if not AIW.IsEnabled() then
        return true
    end
    local patch = AIW.QuestPatch(questID)
    if not patch then
        return true
    end
    local filter = AIW.GetActiveFilter()
    if AsItWasDB.includeOlder ~= false then
        return patch <= filter.max
    end
    return patch >= filter.min and patch <= filter.max
end

function AIW.IsNewerThanFilter(questID)
    if not AIW.IsEnabled() then
        return false
    end
    local patch = AIW.QuestPatch(questID)
    if not patch then
        return false
    end
    return patch > AIW.GetActiveFilter().max
end

function AIW.IsOlderThanFilter(questID)
    if not AIW.IsEnabled() then
        return false
    end
    if AsItWasDB.includeOlder ~= false then
        return false
    end
    local patch = AIW.QuestPatch(questID)
    if not patch then
        return false
    end
    return patch < AIW.GetActiveFilter().min
end

-- "newer" / "older" / nil. Used for the two map badges.
function AIW.OutOfRangeKind(questID)
    if AIW.IsNewerThanFilter(questID) then
        return "newer"
    end
    if AIW.IsOlderThanFilter(questID) then
        return "older"
    end
    return nil
end

local CHIP_H = 14
local CHIP_W = 21 -- chips are 202x132
local CHIP_FILE_W = 202
local CHIP_FILE_H = 132
local MARK_H = 14
local ARROW_FILE = 64
local TEX_CHIPS = "Interface\\AddOns\\" .. ADDON_NAME .. "\\textures\\chips\\"
local TEX_NEWER = "Interface\\AddOns\\" .. ADDON_NAME .. "\\textures\\newer.png"
local TEX_OLDER = "Interface\\AddOns\\" .. ADDON_NAME .. "\\textures\\older.png"
local TEX_WARNING = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew"
local TEX_UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Same helpers Blizzard uses (TextureUtil.lua). PNG paths keep the .png; XML does too
-- (e.g. Interface\Transmogrify\Textures.png). SetTexture without an extension
-- resolves .blp/.tga, which is why these files were blank.
local function FileMarkup(path, fileW, fileH, w, h)
    return CreateTextureMarkup(path, fileW, fileH, w, h, 0, 1, 0, 1)
end

local function SimpleMarkup(path, size)
    return CreateSimpleTextureMarkup(path, size, size)
end

function AIW.ExpansionChipMarkup(major)
    local stem = AIW.ExpansionChipStem(major)
    if not stem then
        return ""
    end
    return FileMarkup(TEX_CHIPS .. stem .. ".png", CHIP_FILE_W, CHIP_FILE_H, CHIP_W, CHIP_H)
end

function AIW.StripTitleMark(title)
    title = title or ""
    local prev
    repeat
        prev = title
        title = title:gsub("^|T.-|t%s*", "")
    until title == prev
    title = title:gsub("^|c%x%x%x%x%x%x%x%x%[[^%]]+%]|r%s*", "")
    title = title:gsub("^%[[^%]]+%]%s*", "")
    title = title:gsub("^%[%?%]%s*", "")
    title = title:gsub("^%d+%.%d+%.%d+%s+", "")
    return title
end

-- style "list" (quest log / NPC): warning when out of range.
-- style "map" (pin tooltip): newer/older arrow, or nothing when in range.
function AIW.MarkTitle(questID, title, style)
    title = AIW.StripTitleMark(title)
    if not AIW.IsEnabled() then
        return title
    end
    local patch = AIW.QuestPatch(questID)
    if not patch then
        return table.concat({ SimpleMarkup(TEX_UNKNOWN, MARK_H), "[?]", title }, " ")
    end
    local major = ExpansionMajorFromCode(patch)
    local parts = {}
    if style == "map" then
        local kind = AIW.OutOfRangeKind(questID)
        if kind == "newer" then
            parts[#parts + 1] = FileMarkup(TEX_NEWER, ARROW_FILE, ARROW_FILE, MARK_H, MARK_H)
        elseif kind == "older" then
            parts[#parts + 1] = FileMarkup(TEX_OLDER, ARROW_FILE, ARROW_FILE, MARK_H, MARK_H)
        end
    elseif not AIW.IsInRange(questID) then
        parts[#parts + 1] = SimpleMarkup(TEX_WARNING, MARK_H)
    end
    local chip = AIW.ExpansionChipMarkup(major)
    if chip ~= "" then
        parts[#parts + 1] = chip
    end
    parts[#parts + 1] = AIW.FormatPatchCode(patch)
    parts[#parts + 1] = title
    return table.concat(parts, " ")
end

function AIW.RetitleMapTooltip(questID)
    if not questID or not GameTooltip or not GameTooltip:IsShown() then
        return
    end
    local line = _G[GameTooltip:GetName() .. "TextLeft1"]
    if not line then
        return
    end
    local text = line:GetText()
    if not text or text == RETRIEVING_DATA then
        return
    end
    local marked = AIW.MarkTitle(questID, text, "map")
    if marked ~= text then
        line:SetText(marked)
        GameTooltip:Show()
    end
end

function AIW.OnFilterChanged(callback)
    listeners[#listeners + 1] = callback
end

function AIW.SetFilterId(id)
    AIW.EnsureDB()
    AsItWasDB.filterId = id
    AIW.NotifyChanged()
end

function AIW.SetIncludeOlder(value)
    AIW.EnsureDB()
    AsItWasDB.includeOlder = value and true or false
    AIW.NotifyChanged()
end

function AIW.ApplyFilter(filterId, includeOlder)
    AIW.EnsureDB()
    AsItWasDB.filterId = filterId
    if includeOlder ~= nil then
        AsItWasDB.includeOlder = includeOlder and true or false
    end
    AIW.NotifyChanged()
end

function AIW.NotifyChanged()
    for _, callback in ipairs(listeners) do
        callback()
    end
end

function AIW.Print(msg)
    print("|cff66ccffAs It Was|r:", msg)
end

-- Diagnostics only. Off by default and the first line returns before any
-- string work, because the minimap pass runs from OnUpdate.
function AIW.Debug(fmt, ...)
    if not AsItWasDB or not AsItWasDB.debug then
        return
    end
    print("|cff66ccffAIW|r " .. string.format(fmt, ...))
end

function AIW.ToggleDebug()
    AIW.EnsureDB()
    AsItWasDB.debug = not AsItWasDB.debug
    AIW.Print(AsItWasDB.debug and "debug on" or "debug off")
end

-- Same family as MinimapZoneText (GameFontNormal / Friz), one step smaller:
-- GameFontNormalSmall = SystemFont_Shadow_Small = Fonts\FRIZQT__.TTF height 10.
local hudButton

local function UpdateFilterHud()
    if not hudButton then
        return
    end
    local caption = AIW.GetFilterHudText()
    if not caption then
        hudButton:Hide()
        return
    end
    hudButton.Text:SetText(caption)
    hudButton:SetWidth(hudButton.Text:GetStringWidth() + 2)
    hudButton:Show()
end

local function CreateFilterHud()
    if hudButton or not MinimapCluster or not MinimapCluster.ZoneTextButton then
        return
    end
    local button = CreateFrame("Button", "AsItWasMinimapFilter", MinimapCluster)
    button:SetPoint("TOPLEFT", MinimapCluster.ZoneTextButton, "BOTTOMLEFT", 0, -3)
    button:SetHeight(12)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", button, "LEFT", 0, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    button.Text = text
    button:SetScript("OnClick", function()
        AIW.OpenOptions()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("As It Was", 1, 1, 1)
        GameTooltip:AddLine("Click to change the era filter.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    hudButton = button
    UpdateFilterHud()
end

AIW.OnFilterChanged(UpdateFilterHud)

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        AIW.EnsureDB()
        AIW.GetFilterOptions()
        -- Blizzard_Minimap is not LoadOnDemand, so ContinueOnAddOnLoaded runs
        -- CreateFilterHud while this file is still executing (EventUtil.lua:69),
        -- before SavedVariables exist. The caption was therefore built from the
        -- default Off and stayed hidden until the filter changed.
        UpdateFilterHud()
    elseif event == "PLAYER_LOGIN" then
        AIW.EnsureDB()
        CreateFilterHud()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- HandlePlayerEnteringWorld calls CloseAllWindows(1), which hides
        -- UISpecialFrames. Showing first-run on PLAYER_LOGIN therefore
        -- auto-dismisses every character and writes seenSetup. Wait a frame.
        C_Timer.After(0, function()
            AIW.EnsureDB()
            if AIW.RefreshTitles then
                AIW.RefreshTitles()
            end
            if AIW.RefreshMapOverlays then
                AIW.RefreshMapOverlays()
            end
            if not AsItWasDB.seenSetup then
                AIW.ShowFirstRun()
            end
        end)
    end
end)

EventUtil.ContinueOnAddOnLoaded("Blizzard_Minimap", CreateFilterHud)

SLASH_ASITWAS1 = "/asitwas"
SLASH_ASITWAS2 = "/aiw"
SlashCmdList.ASITWAS = function(msg)
    msg = string.lower(strtrim(msg or ""))
    if msg == "options" or msg == "" then
        AIW.OpenOptions()
    elseif msg == "abandon" or msg == "clean" then
        AIW.ConfirmMassAbandon()
    elseif msg == "setup" then
        AIW.EnsureDB()
        AsItWasDB.seenSetup = false
        AIW.ShowFirstRun()
    elseif msg == "debug" then
        AIW.ToggleDebug()
    elseif msg == "debug map" then
        AIW.DumpMinimap()
    else
        AIW.Print("/aiw options  /aiw setup  /aiw abandon  /aiw debug  /aiw debug map")
    end
end
