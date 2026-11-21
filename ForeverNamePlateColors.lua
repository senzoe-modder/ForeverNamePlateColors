--------------------------------------------------------------------------------
-- ForeverNamePlateColors.lua
-- Main Entry Point, Error Tracker, Event Router, and Slash Commands
--------------------------------------------------------------------------------

local addonName, FNC = ...

local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local addonVersion = (GetAddOnMetadata and GetAddOnMetadata(addonName, "Version")) or "dev"

local function GetChatTitle()
    return FNC.GetChatTitle and FNC.GetChatTitle() or (FNC.RAINBOW_TITLE or "|cFF00FFCCForeverNamePlateColors|r")
end

local function FormatChat(msg)
    return FNC.FormatChat and FNC.FormatChat(msg) or (GetChatTitle() .. " " .. tostring(msg or ""))
end

-- Error Tracker: Always logs FNC errors to SavedVariables on disk; prints to chat if enabled in settings
local prevErrorHandler = geterrorhandler()
seterrorhandler(function(err)
    local msg = tostring(err)
    if msg:find("ForeverNamePlateColors", 1, true) then
        ForeverNamePlateColorsDB = ForeverNamePlateColorsDB or {}
        if type(ForeverNamePlateColorsDB.errorLog) ~= "table" then
            ForeverNamePlateColorsDB.errorLog = {}
        end

        local stack = debugstack(2, 8, 8) or ""
        local timestamp = date and date("%Y-%m-%d %H:%M:%S") or "Unknown Time"
        local entry = string.format("[%s] %s\n%s", timestamp, msg, stack)
        local log = ForeverNamePlateColorsDB.errorLog

        if log[#log] ~= entry then
            log[#log + 1] = entry
            if #log > 25 then
                table.remove(log, 1)
            end
        end

        if ForeverNamePlateColorsDB.showErrors then
            print("[" .. GetChatTitle() .. " |cFFFF5555Error|r] " .. msg)
        end
    end

    if prevErrorHandler then
        return prevErrorHandler(err)
    end
end)

local mainFrame = CreateFrame("Frame", "ForeverNamePlateColorsMainFrame", UIParent)
FNC.mainFrame = mainFrame

-- Debounced Quest Log Refresh (coalesces burst QUEST_LOG_UPDATE events within the same frame)
local questRefreshQueued = false
local function QueueQuestRefresh()
    if questRefreshQueued then return end
    questRefreshQueued = true
    C_Timer.After(0, function()
        questRefreshQueued = false
        FNC:RebuildQuestCache()
        FNC:RefreshAllPlates()
    end)
end

-- Register Core, Group, Combat/Threat, and Quest Events
mainFrame:RegisterEvent("ADDON_LOADED")
mainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
mainFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
mainFrame:RegisterEvent("UNIT_NAME_UPDATE")
mainFrame:RegisterEvent("UNIT_LEVEL")
mainFrame:RegisterEvent("UNIT_FACTION")
mainFrame:RegisterEvent("UNIT_FLAGS")
mainFrame:RegisterEvent("UNIT_TARGET")
mainFrame:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
mainFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
mainFrame:RegisterEvent("QUEST_LOG_UPDATE")
mainFrame:RegisterEvent("QUEST_ACCEPTED")
mainFrame:RegisterEvent("QUEST_REMOVED")
mainFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")

mainFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        FNC.MigrateDB(ForeverNamePlateColorsDB)
        FNC.EnsureDefaults(ForeverNamePlateColorsDB)
        FNC:RebuildQuestCache()
        FNC:SyncAllCVars()
        FNC:UpdateConfigPanelUI()
        print(FormatChat("v" .. addonVersion .. " loaded successfully. Type |cFFFFFFFF/fnc|r to open options."))
    elseif event == "PLAYER_ENTERING_WORLD" then
        FNC:RebuildQuestCache()
        FNC:SyncAllCVars()
        FNC:RefreshAllPlates()
    elseif event == "NAME_PLATE_UNIT_ADDED"
        or event == "UNIT_NAME_UPDATE"
        or event == "UNIT_LEVEL"
        or event == "UNIT_FACTION"
        or event == "UNIT_FLAGS"
        or event == "UNIT_TARGET"
        or event == "UNIT_THREAT_LIST_UPDATE" then
        local unit = arg1
        if type(unit) == "string" and unit:match("^nameplate%d+$") then
            local plate = C_NamePlate.GetNamePlateForUnit(unit)
            if plate then
                local uf = plate.UnitFrame or plate.unitFrame
                if uf and not uf:IsForbidden() then
                    FNC:UpdateUnitFrame(uf, unit)
                end
            end
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        FNC:RefreshAllPlates()
    elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" then
        QueueQuestRefresh()
    elseif event == "UNIT_QUEST_LOG_CHANGED" then
        if not arg1 or arg1 == "player" then
            QueueQuestRefresh()
        end
    end
end)

-- Slash Command Handler (/fnc)
SlashCmdList["FOREVERNAMEPLATECOLORS"] = function(msg)
    msg = string.lower(strtrim(msg or ""))
    if msg == "toggle" then
        ForeverNamePlateColorsDB.enabled = not ForeverNamePlateColorsDB.enabled
        print(FormatChat("Enabled: " .. tostring(ForeverNamePlateColorsDB.enabled)))
        if ForeverNamePlateColorsDB.enabled then
            FNC:RefreshAllPlates()
        else
            FNC:SyncAllCVars()
            FNC:ResetAllPlates()
        end
        FNC:UpdateConfigPanelUI()
    elseif msg == "errors" then
        local log = ForeverNamePlateColorsDB and ForeverNamePlateColorsDB.errorLog
        if not log or #log == 0 then
            print(FormatChat("No recorded errors."))
        else
            print(FormatChat("Recorded errors (" .. #log .. "):"))
            for i, entry in ipairs(log) do
                print("|cFFFF5555[" .. i .. "]|r " .. entry)
            end
        end
    elseif msg == "clearerrors" then
        if ForeverNamePlateColorsDB then
            ForeverNamePlateColorsDB.errorLog = {}
        end
        print(FormatChat("Error log cleared."))
    else
        if Settings and Settings.OpenToCategory and FNC.settingsCategory then
            Settings.OpenToCategory(FNC.settingsCategory.ID)
        elseif FNC.configFrame then
            InterfaceOptionsFrame_OpenToCategory(FNC.configFrame)
        end
    end
end
SLASH_FOREVERNAMEPLATECOLORS1 = "/fnc"
