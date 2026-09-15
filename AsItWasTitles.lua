local _, AIW = ...

-- One place for [X.Y.Z] prefixes. Blizzard already formats these titles;
-- we change the string it is given, then let it draw.

local hooked = {
    decorate = false,
    gossip = false,
    greeting = false,
    progress = false,
    tracker = false,
}

local function WrapDecorate()
    if hooked.decorate or not QuestUtils_DecorateQuestText then
        return
    end
    hooked.decorate = true
    local original = QuestUtils_DecorateQuestText
    function QuestUtils_DecorateQuestText(questID, text, ...)
        return original(questID, AIW.MarkTitle(questID, text), ...)
    end
end

local function WrapGossip()
    if hooked.gossip or not GossipSharedQuestButtonMixin or not GossipSharedQuestButtonMixin.UpdateTitleForQuest then
        return
    end
    hooked.gossip = true
    local original = GossipSharedQuestButtonMixin.UpdateTitleForQuest
    function GossipSharedQuestButtonMixin.UpdateTitleForQuest(self, questID, titleText, isIgnored, isTrivial)
        original(self, questID, AIW.MarkTitle(questID, titleText), isIgnored, isTrivial)
    end
end

local function PrefixGreetingButtons()
    if not QuestFrameGreetingPanel or not QuestFrameGreetingPanel.titleButtonPool then
        return
    end
    for button in QuestFrameGreetingPanel.titleButtonPool:EnumerateActive() do
        local questID, title, isTrivial
        local index = button:GetID()
        if button.isActive == 1 then
            questID = GetActiveQuestID(index)
            title = GetActiveTitle(index)
            isTrivial = IsActiveQuestTrivial(index)
        else
            local trivial
            trivial, _, _, _, questID = GetAvailableQuestInfo(index)
            isTrivial = trivial
            title = GetAvailableTitle(index)
        end
        if questID and title then
            local marked = AIW.MarkTitle(questID, title)
            if isTrivial then
                button:SetFormattedText(TRIVIAL_QUEST_DISPLAY, marked)
            else
                button:SetFormattedText(NORMAL_QUEST_DISPLAY, marked)
            end
            button:SetHeight(math.max(button:GetTextHeight() + 2, button.Icon and button.Icon:GetHeight() or 0))
        end
    end
end

local function WrapGreeting()
    if hooked.greeting or not QuestFrameGreetingPanel_OnShow then
        return
    end
    hooked.greeting = true
    hooksecurefunc("QuestFrameGreetingPanel_OnShow", PrefixGreetingButtons)
end

local function PrefixProgressTitle()
    if not QuestProgressTitleText or not GetQuestID or not GetTitleText then
        return
    end
    QuestProgressTitleText:SetText(AIW.MarkTitle(GetQuestID(), GetTitleText()))
end

local function WrapProgress()
    if hooked.progress or not QuestFrameProgressPanel_OnShow then
        return
    end
    hooked.progress = true
    hooksecurefunc("QuestFrameProgressPanel_OnShow", PrefixProgressTitle)
end

local function TrackerQuestID(block)
    if not block or type(block.id) ~= "number" then
        return nil
    end
    local module = block.parentModule
    if not module then
        return nil
    end
    if module.GetTag and module:GetTag() == "quest" then
        return block.id
    end
    -- Bonus and world-quest modules use quest IDs as block.id.
    if module.showWorldQuests ~= nil then
        return block.id
    end
    return nil
end

local function WrapTracker()
    if hooked.tracker or not ObjectiveTrackerBlockMixin or not ObjectiveTrackerBlockMixin.SetHeader then
        return
    end
    hooked.tracker = true
    hooksecurefunc(ObjectiveTrackerBlockMixin, "SetHeader", function(self, text)
        local questID = TrackerQuestID(self)
        if not questID or not self.HeaderText then
            return
        end
        local marked = AIW.MarkTitle(questID, text)
        if marked ~= text then
            if self.SetStringText then
                self:SetStringText(self.HeaderText, marked, nil, OBJECTIVE_TRACKER_COLOR and OBJECTIVE_TRACKER_COLOR["Header"], self.isHighlighted)
            else
                self.HeaderText:SetText(marked)
            end
        end
    end)
end

function AIW.RefreshTitles()
    WrapDecorate()
    WrapGossip()
    WrapGreeting()
    WrapProgress()
    WrapTracker()

    if QuestLogQuests_Update then
        pcall(QuestLogQuests_Update)
    end
    if ObjectiveTrackerManager and ObjectiveTrackerManager.UpdateAll then
        pcall(function()
            ObjectiveTrackerManager:UpdateAll()
        end)
    end
    if GossipFrame and GossipFrame.Update and GossipFrame:IsShown() then
        pcall(function()
            GossipFrame:Update()
        end)
    end
    if QuestFrameGreetingPanel and QuestFrameGreetingPanel:IsShown() then
        PrefixGreetingButtons()
    end
    if QuestFrameProgressPanel and QuestFrameProgressPanel:IsShown() then
        PrefixProgressTitle()
    end
    if QuestInfo_ShowTitle and QuestInfoTitleHeader and QuestInfoTitleHeader:IsVisible() then
        pcall(QuestInfo_ShowTitle)
    end
end

local mapTooltipHooks = {}
local function HookMapTooltips()
    if not mapTooltipHooks.pin and QuestPinMixin and QuestPinMixin.OnMouseEnter then
        mapTooltipHooks.pin = true
        hooksecurefunc(QuestPinMixin, "OnMouseEnter", function(self)
            local questID = self.GetQuestID and self:GetQuestID() or self.questID
            if questID then
                AIW.RetitleMapTooltip(questID)
            end
        end)
    end
    if not mapTooltipHooks.task and TaskPOI_OnEnter then
        mapTooltipHooks.task = true
        hooksecurefunc("TaskPOI_OnEnter", function(self)
            if self and self.questID then
                AIW.RetitleMapTooltip(self.questID)
            end
        end)
    end
    if not mapTooltipHooks.calling and CallingPOI_OnEnter then
        mapTooltipHooks.calling = true
        hooksecurefunc("CallingPOI_OnEnter", function(self)
            if self and self.questID then
                AIW.RetitleMapTooltip(self.questID)
            end
        end)
    end
end

WrapDecorate()
HookMapTooltips()
EventUtil.ContinueOnAddOnLoaded("Blizzard_UIPanels_Game", function()
    WrapGossip()
    WrapGreeting()
    WrapProgress()
    HookMapTooltips()
end)
EventUtil.ContinueOnAddOnLoaded("Blizzard_SharedMapDataProviders", HookMapTooltips)
EventUtil.ContinueOnAddOnLoaded("Blizzard_ObjectiveTracker", WrapTracker)

AIW.OnFilterChanged(AIW.RefreshTitles)
