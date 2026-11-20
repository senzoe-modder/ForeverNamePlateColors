--------------------------------------------------------------------------------
-- ForeverNamePlateColors.lua
-- Main Entry Point, Event Router, and Slash Commands
--------------------------------------------------------------------------------

local addonName, FNC = ...
local mainFrame = CreateFrame("Frame", "ForeverNamePlateColorsMainFrame", UIParent)
FNC.mainFrame = mainFrame

-- Register Core, Group, and Quest Events
mainFrame:RegisterEvent("ADDON_LOADED")
mainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
mainFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
mainFrame:RegisterEvent("UNIT_NAME_UPDATE")
mainFrame:RegisterEvent("UNIT_LEVEL")
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
        print("|cFF00FFCCForeverNamePlateColors|r v1.4.0 loaded successfully. Type |cFFFFFFFF/fnc|r to open options.")
    elseif event == "PLAYER_ENTERING_WORLD" then
        FNC:RebuildQuestCache()
        FNC:SyncAllCVars()
        FNC:RefreshAllPlates()
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL" then
        local unit = arg1
        if unit then
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
        FNC:RebuildQuestCache()
        FNC:RefreshAllPlates()
    elseif event == "UNIT_QUEST_LOG_CHANGED" then
        if not arg1 or arg1 == "player" then
            FNC:RebuildQuestCache()
            FNC:RefreshAllPlates()
        end
    end
end)

-- Slash Command Handler
SlashCmdList["FOREVERNAMEPLATECOLORS"] = function(msg)
    msg = string.lower(strtrim(msg or ""))
    if msg == "toggle" then
        ForeverNamePlateColorsDB.enabled = not ForeverNamePlateColorsDB.enabled
        print("|cFF00FFCCForeverNamePlateColors|r Enabled: " .. tostring(ForeverNamePlateColorsDB.enabled))
        if ForeverNamePlateColorsDB.enabled then
            FNC:RefreshAllPlates()
        else
            FNC:SyncAllCVars()
            FNC:ResetAllPlates()
        end
        FNC:UpdateConfigPanelUI()
    else
        if Settings and Settings.OpenToCategory and FNC.settingsCategory then
            Settings.OpenToCategory(FNC.settingsCategory.ID)
        elseif FNC.configFrame then
            InterfaceOptionsFrame_OpenToCategory(FNC.configFrame)
        end
    end
end
SLASH_FOREVERNAMEPLATECOLORS1 = "/fnc"