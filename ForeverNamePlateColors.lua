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
        if FNC.RebuildQuestCache then FNC:RebuildQuestCache() end
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
mainFrame:RegisterEvent("UNIT_HEALTH")
mainFrame:RegisterEvent("UNIT_COMBAT")
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
        if FNC.RebuildQuestCache then FNC:RebuildQuestCache() end
        FNC:SyncAllCVars()
        FNC:UpdateConfigPanelUI()
        print(FormatChat("v" .. addonVersion .. " loaded successfully. Type |cFFFFFFFF/fnc|r to open options."))
    elseif event == "PLAYER_ENTERING_WORLD" then
        if FNC.RebuildQuestCache then FNC:RebuildQuestCache() end
        FNC:SyncAllCVars()
        FNC:RefreshAllPlates()
        if QuestieLoader and FNC.IsQuestieReady and not FNC:IsQuestieReady() then
            local attempts = 0
            local function PollQuestieInit()
                attempts = attempts + 1
                if FNC.IsQuestieReady and FNC:IsQuestieReady() then
                    if FNC.RebuildQuestCache then FNC:RebuildQuestCache() end
                    FNC:RefreshAllPlates()
                elseif attempts < 20 then
                    C_Timer.After(0.5, PollQuestieInit)
                end
            end
            C_Timer.After(0.5, PollQuestieInit)
        end
    elseif event == "NAME_PLATE_UNIT_ADDED"
        or event == "UNIT_NAME_UPDATE"
        or event == "UNIT_LEVEL"
        or event == "UNIT_FACTION"
        or event == "UNIT_FLAGS"
        or event == "UNIT_HEALTH"
        or event == "UNIT_COMBAT"
        or event == "UNIT_TARGET"
        or event == "UNIT_THREAT_LIST_UPDATE" then
        local unit = arg1
        if type(unit) == "string" then
            if unit:match("^nameplate%d+$") then
                local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
                if plate then
                    local uf = plate.UnitFrame or plate.unitFrame
                    if uf and not uf:IsForbidden() then
                        if FNC.QueueUnitFrameUpdate then
                            FNC:QueueUnitFrameUpdate(uf, unit)
                        else
                            FNC:UpdateUnitFrame(uf, unit)
                        end
                    end
                end
            elseif (event == "UNIT_TARGET" or event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_COMBAT")
                and (unit == "player" or unit == "pet" or unit:match("^party%d+$") or unit:match("^raid%d+$") or unit:match("^partypet%d+$") or unit:match("^raidpet%d+$")) then
                local targetUnit = unit .. "target"
                if UnitExists and UnitExists(targetUnit) and C_NamePlate and C_NamePlate.GetNamePlates then
                    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
                        local uf = plate.UnitFrame or plate.unitFrame
                        if uf and not uf:IsForbidden() then
                            local plateUnit = uf.displayedUnit or uf.unit
                            if type(plateUnit) == "string" and plateUnit:match("^nameplate%d+$") and UnitIsUnit(plateUnit, targetUnit) then
                                if FNC.QueueUnitFrameUpdate then
                                    FNC:QueueUnitFrameUpdate(uf, plateUnit)
                                else
                                    FNC:UpdateUnitFrame(uf, plateUnit)
                                end
                                break
                            end
                        end
                    end
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
    elseif msg == "debug" then
        local unit = UnitExists("target") and "target" or (UnitExists("mouseover") and "mouseover" or nil)
        if not unit then
            print(FormatChat("Target or mouseover a quest mob first, then run |cFFFFFFFF/fnc debug|r."))
        else
            local uname = UnitName(unit) or "?"
            local canAtk = UnitCanAttack and UnitCanAttack("player", unit) or false
            local isEn = UnitIsEnemy and UnitIsEnemy("player", unit) or false
            local isTap = UnitIsTapDenied and UnitIsTapDenied(unit) or false
            local isTag = FNC.IsTaggedByPlayerOrParty and FNC:IsTaggedByPlayerOrParty(unit) or false
            local isQuest = FNC.IsActiveQuestUnit and FNC:IsActiveQuestUnit(unit, nil) or false
            local matchedKey = "NONE"
            local isPlayer = UnitIsPlayer(unit)
            local isSub = isPlayer and FNC.IsInMySubgroup and FNC.IsInMySubgroup(unit) or false
            local isRaid = isPlayer and (UnitInRaid(unit) ~= nil) or false
            for _, cfg in ipairs(FNC.CATEGORY_CONFIG or {}) do
                local cat = ForeverNamePlateColorsDB and ForeverNamePlateColorsDB.categories and ForeverNamePlateColorsDB.categories[cfg.key]
                if cat and cat.enabled and cfg.match(unit, isSub, isRaid, isPlayer, isEn, canAtk, nil) then
                    matchedKey = cfg.key
                    break
                end
            end
            print(FormatChat(string.format("Unit=%s Name=%s canAtk=%s isEnemy=%s tapDenied=%s tagged=%s isQuest=%s match=%s",
                tostring(unit), tostring(uname), tostring(canAtk), tostring(isEn), tostring(isTap), tostring(isTag), tostring(isQuest), tostring(matchedKey))))
            if FNC.DumpQuestDebug then
                FNC:DumpQuestDebug(unit)
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
