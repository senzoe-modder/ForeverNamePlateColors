--------------------------------------------------------------------------------
-- Resolvers.lua
-- Subgroup Checks, Minion Owner Detection, Quest Log Cache, & Tooltip Scanner
--------------------------------------------------------------------------------

local addonName, FNC = ...

-- Active Quest Log Cache (Blizzard API fallback when Questie is not installed)
local activeQuestTitles = {}
local incompleteObjectiveTargets = {}
local turnInTargets = {}
local questTextCorpus = ""

-- Reusable scratch table for tooltip lines (zero per-call table allocation)
local tooltipLines = {}

-- Blizzard Classic Era Quest Indicator Texture FileDataIDs
local QUEST_TEXTURE_FILE_IDS = {
    [132048] = true, -- AvailableQuestIcon (!)
    [132049] = true, -- ActiveQuestIcon (?)
    [132050] = true, -- ActiveLegendaryQuestIcon
    [365195] = true, -- DailyQuestIcon
    [368362] = true, -- DailyActiveQuestIcon
    [368577] = true, -- Quest objective badge
    [136460] = true, -- Quest icon variant
}

local function IsSafeString(val)
    if type(val) ~= "string" or val == "" then return false end
    if issecretvalue and issecretvalue(val) then return false end
    return true
end

local function CleanTooltipText(text)
    if not IsSafeString(text) then return "" end
    local ok, cleaned = pcall(function()
        return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
    end)
    return (ok and type(cleaned) == "string") and cleaned or ""
end

local function GetNpcIDFromUnit(unit)
    if not IsSafeString(unit) or not UnitGUID then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or not IsSafeString(guid) then return nil end
    local unitType, _, _, _, _, npcIDStr = strsplit("-", guid)
    if (unitType == "Creature" or unitType == "Vehicle") and npcIDStr then
        return tonumber(npcIDStr)
    end
    return nil
end

local function AddTurnInNPC(rawTarget)
    if not IsSafeString(rawTarget) then return end
    local npc = rawTarget:match("^([^%.%!%?,\r\n]+)") or rawTarget
    npc = npc:lower()
    npc = npc:gsub(":%s*%d+%s*/%s*%d+$", "")
    npc = npc:gsub("%s+in%s+[%a%s'%-]+$", "")
    npc = npc:gsub("%s+at%s+[%a%s'%-]+$", "")
    npc = npc:gsub("%s+near%s+[%a%s'%-]+$", "")
    npc = npc:gsub("%s+inside%s+[%a%s'%-]+$", "")
    npc = npc:gsub("%s+outside%s+[%a%s'%-]+$", "")
    npc = npc:gsub("%s+on%s+[%a%s'%-]+$", "")
    npc = npc:gsub("%s+to%s+claim.*$", "")
    npc = npc:gsub("%s+to%s+complete.*$", "")
    npc = npc:gsub("%s+to%s+turn.*$", "")
    npc = npc:gsub("%s+when%s+.*$", "")
    npc = npc:gsub("%s+once%s+.*$", "")
    npc = npc:match("^%s*(.-)%s*$")
    if npc and npc ~= "" and #npc >= 3 then
        turnInTargets[npc] = true
    end
end

local function ScanTextForTurnInNPCs(text)
    if not IsSafeString(text) then return end
    local lower = CleanTooltipText(text):lower()
    if lower == "" then return end

    local patterns = {
        "speak with%s+([^%.%!%?,\r\n]+)",
        "speak to%s+([^%.%!%?,\r\n]+)",
        "talk to%s+([^%.%!%?,\r\n]+)",
        "talk with%s+([^%.%!%?,\r\n]+)",
        "return to%s+([^%.%!%?,\r\n]+)",
        "report to%s+([^%.%!%?,\r\n]+)",
        "see%s+([%a'%-%s]+)%s+in%s+",
        "see%s+([%a'%-%s]+)%s+at%s+",
        "find%s+([%a'%-%s]+)%s+in%s+",
        "find%s+([%a'%-%s]+)%s+at%s+",
        "deliver%s+.-%s+to%s+([^%.%!%?,\r\n]+)",
        "bring%s+.-%s+to%s+([^%.%!%?,\r\n]+)",
        "take%s+.-%s+to%s+([^%.%!%?,\r\n]+)",
        "give%s+.-%s+to%s+([^%.%!%?,\r\n]+)",
    }

    for _, pat in ipairs(patterns) do
        for match in lower:gmatch(pat) do
            AddTurnInNPC(match)
        end
    end
end

-- Check Questie's live runtime tooltip registry by NPC ID ("m_<npcID>") when Questie is installed
local cachedQuestieTooltips = nil
local function IsMatchedInQuestieLiveTooltips(npcID)
    if not npcID or not QuestieLoader or not QuestieLoader.ImportModule then return false end
    local ok, found = pcall(function()
        if not cachedQuestieTooltips then
            cachedQuestieTooltips = QuestieLoader:ImportModule("QuestieTooltips")
        end
        if not cachedQuestieTooltips or type(cachedQuestieTooltips.lookupByKey) ~= "table" then
            return false
        end
        local entries = cachedQuestieTooltips.lookupByKey["m_" .. tostring(npcID)]
        return type(entries) == "table" and next(entries) ~= nil
    end)
    return ok and found == true
end

function FNC:RebuildQuestCache()
    wipe(activeQuestTitles)
    wipe(incompleteObjectiveTargets)
    wipe(turnInTargets)
    questTextCorpus = ""

    if not GetNumQuestLogEntries or not GetQuestLogTitle then return end

    local corpusParts = {}
    local prevSelection = GetQuestLogSelection and GetQuestLogSelection() or 0
    local numEntries = GetNumQuestLogEntries() or 0

    for i = 1, numEntries do
        local title, _, _, isHeader, _, isComplete = GetQuestLogTitle(i)
        if IsSafeString(title) and not isHeader then
            local cleanTitle = CleanTooltipText(title):gsub("^%[.-%]%s*", ""):gsub("%s*%(complete%)%s*$", ""):lower()
            if cleanTitle ~= "" then
                activeQuestTitles[cleanTitle] = true
                table.insert(corpusParts, cleanTitle)
            end

            local numObjectives = (GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i)) or 0
            if GetQuestLogLeaderBoard then
                for j = 1, numObjectives do
                    local desc, _, isDone = GetQuestLogLeaderBoard(j, i)
                    if IsSafeString(desc) then
                        local cleanDesc = CleanTooltipText(desc)
                        table.insert(corpusParts, cleanDesc:lower())

                        if not isDone and isComplete ~= 1 then
                            local target = cleanDesc:match("^([^:]+):%s*%d+%s*/%s*%d+")
                            if target then
                                target = target:gsub("%s+slain$", ""):gsub("%s+killed$", ""):gsub("%s+collected$", ""):match("^%s*(.-)%s*$"):lower()
                                if target ~= "" then
                                    incompleteObjectiveTargets[target] = true
                                end
                            end
                        end

                        ScanTextForTurnInNPCs(cleanDesc)
                    end
                end
            end

            if SelectQuestLogEntry then
                SelectQuestLogEntry(i)
                if GetQuestLogQuestText then
                    local questDescription, questObjectives = GetQuestLogQuestText()
                    if IsSafeString(questObjectives) then
                        table.insert(corpusParts, CleanTooltipText(questObjectives):lower())
                        ScanTextForTurnInNPCs(questObjectives)
                    end
                    if IsSafeString(questDescription) then
                        table.insert(corpusParts, CleanTooltipText(questDescription):lower())
                        ScanTextForTurnInNPCs(questDescription)
                    end
                end
                if GetQuestLogCompletionText then
                    local completionText = GetQuestLogCompletionText()
                    if IsSafeString(completionText) then
                        table.insert(corpusParts, CleanTooltipText(completionText):lower())
                        ScanTextForTurnInNPCs(completionText)
                    end
                end
            end
        end
    end

    questTextCorpus = " " .. table.concat(corpusParts, " | ") .. " "

    if prevSelection and prevSelection > 0 and SelectQuestLogEntry then
        SelectQuestLogEntry(prevSelection)
    end
end

-- Preallocated unit token tables for zero-allocation threat/target lookups
local PARTY_UNITS = { "party1", "party2", "party3", "party4" }
local PARTY_PET_UNITS = { "partypet1", "partypet2", "partypet3", "partypet4" }
local RAID_UNITS = {}
local RAID_PET_UNITS = {}
for i = 1, 40 do
    RAID_UNITS[i] = "raid" .. i
    RAID_PET_UNITS[i] = "raidpet" .. i
end

-- Zero-allocation check whether an attackable mob is tagged by the player or their party/raid
local function CheckTaggedByPlayerOrPartyInternal(unit)
    if not IsSafeString(unit) or UnitIsPlayer(unit) then return false end
    if UnitPlayerControlled(unit) or (UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(unit)) then
        return false
    end
    if not UnitCanAttack("player", unit) then
        return false
    end
    if UnitIsDead and UnitIsDead(unit) then
        return false
    end

    if UnitIsTapDenied and UnitIsTapDenied(unit) then
        return false
    end

    local mobTarget = unit .. "target"
    local hasMobTarget = UnitExists and UnitExists(mobTarget)

    if UnitThreatSituation and UnitThreatSituation("player", unit) ~= nil then
        return true
    end
    if hasMobTarget and UnitIsUnit(mobTarget, "player") then
        return true
    end
    if UnitExists("pet") then
        if UnitThreatSituation and UnitThreatSituation("pet", unit) ~= nil then
            return true
        end
        if hasMobTarget and UnitIsUnit(mobTarget, "pet") then
            return true
        end
    end

    if IsInRaid() then
        local numMembers = GetNumGroupMembers()
        for i = 1, numMembers do
            local rUnit = RAID_UNITS[i]
            if rUnit and UnitExists(rUnit) then
                if UnitThreatSituation and UnitThreatSituation(rUnit, unit) ~= nil then
                    return true
                end
                if hasMobTarget and UnitIsUnit(mobTarget, rUnit) then
                    return true
                end
            end
            local rPet = RAID_PET_UNITS[i]
            if rPet and UnitExists(rPet) then
                if UnitThreatSituation and UnitThreatSituation(rPet, unit) ~= nil then
                    return true
                end
                if hasMobTarget and UnitIsUnit(mobTarget, rPet) then
                    return true
                end
            end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local pUnit = PARTY_UNITS[i]
            if UnitExists(pUnit) then
                if UnitThreatSituation and UnitThreatSituation(pUnit, unit) ~= nil then
                    return true
                end
                if hasMobTarget and UnitIsUnit(mobTarget, pUnit) then
                    return true
                end
            end
            local pPet = PARTY_PET_UNITS[i]
            if UnitExists(pPet) then
                if UnitThreatSituation and UnitThreatSituation(pPet, unit) ~= nil then
                    return true
                end
                if hasMobTarget and UnitIsUnit(mobTarget, pPet) then
                    return true
                end
            end
        end
    end

    return false
end

function FNC:IsTaggedByPlayerOrParty(unit)
    local ok, result = pcall(CheckTaggedByPlayerOrPartyInternal, unit)
    return ok and result == true
end

-- Hidden Tooltip Scraper for NPC Role/Job Subtitles, Minion Owner Tags, and Quest Objectives
local scanTooltip = CreateFrame("GameTooltip", "FNCScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function GetUnitTooltipLines(unit)
    wipe(tooltipLines)
    local count = 0

    if not IsSafeString(unit) then
        return tooltipLines, 0
    end

    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
        if ok and type(data) == "table" and type(data.lines) == "table" then
            for i = 2, #data.lines do
                local line = data.lines[i]
                if type(line) == "table" and IsSafeString(line.leftText) then
                    local cleaned = CleanTooltipText(line.leftText)
                    if cleaned ~= "" then
                        count = count + 1
                        tooltipLines[count] = cleaned
                    end
                end
            end
        end
    end

    if count == 0 then
        pcall(function()
            scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
            scanTooltip:ClearLines()
            scanTooltip:SetUnit(unit)
            local numLines = scanTooltip:NumLines() or 0
            for i = 2, numLines do
                local fs = _G["FNCScanTooltipTextLeft" .. i]
                if fs then
                    local txt = fs:GetText()
                    if IsSafeString(txt) then
                        local cleaned = CleanTooltipText(txt)
                        if cleaned ~= "" then
                            count = count + 1
                            tooltipLines[count] = cleaned
                        end
                    end
                end
            end
        end)
    end

    return tooltipLines, count
end

local function IsQuestTextureOrAtlas(region)
    if not region or (region.IsForbidden and region:IsForbidden()) then return false end
    if not region:IsObjectType("Texture") or not region:IsShown() then return false end

    local parentKey = region.GetParentKey and region:GetParentKey() or ""
    if type(parentKey) == "string" and parentKey:lower():find("quest") then
        return true
    end

    local atlas = region.GetAtlas and region:GetAtlas()
    if IsSafeString(atlas) and atlas:lower():find("quest") then
        return true
    end

    local tex = region.GetTexture and region:GetTexture()
    if type(tex) == "number" and QUEST_TEXTURE_FILE_IDS[tex] then
        return true
    elseif IsSafeString(tex) and (tex:lower():find("quest") or tex:lower():find("availablequest") or tex:lower():find("activequest")) then
        return true
    end

    return false
end

local function ScanRegionsForQuestIcon(n, ...)
    for i = 1, n do
        local region = select(i, ...)
        if IsQuestTextureOrAtlas(region) then
            return true
        end
    end
    return false
end

local function ScanChildrenForQuestIcon(n, ...)
    for i = 1, n do
        local child = select(i, ...)
        if child and not (child.IsForbidden and child:IsForbidden()) and child:IsShown() then
            local parentKey = child.GetParentKey and child:GetParentKey() or ""
            if type(parentKey) == "string" and parentKey:lower():find("quest") then
                return true
            end
            local childName = child.GetName and child:GetName() or ""
            if type(childName) == "string" and childName:lower():find("quest") then
                return true
            end
            if ScanRegionsForQuestIcon(select("#", child:GetRegions()), child:GetRegions()) then
                return true
            end
        end
    end
    return false
end

local function HasVisibleQuestBadge(uf)
    if not uf or (uf.IsForbidden and uf:IsForbidden()) then return false end
    if ScanRegionsForQuestIcon(select("#", uf:GetRegions()), uf:GetRegions()) then
        return true
    end
    if ScanChildrenForQuestIcon(select("#", uf:GetChildren()), uf:GetChildren()) then
        return true
    end
    local parent = uf:GetParent()
    if parent and not (parent.IsForbidden and parent:IsForbidden()) then
        if ScanRegionsForQuestIcon(select("#", parent:GetRegions()), parent:GetRegions()) then
            return true
        end
        if ScanChildrenForQuestIcon(select("#", parent:GetChildren()), parent:GetChildren()) then
            return true
        end
    end
    return false
end

local function MatchesTurnInNPCName(lowerName)
    if turnInTargets[lowerName] then
        return true
    end
    for cachedNPC in pairs(turnInTargets) do
        if #cachedNPC >= 4 and lowerName:find(cachedNPC, 1, true) then
            return true
        end
    end
    if lowerName:find("%s") and #lowerName >= 6 and questTextCorpus:find(lowerName, 1, true) then
        return true
    end
    return false
end

local function CheckActiveQuestUnitInternal(unit, uf)
    if not IsSafeString(unit) or UnitIsPlayer(unit) then return false end
    if UnitPlayerControlled(unit) or (UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(unit)) then
        return false
    end

    -- If another player/party has tagged this mob, revert to Blizzard default tapped color
    if UnitCanAttack("player", unit) and UnitIsTapDenied and UnitIsTapDenied(unit) then
        return false
    end

    -- 1. Direct Classic Era Quest Boss / Visible Quest Badge checks
    if UnitIsQuestBoss and UnitIsQuestBoss(unit) then
        return true
    end
    if HasVisibleQuestBadge(uf) then
        return true
    end

    -- 2. Questie live NPC ID lookup (covers turn-in '?' NPCs and active quest mobs via GUID npcID)
    local npcID = GetNpcIDFromUnit(unit)
    if npcID and IsMatchedInQuestieLiveTooltips(npcID) then
        return true
    end

    -- 3. Standalone fallback: match unit name against cached quest objective targets & turn-in NPCs
    local unitName = UnitName(unit)
    if IsSafeString(unitName) then
        local lowerName = unitName:lower()
        if incompleteObjectiveTargets[lowerName] or MatchesTurnInNPCName(lowerName) then
            return true
        end
    end

    -- 4. Scan tooltip lines 2..NumLines() for active/completed quest titles or incomplete objective counters
    local lines, count = GetUnitTooltipLines(unit)
    for i = 1, count do
        local lineText = lines[i]
        if IsSafeString(lineText) then
            local lowerLine = lineText:gsub("%s*%(complete%)%s*$", ""):lower()
            if activeQuestTitles[lowerLine] then
                return true
            end

            if not lowerLine:find("^level") and not lowerLine:find("^lvl") then
                local curStr, reqStr = lineText:match("(%d+)%s*/%s*(%d+)")
                if curStr and reqStr then
                    local curNum, reqNum = tonumber(curStr), tonumber(reqStr)
                    if curNum and reqNum and reqNum > 0 and curNum < reqNum then
                        return true
                    end
                end
            end
        end
    end

    return false
end

function FNC:IsActiveQuestUnit(unit, uf)
    local ok, result = pcall(CheckActiveQuestUnitInternal, unit, uf)
    return ok and result == true
end

local function GetNPCSubtitleInternal(unit)
    if not IsSafeString(unit) or UnitIsPlayer(unit) then return nil end

    local lines, count = GetUnitTooltipLines(unit)
    local textLine2 = (count >= 1) and lines[1] or nil

    if not IsSafeString(textLine2) then return nil end
    if textLine2 == "Unknown" or (UNKNOWNOBJECT and textLine2 == UNKNOWNOBJECT) then
        return nil
    end

    local lower = textLine2:lower()
    if lower:find("^level") or lower:find("^lvl") or lower:find("^%?%?") or textLine2:match("^%d") or lower:find("corpse") then
        return nil
    end

    if textLine2 == "Alliance" or textLine2 == "Horde" or textLine2 == "Neutral" then
        return nil
    end

    if activeQuestTitles[lower] or textLine2:match("%d+%s*/%s*%d+") then
        return nil
    end

    if textLine2:sub(1, 1) == "<" and textLine2:sub(-1) == ">" then
        return textLine2
    else
        return "<" .. textLine2 .. ">"
    end
end

function FNC:GetNPCSubtitle(unit)
    local ok, result = pcall(GetNPCSubtitleInternal, unit)
    return ok and result or nil
end

-- Subgroup Check using UnitInRaid index lookup
function FNC.IsInMySubgroup(unit)
    if UnitIsUnit(unit, "player") then return true end
    if not IsInRaid() then return UnitInParty(unit) end

    local targetRaidIndex = UnitInRaid(unit)
    if not targetRaidIndex then return false end

    local playerRaidIndex = UnitInRaid("player")
    if not playerRaidIndex then return false end

    local _, _, playerSubgroup = GetRaidRosterInfo(playerRaidIndex)
    local _, _, targetSubgroup = GetRaidRosterInfo(targetRaidIndex)

    if playerSubgroup and targetSubgroup then
        return playerSubgroup == targetSubgroup
    end

    return false
end

-- Resolve whether a Friendly Minion belongs to Personal, Party (Subgroup), or Raid (Other Subgroups)
function FNC.ResolveFriendlyMinionSubKey(unit)
    if not IsSafeString(unit) then return nil end

    if UnitExists("pet") and UnitIsUnit(unit, "pet") then
        return "PersonalMinion"
    end

    if UnitIsOwnerOrControllerOfUnit and UnitIsOwnerOrControllerOfUnit("player", unit) then
        return "PersonalMinion"
    end

    if IsInRaid() then
        local numMembers = GetNumGroupMembers()
        for i = 1, numMembers do
            local raidUnit = "raid" .. i
            local raidPetUnit = "raidpet" .. i
            local isMatch = (UnitExists(raidPetUnit) and UnitIsUnit(unit, raidPetUnit))
                or (UnitExists(raidUnit) and UnitIsOwnerOrControllerOfUnit and UnitIsOwnerOrControllerOfUnit(raidUnit, unit))
            if isMatch then
                if UnitIsUnit(raidUnit, "player") then
                    return "PersonalMinion"
                elseif FNC.IsInMySubgroup(raidUnit) then
                    return "PartyMinion"
                else
                    return "RaidMinion"
                end
            end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local partyUnit = "party" .. i
            local partyPetUnit = "partypet" .. i
            local isMatch = (UnitExists(partyPetUnit) and UnitIsUnit(unit, partyPetUnit))
                or (UnitExists(partyUnit) and UnitIsOwnerOrControllerOfUnit and UnitIsOwnerOrControllerOfUnit(partyUnit, unit))
            if isMatch then
                return "PartyMinion"
            end
        end
    end

    local subtitle = FNC:GetNPCSubtitle(unit)
    if subtitle then
        local rawOwner = subtitle:match("^<?([^'’<>]+)['’]")
        if rawOwner then
            local cleanOwner = rawOwner:match("^%s*(.-)%s*$"):gsub("%-.*$", "")
            if cleanOwner ~= "" then
                local playerName = UnitName("player")
                if IsSafeString(playerName) and cleanOwner == playerName then
                    return "PersonalMinion"
                end

                if IsInRaid() then
                    local numMembers = GetNumGroupMembers()
                    for i = 1, numMembers do
                        local raidUnit = "raid" .. i
                        local memberName = UnitName(raidUnit)
                        if IsSafeString(memberName) and memberName == cleanOwner then
                            if FNC.IsInMySubgroup(raidUnit) then
                                return "PartyMinion"
                            else
                                return "RaidMinion"
                            end
                        end
                    end
                elseif IsInGroup() then
                    for i = 1, 4 do
                        local partyUnit = "party" .. i
                        local memberName = UnitName(partyUnit)
                        if IsSafeString(memberName) and memberName == cleanOwner then
                            return "PartyMinion"
                        end
                    end
                end
            end
        end
    end

    return nil
end
