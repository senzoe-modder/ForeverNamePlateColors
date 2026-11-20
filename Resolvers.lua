--------------------------------------------------------------------------------
-- Resolvers.lua
-- Subgroup Checks, Minion Owner Detection, Quest Log Cache, & Tooltip Scanner
--------------------------------------------------------------------------------

local addonName, FNC = ...

-- Active Quest Log Cache
local activeQuestTitles = {}
local incompleteObjectiveTargets = {}
local turnInTargets = {}

local function CleanTooltipText(text)
    if not text or text == "" then return "" end
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
end

function FNC:RebuildQuestCache()
    wipe(activeQuestTitles)
    wipe(incompleteObjectiveTargets)
    wipe(turnInTargets)

    if not GetNumQuestLogEntries or not GetQuestLogTitle then return end

    local numEntries = GetNumQuestLogEntries()
    for i = 1, numEntries do
        local title, _, _, isHeader, _, isComplete = GetQuestLogTitle(i)
        if title and not isHeader then
            local cleanTitle = CleanTooltipText(title):gsub("^%[.-%]%s*", ""):lower()
            if cleanTitle ~= "" then
                activeQuestTitles[cleanTitle] = true
            end

            if GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
                local numObjectives = GetNumQuestLeaderBoards(i) or 0
                for j = 1, numObjectives do
                    local desc, _, isDone = GetQuestLogLeaderBoard(j, i)
                    if desc and desc ~= "" then
                        local cleanDesc = CleanTooltipText(desc)
                        if not isDone then
                            -- Extract target name before ": X/Y" (e.g., "Goretusk Liver: 3/8" or "Defias Pillager slain: 2/10")
                            local target = cleanDesc:match("^([^:]+):%s*%d+%s*/%s*%d+")
                            if target then
                                target = target:gsub("%s+slain$", ""):gsub("%s+killed$", ""):gsub("%s+collected$", ""):match("^%s*(.-)%s*$"):lower()
                                if target ~= "" then
                                    incompleteObjectiveTargets[target] = true
                                end
                            end

                            -- Extract NPC interaction / turn-in targets (e.g., "Speak with Marshal Dughan")
                            local lowerDesc = cleanDesc:lower()
                            local npcTarget = lowerDesc:match("^speak with%s+(.+)")
                                or lowerDesc:match("^talk to%s+(.+)")
                                or lowerDesc:match("^return to%s+(.+)")
                                or lowerDesc:match("^report to%s+(.+)")
                                or lowerDesc:match("^deliver%s+.+%s+to%s+(.+)")
                                or lowerDesc:match("^bring%s+.+%s+to%s+(.+)")
                            if npcTarget then
                                npcTarget = npcTarget:gsub("[%.%!%?]+$", ""):gsub(":%s*%d+%s*/%s*%d+$", ""):match("^%s*(.-)%s*$")
                                if npcTarget ~= "" then
                                    turnInTargets[npcTarget] = true
                                end
                            end
                        elseif isComplete then
                            local lowerDesc = cleanDesc:lower()
                            local npcTarget = lowerDesc:match("^return to%s+(.+)")
                                or lowerDesc:match("^report to%s+(.+)")
                                or lowerDesc:match("^speak with%s+(.+)")
                                or lowerDesc:match("^talk to%s+(.+)")
                            if npcTarget then
                                npcTarget = npcTarget:gsub("[%.%!%?]+$", ""):match("^%s*(.-)%s*$")
                                if npcTarget ~= "" then
                                    turnInTargets[npcTarget] = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Hidden Tooltip Scraper for NPC Role/Job Subtitles, Minion Owner Tags, and Quest Objectives
local scanTooltip = CreateFrame("GameTooltip", "FNCScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function GetUnitTooltipLines(unit)
    local lines = {}

    -- 1. Query modern C_TooltipInfo API (Classic Era 1.15+)
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local data = C_TooltipInfo.GetUnit(unit)
        if data and data.lines then
            for i = 2, #data.lines do
                local line = data.lines[i]
                if line and line.leftText and line.leftText ~= "" then
                    table.insert(lines, CleanTooltipText(line.leftText))
                end
            end
        end
    end

    -- 2. Fallback to hidden scanning tooltip
    if #lines == 0 then
        scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
        scanTooltip:ClearLines()
        scanTooltip:SetUnit(unit)
        local numLines = scanTooltip:NumLines() or 0
        for i = 2, numLines do
            local fs = _G["FNCScanTooltipTextLeft" .. i]
            if fs then
                local txt = fs:GetText()
                if txt and txt ~= "" then
                    table.insert(lines, CleanTooltipText(txt))
                end
            end
        end
    end

    return lines
end

function FNC:IsActiveQuestUnit(unit, uf)
    if not unit or UnitIsPlayer(unit) then return false end
    if UnitPlayerControlled(unit) or (UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(unit)) then
        return false
    end

    -- 1. Direct Classic Era Quest Boss / CompactUnitFrame Quest Icon checks
    if UnitIsQuestBoss and UnitIsQuestBoss(unit) then
        return true
    end
    if uf and ((uf.questIcon and uf.questIcon:IsShown()) or (uf.QuestIcon and uf.QuestIcon:IsShown())) then
        return true
    end

    -- 2. Match unit name against cached quest objective targets & turn-in NPCs
    local unitName = UnitName(unit)
    if unitName and unitName ~= "" then
        local lowerName = unitName:lower()
        if incompleteObjectiveTargets[lowerName] or turnInTargets[lowerName] then
            return true
        end
    end

    -- 3. Scan tooltip lines 2..NumLines() for active quest titles or incomplete objective counters
    local lines = GetUnitTooltipLines(unit)
    for _, lineText in ipairs(lines) do
        if lineText ~= "" then
            local lowerLine = lineText:lower()
            if activeQuestTitles[lowerLine] then
                return true
            end

            -- Match objective counter patterns like "In Search of Anthry (3/5 Collected)" or "Goretusk Liver: 3/8"
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

function FNC:GetNPCSubtitle(unit)
    if not unit or UnitIsPlayer(unit) then return nil end

    local lines = GetUnitTooltipLines(unit)
    local textLine2 = lines[1] -- lines[1] corresponds to tooltip line 2

    if not textLine2 or textLine2 == "" then return nil end
    if textLine2 == "Unknown" or (UNKNOWNOBJECT and textLine2 == UNKNOWNOBJECT) then
        return nil
    end

    -- Check if line 2 is level / boss / corpse / player info
    local lower = textLine2:lower()
    if lower:find("^level") or lower:find("^lvl") or lower:find("^%?%?") or textLine2:match("^%d") or lower:find("corpse") then
        return nil
    end

    -- Filter out faction strings
    if textLine2 == "Alliance" or textLine2 == "Horde" or textLine2 == "Neutral" then
        return nil
    end

    -- Filter out quest objective lines if an untitled NPC displays a quest line on line 2
    if activeQuestTitles[lower] or textLine2:match("%d+%s*/%s*%d+") then
        return nil
    end

    if textLine2:sub(1, 1) == "<" and textLine2:sub(-1) == ">" then
        return textLine2
    else
        return "<" .. textLine2 .. ">"
    end
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
    if not unit then return nil end

    -- 1. Direct primary pet check for player ("pet")
    if UnitExists("pet") and UnitIsUnit(unit, "pet") then
        return "PersonalMinion"
    end

    -- 2. Direct owner/controller check for player guardians & totems
    if UnitIsOwnerOrControllerOfUnit and UnitIsOwnerOrControllerOfUnit("player", unit) then
        return "PersonalMinion"
    end

    -- 3. Group roster checks (Raid or 5-man Party)
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

    -- 4. Fallback: Parse owner name from tooltip subtitle (e.g. "<OwnerName's Minion>")
    local subtitle = FNC:GetNPCSubtitle(unit)
    if subtitle then
        local rawOwner = subtitle:match("^<?([^'’<>]+)['’]")
        if rawOwner then
            local cleanOwner = rawOwner:match("^%s*(.-)%s*$"):gsub("%-.*$", "")
            if cleanOwner ~= "" then
                local playerName = UnitName("player")
                if playerName and cleanOwner == playerName then
                    return "PersonalMinion"
                end

                if IsInRaid() then
                    local numMembers = GetNumGroupMembers()
                    for i = 1, numMembers do
                        local raidUnit = "raid" .. i
                        local memberName = UnitName(raidUnit)
                        if memberName and memberName == cleanOwner then
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
                        if memberName and memberName == cleanOwner then
                            return "PartyMinion"
                        end
                    end
                end
            end
        end
    end

    return nil
end