local _, AIW = ...

-- One place for [X.Y.Z] prefixes. Blizzard already formats these titles;
-- we change the string it is given, then let it draw.

local hooked = {
    decorate = false,
    dialogue = false,
    gossip = false,
    greeting = false,
    progress = false,
    tracker = false,
}

local function DecorateDialogueTitle(dialogue)
    local questID = dialogue and dialogue.questID
    local header = dialogue and dialogue.FrontFrame and dialogue.FrontFrame.Header
    local title = header and header.Title
    if questID and title then
        title:SetText(AIW.MarkTitle(questID, title:GetText()))
    end
end

local function DecorateDialogueQuestButtons(dialogue)
    local pool = dialogue and dialogue.optionButtonPool
    if not pool or not pool.ProcessActiveObjects then
        return
    end

    pool:ProcessActiveObjects(function(button)
        if button.IsQuestButton and button:IsQuestButton() and button.questID and button.Name then
            button:SetButtonText(AIW.MarkTitle(button.questID, button.Name:GetText()), true)
        end
    end)
end

local function WrapDialogue()
    if hooked.dialogue then
        return
    end

    local dialogue = DUIQuestFrame
    if not dialogue or not dialogue.UpdateQuestTitle or not dialogue.FrontFrame then
        return
    end

    hooked.dialogue = true
    hooksecurefunc(dialogue, "UpdateQuestTitle", function(self)
        DecorateDialogueTitle(self)
    end)
    if dialogue.HandleGossip then
        hooksecurefunc(dialogue, "HandleGossip", function(self)
            DecorateDialogueQuestButtons(self)
        end)
    end
    if dialogue:IsShown() then
        DecorateDialogueTitle(dialogue)
        DecorateDialogueQuestButtons(dialogue)
    end
end

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

-- CreateFromMixins copies methods, so the derived gossip mixins already hold
-- their own UpdateTitleForQuest by the time we load (GossipFrameShared.lua:44,
-- GossipFrame.lua:35). Wrapping only the shared one never reaches the buttons.
local GOSSIP_MIXINS = {
    "GossipSharedQuestButtonMixin",
    "GossipSharedAvailableQuestButtonMixin",
    "GossipSharedActiveQuestButtonMixin",
    "GossipQuestButtonMixin",
    "GossipAvailableQuestButtonMixin",
    "GossipActiveQuestButtonMixin",
}

local wrappedGossipMixins = {}

local function WrapGossip()
    for _, name in ipairs(GOSSIP_MIXINS) do
        local mixin = _G[name]
        if mixin and not wrappedGossipMixins[name] and rawget(mixin, "UpdateTitleForQuest") then
            wrappedGossipMixins[name] = true
            local original = mixin.UpdateTitleForQuest
            mixin.UpdateTitleForQuest = function(self, questID, titleText, isIgnored, isTrivial)
                original(self, questID, AIW.MarkTitle(questID, titleText), isIgnored, isTrivial)
            end
        end
    end
    hooked.gossip = true
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

local TRACKER_FRAMES = {
    "QuestObjectiveTracker",
    "CampaignQuestObjectiveTracker",
    "BonusObjectiveTracker",
    "WorldQuestObjectiveTracker",
}

local wrappedTrackerFrames = {}

local function DecorateTrackerBlock(module, questID, title)
    if not questID or not module or not module.GetExistingBlock then
        return
    end
    local block = module:GetExistingBlock(questID)
    if not block or not block.HeaderText then
        return
    end
    local current = block.HeaderText:GetText()
    local marked = AIW.MarkTitle(questID, title or current)
    if not marked or marked == current then
        return
    end
    -- Objective lines anchor to HeaderText (ObjectiveTrackerBlock.lua:192), so
    -- they follow on their own. Only the block height was measured before the
    -- prefix went in, so carry the difference over.
    local before = block.HeaderText:GetHeight()
    block.HeaderText:SetText(marked)
    local delta = block.HeaderText:GetHeight() - before
    if delta ~= 0 then
        block:SetHeight(block:GetHeight() + delta)
    end
end

-- XML mixin= copies methods onto the frame. hooksecurefunc on
-- ObjectiveTrackerBlockMixin.SetHeader does not run on those copies.
-- Hook the live module frames instead (QuestObjectiveTracker.lua:280).
local function WrapTracker()
    for _, name in ipairs(TRACKER_FRAMES) do
        local frame = _G[name]
        if frame and not wrappedTrackerFrames[name] then
            wrappedTrackerFrames[name] = true
            if frame.UpdateSingle then
                hooksecurefunc(frame, "UpdateSingle", function(self, quest)
                    if not quest then
                        return
                    end
                    local questID = quest.GetID and quest:GetID()
                    DecorateTrackerBlock(self, questID, quest.title)
                end)
            end
            if frame.SetUpQuestBlock then
                hooksecurefunc(frame, "SetUpQuestBlock", function(self, block)
                    if block and type(block.id) == "number" then
                        DecorateTrackerBlock(self, block.id, block.taskName)
                    end
                end)
            end
        end
    end
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

-- ObjectiveTrackerManager:UpdateAll is a dirty update: a module that is not
-- marked dirty keeps its cached layout and never runs UpdateSingle again
-- (ObjectiveTrackerModule.lua:134). Without this the titles only appear after
-- something else dirties the tracker.
local function MarkTrackerModulesDirty()
    for _, name in ipairs(TRACKER_FRAMES) do
        local frame = _G[name]
        if frame and frame.MarkDirty then
            frame:MarkDirty()
        end
    end
end

function AIW.RefreshTitles()
    WrapDecorate()
    WrapDialogue()
    WrapGossip()
    WrapGreeting()
    WrapProgress()
    WrapTracker()

    if QuestLogQuests_Update then
        pcall(QuestLogQuests_Update)
    end
    if ObjectiveTrackerManager and ObjectiveTrackerManager.UpdateAll then
        pcall(function()
            MarkTrackerModulesDirty()
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
WrapDialogue()
HookMapTooltips()
EventUtil.ContinueOnAddOnLoaded("Blizzard_UIPanels_Game", function()
    WrapGossip()
    WrapGreeting()
    WrapProgress()
    HookMapTooltips()
end)
EventUtil.ContinueOnAddOnLoaded("Blizzard_SharedMapDataProviders", HookMapTooltips)
EventUtil.ContinueOnAddOnLoaded("Blizzard_ObjectiveTracker", WrapTracker)
EventUtil.ContinueOnAddOnLoaded("DialogueUI", WrapDialogue)

AIW.OnFilterChanged(AIW.RefreshTitles)
