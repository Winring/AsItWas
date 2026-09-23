local ADDON_NAME, AIW = ...

local settingsCategory
local optionsDropdown
local optionsOlder
local optionsMinimap
local firstRunFrame

local function FillFilterMenu(rootDescription, getId, setId, includeOff)
    rootDescription:SetScrollMode(240)
    local function IsSelected(id)
        return getId() == id
    end
    if includeOff then
        rootDescription:CreateRadio("Off (do not mark quests)", IsSelected, setId, "off")
        rootDescription:CreateDivider()
    end
    for _, opt in ipairs(AIW.GetFilterOptions()) do
        if opt.kind ~= "off" then
            rootDescription:CreateRadio(opt.label, IsSelected, setId, opt.id)
        end
    end
end

local function MakeDropdown(parent, getId, setId, includeOff, defaultText)
    local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(360)
    dropdown:SetDefaultText(defaultText)
    dropdown:SetupMenu(function(_, rootDescription)
        FillFilterMenu(rootDescription, getId, setId, includeOff)
    end)
    return dropdown
end

local function MakeOlderCheckbox(parent, getter, setter)
    local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    box.Text:SetText("Include older quests")
    box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Include older quests", 1, 1, 1)
        GameTooltip:AddLine("Earlier patches stay unmarked. Later patches get the blue badge.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", GameTooltip_Hide)
    box:SetScript("OnClick", function(self)
        setter(self:GetChecked())
    end)
    box.Refresh = function(self)
        self:SetChecked(getter())
    end
    return box
end

local function MakeMinimapCheckbox(parent, getter, setter)
    local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    box.Text:SetText("Show minimap quest badges")
    box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Show minimap quest badges", 1, 1, 1)
        GameTooltip:AddLine("Disable this if minimap quest markers are incomplete or cause problems.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", GameTooltip_Hide)
    box:SetScript("OnClick", function(self)
        setter(self:GetChecked())
    end)
    box.Refresh = function(self)
        self:SetChecked(getter())
    end
    return box
end

local function BuildOptionsFrame()
    local frame = CreateFrame("Frame")
    local intro = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    intro:SetPoint("TOPLEFT", 0, 0)
    intro:SetPoint("TOPRIGHT", 0, 0)
    intro:SetJustifyH("LEFT")
    intro:SetText("Play this expansion or patch as it was. Later quests are marked, not blocked.")

    optionsDropdown = MakeDropdown(frame, function()
        AIW.EnsureDB()
        return AsItWasDB.filterId
    end, function(id)
        AIW.SetFilterId(id)
    end, true, "Off (do not mark quests)")
    optionsDropdown:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -16)

    optionsOlder = MakeOlderCheckbox(frame, function()
        AIW.EnsureDB()
        return AsItWasDB.includeOlder ~= false
    end, function(checked)
        AIW.SetIncludeOlder(checked)
    end)
    optionsOlder:SetPoint("TOPLEFT", optionsDropdown, "BOTTOMLEFT", -6, -12)
    optionsOlder:Refresh()

    optionsMinimap = MakeMinimapCheckbox(frame, function()
        return AIW.IsMinimapBadgesEnabled()
    end, function(checked)
        AIW.SetMinimapBadgesEnabled(checked)
    end)
    optionsMinimap:SetPoint("TOPLEFT", optionsOlder, "BOTTOMLEFT", 0, -8)
    optionsMinimap:Refresh()

    AIW.OnFilterChanged(function()
        if optionsOlder then
            optionsOlder:Refresh()
        end
        if optionsMinimap then
            optionsMinimap:Refresh()
        end
    end)

    function frame:OnRefresh()
        AIW.EnsureDB()
        if optionsDropdown then
            optionsDropdown:GenerateMenu()
        end
        if optionsOlder then
            optionsOlder:Refresh()
        end
        if optionsMinimap then
            optionsMinimap:Refresh()
        end
    end

    return frame
end

local function BuildFirstRunFrame()
    local draft = {
        filterId = nil,
        includeOlder = true,
    }

    local frame = CreateFrame("Frame", "AsItWasFirstRunFrame", UIParent, "DefaultPanelTemplate")
    frame:SetSize(440, 280)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetTitle("As It Was")
    frame:Hide()
    table.insert(UISpecialFrames, "AsItWasFirstRunFrame")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 3, 3)

    local intro = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    intro:SetPoint("TOPLEFT", 20, -36)
    intro:SetPoint("TOPRIGHT", -20, -36)
    intro:SetJustifyH("LEFT")
    intro:SetText("Pick the era you want to play as it was. Confirm to start marking later quests. Close this window to leave the addon off.")

    local dropdown = MakeDropdown(frame, function()
        return draft.filterId
    end, function(id)
        draft.filterId = id
        if frame.Confirm then
            frame.Confirm:SetEnabled(id ~= nil)
        end
    end, false, "Choose a patch")
    dropdown:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -20)

    local older = MakeOlderCheckbox(frame, function()
        return draft.includeOlder ~= false
    end, function(checked)
        draft.includeOlder = checked and true or false
    end)
    older:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", -6, -12)

    local confirm = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    confirm:SetSize(120, 22)
    confirm:SetPoint("BOTTOMLEFT", 20, 18)
    confirm:SetText(ACCEPT)
    confirm:SetEnabled(false)
    confirm:SetScript("OnClick", function()
        if not draft.filterId then
            return
        end
        AIW.EnsureDB()
        if not pcall(AIW.ApplyFilter, draft.filterId, draft.includeOlder) then
            return
        end
        frame.applied = true
        AsItWasDB.seenSetup = true
        frame:Hide()
    end)
    frame.Confirm = confirm

    local noFilter = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    noFilter:SetSize(120, 22)
    noFilter:SetPoint("BOTTOMRIGHT", -20, 18)
    noFilter:SetText("No filter")
    noFilter:SetScript("OnClick", function()
        frame:Hide()
    end)

    frame:SetScript("OnShow", function()
        draft.filterId = nil
        draft.includeOlder = true
        frame.applied = false
        confirm:SetEnabled(false)
        older:Refresh()
        dropdown:GenerateMenu()
    end)

    frame:SetScript("OnHide", function()
        if frame.applied then
            return
        end
        -- CloseAllWindows (PEW / death / Esc-all) hides UISpecialFrames.
        -- Do not treat that as the player picking Off.
        if not frame.userCanDismiss then
            return
        end
        AIW.EnsureDB()
        if not pcall(AIW.ApplyFilter, "off", true) then
            return
        end
        AsItWasDB.seenSetup = true
    end)

    return frame
end

local function HookQuestLogMenu()
    if not Menu or not Menu.ModifyMenu then
        return
    end
    Menu.ModifyMenu("MENU_QUEST_MAP_FRAME_SETTINGS", function(_, rootDescription)
        rootDescription:CreateDivider()
        rootDescription:CreateTitle("As It Was")
        rootDescription:CreateCheckbox("Don't abandon older quests", function()
            AIW.EnsureDB()
            return AsItWasDB.doNotAbandonOlder ~= false
        end, function()
            AIW.EnsureDB()
            AsItWasDB.doNotAbandonOlder = AsItWasDB.doNotAbandonOlder == false
        end)
        rootDescription:CreateButton("Abandon later quests", function()
            AIW.ConfirmMassAbandon()
        end)
    end)
end

function AIW.ShowFirstRun()
    AIW.EnsureDB()
    if AsItWasDB.seenSetup then
        return
    end
    if not firstRunFrame then
        firstRunFrame = BuildFirstRunFrame()
    end
    firstRunFrame.userCanDismiss = false
    firstRunFrame:Show()
    C_Timer.After(0, function()
        if firstRunFrame and firstRunFrame:IsShown() then
            firstRunFrame.userCanDismiss = true
        end
    end)
end

function AIW.OpenOptions()
    if settingsCategory then
        Settings.OpenToCategory(settingsCategory:GetID())
    else
        AIW.Print("Settings are not ready yet.")
    end
end

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
    local optionsFrame = BuildOptionsFrame()
    local category = Settings.RegisterCanvasLayoutCategory(optionsFrame, "As It Was")
    Settings.RegisterAddOnCategory(category)
    settingsCategory = category
    HookQuestLogMenu()
end)
