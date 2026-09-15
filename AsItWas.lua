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
        local name = EXPANSION_NAME[major] or ("Expansion " .. major)
        local first = group[1]
        local last = group[#group]
        if major == 7 then
            options[#options + 1] = {
                id = first.patch,
                kind = "baseline",
                label = name .. " and older",
                min = first.code,
                max = first.code,
                patch = first.patch,
            }
        else
            options[#options + 1] = {
                id = tostring(major),
                kind = "expansion",
                label = name .. " (whole)",
                min = first.code,
                max = last.code,
                patch = last.patch,
            }
            for _, row in ipairs(group) do
                options[#options + 1] = {
                    id = row.patch,
                    kind = "patch",
                    label = name .. " " .. row.patch,
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

-- Unknown IDs stay unmarked. Filter off marks nothing.
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

function AIW.MarkTitle(questID, title)
    title = title or ""
    if AIW.IsInRange(questID) then
        return title
    end
    local patch = AIW.QuestPatch(questID)
    return string.format("[%s] %s", AIW.FormatPatchCode(patch), title)
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

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        AIW.EnsureDB()
        AIW.GetFilterOptions()
    elseif event == "PLAYER_LOGIN" then
        AIW.EnsureDB()
        if not AsItWasDB.seenSetup then
            AIW.ShowFirstRun()
        end
    end
end)

SLASH_ASITWAS1 = "/asitwas"
SLASH_ASITWAS2 = "/aiw"
SlashCmdList.ASITWAS = function(msg)
    msg = string.lower(strtrim(msg or ""))
    if msg == "options" or msg == "" then
        AIW.OpenOptions()
    elseif msg == "abandon" or msg == "clean" then
        AIW.ConfirmMassAbandon()
    else
        AIW.Print("/aiw options  /aiw abandon")
    end
end
