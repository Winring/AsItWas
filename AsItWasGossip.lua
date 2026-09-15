local _, AIW = ...

local MARK = "^%[%d+%.%d+%.%d+%] "

local function PrefixButton(button, questID, title)
    if not button or not questID then
        return
    end
    if AIW.IsInRange(questID) then
        return
    end
    local current = button:GetText()
    if current and current:find(MARK) then
        return
    end
    local marked = AIW.MarkTitle(questID, title)
    if button.SetTextAndResize then
        button:SetTextAndResize(marked)
    else
        button:SetText(marked)
    end
end

local function HookGossip()
    if GossipSharedAvailableQuestButtonMixin then
        hooksecurefunc(GossipSharedAvailableQuestButtonMixin, "Setup", function(self, questInfo)
            if questInfo then
                PrefixButton(self, questInfo.questID, questInfo.title)
            end
        end)
    end
    if GossipSharedActiveQuestButtonMixin then
        hooksecurefunc(GossipSharedActiveQuestButtonMixin, "Setup", function(self, questInfo)
            if questInfo then
                PrefixButton(self, questInfo.questID, questInfo.title)
            end
        end)
    end
end

local function HookGreeting()
    if not QuestFrameGreetingPanel_OnShow then
        return
    end
    hooksecurefunc("QuestFrameGreetingPanel_OnShow", function()
        if not QuestFrameGreetingPanel or not QuestFrameGreetingPanel.titleButtonPool then
            return
        end
        for button in QuestFrameGreetingPanel.titleButtonPool:EnumerateActive() do
            local questID
            if button.isActive == 1 then
                questID = GetActiveQuestID(button:GetID())
            else
                local info = { GetAvailableQuestInfo(button:GetID()) }
                questID = info[5]
            end
            if questID then
                PrefixButton(button, questID, button:GetText())
            end
        end
    end)
end

local gossipLoader = CreateFrame("Frame")
gossipLoader:RegisterEvent("PLAYER_LOGIN")
gossipLoader:SetScript("OnEvent", function()
    HookGossip()
    HookGreeting()
end)
