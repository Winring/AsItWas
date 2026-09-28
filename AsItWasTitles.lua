local _, AIW = ...

-- One place for [X.Y.Z] prefixes. Blizzard already formats these titles;
-- we change the string it is given, then let it draw.

local hooked = {
    dialogue = false,
    dialogueOptions = false,
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

local function HookDialogueOptionButtons()
    if hooked.dialogueOptions then
        return
    end

    local mixin = _G.DUIDialogOptionButtonMixin
    if not mixin or not rawget(mixin, "SetQuest") then
        return
    end

    hooked.dialogueOptions = true
    hooksecurefunc(mixin, "SetQuest", function(button)
        local questID = button and button.questID
        local title = button and button.Name
        if questID and title then
            button:SetButtonText(AIW.MarkTitle(questID, title:GetText()), true)
        end
    end)
end

local function WrapDialogue()
    if hooked.dialogue then
        return
    end

    HookDialogueOptionButtons()

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

local questLogHooked = false
local function PrefixQuestLogRows()
    local pool = QuestScrollFrame and QuestScrollFrame.titleFramePool
    if not pool or not pool.EnumerateActive then
        return
    end
    for button in pool:EnumerateActive() do
        if button.questID and button.Text then
            local current = button.Text:GetText()
            local marked = AIW.MarkTitle(button.questID, current)
            if marked ~= current then
                button.Text:SetText(marked)
            end
        end
    end
end

local questInfoHooked = false
local function SetMarkedTitle(title, questID)
    if not title or not questID then
        return
    end

    local current = title:GetText()
    local marked = AIW.MarkTitle(questID, current)
    if marked ~= current then
        title:SetText(marked)
    end
end

local function PrefixQuestInfoTitle()
    if not QuestInfoTitleHeader then
        return
    end

    local questID
    if QuestMapFrame and QuestMapFrame.DetailsFrame and QuestMapFrame.DetailsFrame.questID then
        questID = QuestMapFrame.DetailsFrame.questID
    elseif QuestInfoFrame and QuestInfoFrame.questLog and C_QuestLog and C_QuestLog.GetSelectedQuest then
        questID = C_QuestLog.GetSelectedQuest()
    elseif GetQuestID then
        questID = GetQuestID()
    end

    if not questID then
        return
    end

    SetMarkedTitle(QuestInfoTitleHeader, questID)
end

local questLogPopupHooked = false
local function PrefixQuestLogPopupTitle()
    if not QuestInfoTitleHeader then
        return
    end

    local questID = QuestLogPopupDetailFrame and QuestLogPopupDetailFrame.questID
    if not questID and C_QuestLog and C_QuestLog.GetSelectedQuest then
        questID = C_QuestLog.GetSelectedQuest()
    end
    if not questID then
        return
    end

    SetMarkedTitle(QuestInfoTitleHeader, questID)
end

local function WrapQuestLog()
    if questLogHooked or not QuestLogQuests_Update then
        return
    end
    questLogHooked = true
    hooksecurefunc("QuestLogQuests_Update", PrefixQuestLogRows)
end

local function WrapQuestInfo()
    if questInfoHooked or not QuestInfo_Display then
        return
    end
    questInfoHooked = true
    hooksecurefunc("QuestInfo_Display", PrefixQuestInfoTitle)
end

local function WrapQuestLogPopup()
    if questLogPopupHooked or not QuestLogPopupDetailFrame_Update then
        return
    end
    questLogPopupHooked = true
    hooksecurefunc("QuestLogPopupDetailFrame_Update", PrefixQuestLogPopupTitle)
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
local objectiveTrackerAuraGuardApplied = false

-- Blizzard's objective-tracker check reads a restricted aura without a guard.
-- MAW is only the function name in the stack; the restriction also affects
-- unrelated Midnight event/scenario layouts.
local function ApplyObjectiveTrackerAuraGuard()
    if objectiveTrackerAuraGuardApplied or type(ShouldShowMawBuffs) ~= "function" then
        return
    end
    if not C_Secrets or not C_Secrets.ShouldAurasBeSecret then
        return
    end

    objectiveTrackerAuraGuardApplied = true
    local original = ShouldShowMawBuffs
    ShouldShowMawBuffs = function()
        if C_Secrets.ShouldAurasBeSecret() then
            return false
        end
        return original()
    end
end

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
    ApplyObjectiveTrackerAuraGuard()
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
            securecallfunction(frame.MarkDirty, frame)
        end
    end
end

function AIW.RefreshTitles()
    WrapDialogue()
    WrapQuestLog()
    WrapQuestInfo()
    WrapQuestLogPopup()
    WrapGossip()
    WrapGreeting()
    WrapProgress()
    WrapTracker()

    if QuestLogQuests_Update then
        pcall(QuestLogQuests_Update)
    end
    if ObjectiveTrackerManager and ObjectiveTrackerManager.UpdateAll then
        MarkTrackerModulesDirty()
        securecallfunction(ObjectiveTrackerManager.UpdateAll, ObjectiveTrackerManager)
    end
    if GossipFrame and GossipFrame.Update and GossipFrame:IsShown() then
        pcall(function()
            GossipFrame:Update()
        end)
    end
    if DUIQuestFrame and DUIQuestFrame:IsShown() then
        pcall(function()
            DecorateDialogueTitle(DUIQuestFrame)
            DecorateDialogueQuestButtons(DUIQuestFrame)
        end)
    end
    if QuestFrameGreetingPanel and QuestFrameGreetingPanel:IsShown() then
        PrefixGreetingButtons()
    end
    if QuestFrameProgressPanel and QuestFrameProgressPanel:IsShown() then
        PrefixProgressTitle()
    end
    if QuestInfoTitleHeader and QuestInfoTitleHeader:IsVisible() then
        pcall(PrefixQuestInfoTitle)
    end
    if QuestLogPopupDetailFrame and QuestLogPopupDetailFrame:IsShown() then
        pcall(PrefixQuestLogPopupTitle)
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

WrapDialogue()
WrapQuestLog()
WrapQuestInfo()
WrapQuestLogPopup()
HookMapTooltips()
EventUtil.ContinueOnAddOnLoaded("Blizzard_UIPanels_Game", function()
    WrapQuestLog()
    WrapQuestInfo()
    WrapQuestLogPopup()
    WrapGossip()
    WrapGreeting()
    WrapProgress()
    HookMapTooltips()
end)
EventUtil.ContinueOnAddOnLoaded("Blizzard_SharedMapDataProviders", HookMapTooltips)
EventUtil.ContinueOnAddOnLoaded("Blizzard_ObjectiveTracker", WrapTracker)
EventUtil.ContinueOnAddOnLoaded("DialogueUI", WrapDialogue)

AIW.OnFilterChanged(AIW.RefreshTitles)
