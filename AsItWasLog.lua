local _, AIW = ...

-- Abandon only quests newer than the selected filter max (8.1 when 8.0.1 is selected).
-- Older than min stay in the log unless the player turns that protection off.

local function CollectAbandonList()
    local filter = AIW.GetActiveFilter()
    if not filter or filter.kind == "off" then
        return {}
    end
    local keepOlder = AsItWasDB.doNotAbandonOlder ~= false
    local list = {}
    local entries = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
    for index = 1, entries do
        local info = C_QuestLog.GetInfo(index)
        if info and not info.isHeader and info.questID then
            local drop = false
            if keepOlder then
                drop = AIW.IsNewerThanFilter(info.questID)
            else
                drop = not AIW.IsInRange(info.questID)
            end
            if drop and C_QuestLog.CanAbandonQuest and C_QuestLog.CanAbandonQuest(info.questID) then
                list[#list + 1] = {
                    questID = info.questID,
                    title = info.title or ("#" .. info.questID),
                }
            end
        end
    end
    return list
end

local function AbandonQuestID(questID)
    C_QuestLog.SetSelectedQuest(questID)
    if C_QuestLog.SetAbandonQuest then
        C_QuestLog.SetAbandonQuest()
    end
    C_QuestLog.AbandonQuest()
end

function AIW.RunMassAbandon()
    local list = CollectAbandonList()
    for _, row in ipairs(list) do
        AbandonQuestID(row.questID)
    end
    local keepOlder = AsItWasDB.doNotAbandonOlder ~= false
    if keepOlder then
        AIW.Print(string.format("Abandoned %d quest(s) newer than %s.", #list, AIW.FormatPatchCode(AIW.GetActiveFilter().max)))
    else
        AIW.Print(string.format("Abandoned %d quest(s) outside this era.", #list))
    end
end

function AIW.ConfirmMassAbandon()
    if not AIW.IsEnabled() then
        AIW.Print("Pick a patch first. Nothing was abandoned.")
        return
    end
    local list = CollectAbandonList()
    if #list == 0 then
        AIW.Print("No newer-than-filter quests to abandon.")
        return
    end
    StaticPopup_Show("ASITWAS_MASS_ABANDON", #list)
end

StaticPopupDialogs["ASITWAS_MASS_ABANDON"] = {
    text = "Abandon %s quest(s) that do not belong to this era?",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        AIW.RunMassAbandon()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local logFrame = CreateFrame("Frame")
logFrame:RegisterEvent("QUEST_ACCEPTED")
logFrame:SetScript("OnEvent", function(_, _, arg1, arg2)
    local questID = arg2 or arg1
    if type(questID) ~= "number" then
        return
    end
    if AIW.IsInRange(questID) then
        return
    end
    local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID) or ""
    AIW.Print(AIW.MarkTitle(questID, title ~= "" and title or ("Quest " .. questID)))
end)
