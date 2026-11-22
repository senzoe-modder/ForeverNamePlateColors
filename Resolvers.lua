--------------------------------------------------------------------------------
-- Resolvers.lua
-- Subgroup Checks, Minion Owner Detection, QuestieDB / Quest Log Cache, & Tooltip Scanner
--------------------------------------------------------------------------------

local addonName, FNC = ...

-- QuestieDB + QuestiePlayer Cache (authoritative exact npcID tracking when Questie is installed)
local questieMobNpcIDs = {}
local questieTurnInNpcIDs = {}
local questieQuestIDs = {}
local questieCacheActive = false
local hasUnrecognizedQuest = false

-- Standalone Blizzard Quest Log Cache (fallback when Questie is not installed or for custom quests)
local activeQuestTitles = {}
local incompleteQuestTitles = {}
local completedQuestTitles = {}
local incompleteObjectiveTargets = {}
local incompleteObjectiveLabels = {}
local completedObjectiveTargets = {}
local turnInTargets = {}
local completedTurnInNPCs = {}
local questTextCorpus = ""
local questCacheGeneration = 0

-- Reusable scratch table for tooltip lines (zero per-call table allocation)
local tooltipLines = {}

-- Short-lived per-pass caches to avoid repeated tooltip/threat/quest scans on bursty nameplate updates
local tooltipCache = setmetatable({}, { __mode = "k" })
local taggedCache = {}
local questUnitCache = {}
local subtitleCache = {}
local cacheGeneration = -1

local function EnsurePassCacheFresh()
    local curGen = (FNC.updatePassGeneration or 0) * 100000 + questCacheGeneration
    if cacheGeneration ~= curGen then
        cacheGeneration = curGen
        wipe(tooltipCache)
        wipe(taggedCache)
        wipe(questUnitCache)
        wipe(subtitleCache)
    end
end

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

local function ParseObjectiveProgressLine(text)
    if not IsSafeString(text) then return nil end
    local cleaned = CleanTooltipText(text):gsub("^%-+%s*", "")
    if cleaned == "" then return nil end
    local lower = cleaned:lower()
    if lower:find("^level") or lower:find("^lvl") then return nil end

    -- Pattern 1: "Target: 2/6" or "2/6: Target"
    local prefix1, cur1, req1 = cleaned:match("^([^:]+):%s*(%d+)%s*/%s*(%d+)")
    if cur1 and req1 then
        local target = (prefix1 or ""):gsub("%s+slain$", ""):gsub("%s+killed$", ""):gsub("%s+collected$", ""):match("^%s*(.-)%s*$"):lower()
        return tonumber(cur1), tonumber(req1), target
    end

    -- Pattern 2: "2/6 Hillsbrad Farmer slain" or "2/6 Target"
    local cur2, req2, rest2 = cleaned:match("^(%d+)%s*/%s*(%d+)%s+(.+)$")
    if cur2 and req2 then
        local target = (rest2 or ""):gsub("%s+slain$", ""):gsub("%s+killed$", ""):gsub("%s+collected$", ""):gsub("%s*%(complete%)%s*$", ""):match("^%s*(.-)%s*$"):lower()
        return tonumber(cur2), tonumber(req2), target
    end

    return nil
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

--------------------------------------------------------------------------------
-- QuestieDB & QuestiePlayer Integration
--------------------------------------------------------------------------------

local cachedQuestiePlayer = nil
local cachedQuestieDB = nil
local cachedQuestieTooltips = nil

local function ImportQuestieModule(name)
    if QuestieLoader and type(QuestieLoader.ImportModule) == "function" then
        local ok, mod = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
        if ok and type(mod) == "table" then
            return mod
        end
    end
    if type(_G[name]) == "table" then
        return _G[name]
    end
    if type(Questie) == "table" and type(Questie[name]) == "table" then
        return Questie[name]
    end
    return nil
end

local function GetQuestieModules()
    if not cachedQuestiePlayer then
        cachedQuestiePlayer = ImportQuestieModule("QuestiePlayer")
    end
    if not cachedQuestieDB then
        cachedQuestieDB = ImportQuestieModule("QuestieDB")
    end
    if not cachedQuestieTooltips then
        cachedQuestieTooltips = ImportQuestieModule("QuestieTooltips")
    end
    return cachedQuestiePlayer, cachedQuestieDB, cachedQuestieTooltips
end

function FNC:IsQuestieReady()
    local qp, qdb, qt = GetQuestieModules()
    if not (qp or qdb or qt) then return false end
    if type(Questie) == "table" and Questie.started == false then return false end
    return true
end

local function IsQuestIdOnPlayer(questId)
    local qid = tonumber(questId)
    return qid ~= nil and qid > 0
end

local function IsQuestIdComplete(questId, questObj)
    local qid = tonumber(questId)
    if qid and qid > 0 and C_QuestLog and type(C_QuestLog.IsComplete) == "function" then
        local ok, comp = pcall(C_QuestLog.IsComplete, qid)
        if ok and comp ~= nil then
            return comp == true or comp == 1
        end
    end
    if type(questObj) == "table" then
        if type(questObj.IsComplete) == "function" then
            local okComp, status = pcall(questObj.IsComplete, questObj)
            if okComp and (status == 1 or status == true) then
                return true
            end
        end
        if questObj.isComplete == true then
            return true
        end
    end
    return false
end

local function AddQuestieObjectiveNpcs(obj, qdb)
    if type(obj) ~= "table" then return end

    local isObjDone = (obj.Completed == true)
        or (type(obj.Needed) == "number" and type(obj.Collected) == "number" and obj.Needed > 0 and obj.Collected >= obj.Needed)
    if isObjDone then
        return
    end

    -- 1. Direct SpawnList (monster, event, killcredit, and item objectives)
    if type(obj.SpawnList) == "table" then
        for npcId in pairs(obj.SpawnList) do
            local numId = tonumber(npcId)
            if numId and numId > 0 then
                questieMobNpcIDs[numId] = true
            end
        end
    end

    -- 2. Direct monster kill objective
    if obj.Type == "monster" then
        local numId = tonumber(obj.Id)
        if numId and numId > 0 then
            questieMobNpcIDs[numId] = true
        end
    end

    -- 3. Item drop / collect objective -> all NPCs that drop this item in QuestieDB
    if obj.Type == "item" then
        local itemId = tonumber(obj.Id)
        if itemId and itemId > 0 and qdb then
            local npcDrops = nil
            if type(qdb.QueryItemSingle) == "function" then
                local ok, drops = pcall(qdb.QueryItemSingle, itemId, "npcDrops")
                if ok and type(drops) == "table" then
                    npcDrops = drops
                end
            elseif type(qdb.GetItem) == "function" then
                local ok, item = pcall(qdb.GetItem, qdb, itemId)
                if ok and type(item) == "table" and type(item.npcDrops) == "table" then
                    npcDrops = item.npcDrops
                end
            end

            if type(npcDrops) == "table" then
                for _, npcId in ipairs(npcDrops) do
                    local numNpc = tonumber(npcId)
                    if numNpc and numNpc > 0 then
                        questieMobNpcIDs[numNpc] = true
                    end
                end
            end
        end
    end
end

local readyQuestIDs = {}
local lastQuestieError = nil

local function AddQuestieTurnInNpcs(questId, quest, qdb)
    if type(quest) == "table" and type(quest.Finisher) == "table" then
        local fType = type(quest.Finisher.Type) == "string" and quest.Finisher.Type:lower() or ""
        if fType == "" or fType == "monster" or fType == "npc" then
            local singleId = tonumber(quest.Finisher.Id)
            if singleId and singleId > 0 then
                questieTurnInNpcIDs[singleId] = true
            elseif type(quest.Finisher.Id) == "table" then
                for _, npcId in pairs(quest.Finisher.Id) do
                    local numId = tonumber(npcId)
                    if numId and numId > 0 then
                        questieTurnInNpcIDs[numId] = true
                    end
                end
            end
        end
    end

    if qdb and type(qdb.QueryQuestSingle) == "function" then
        local ok, finishedBy = pcall(qdb.QueryQuestSingle, questId, "finishedBy")
        if ok and type(finishedBy) == "table" and type(finishedBy[1]) == "table" then
            for _, npcId in ipairs(finishedBy[1]) do
                local numId = tonumber(npcId)
                if numId and numId > 0 then
                    questieTurnInNpcIDs[numId] = true
                end
            end
        end
    end
end

local function RebuildQuestieCache()
    wipe(questieMobNpcIDs)
    wipe(questieTurnInNpcIDs)
    wipe(questieQuestIDs)
    wipe(readyQuestIDs)
    questieCacheActive = false
    lastQuestieError = nil

    if not FNC:IsQuestieReady() then
        return false
    end

    local qp, qdb, qt = GetQuestieModules()
    local ok, err = pcall(function()
        -- 1. Check QuestiePlayer.currentQuestlog if populated
        if qp and type(qp.currentQuestlog) == "table" then
            for rawQuestId, quest in pairs(qp.currentQuestlog) do
                local questId = tonumber(rawQuestId)
                if questId and questId > 0 and IsQuestIdOnPlayer(questId) then
                    questieQuestIDs[questId] = true
                    local isComplete = IsQuestIdComplete(questId, quest)
                    if isComplete then
                        readyQuestIDs[questId] = true
                        AddQuestieTurnInNpcs(questId, quest, qdb)
                    elseif type(quest) == "table" then
                        if type(quest.Objectives) == "table" then
                            for _, obj in pairs(quest.Objectives) do
                                AddQuestieObjectiveNpcs(obj, qdb)
                            end
                        end
                        if type(quest.SpecialObjectives) == "table" then
                            for _, obj in pairs(quest.SpecialObjectives) do
                                AddQuestieObjectiveNpcs(obj, qdb)
                            end
                        end
                    end
                end
            end
        end

        -- 2. Check legacy or C_QuestLog quest log entries if available
        if GetNumQuestLogEntries and GetQuestLogTitle then
            local numEntries = GetNumQuestLogEntries() or 0
            for i = 1, numEntries do
                local _, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
                local qid = tonumber(questID)
                if not isHeader and qid and qid > 0 then
                    questieQuestIDs[qid] = true
                    if isComplete == 1 or isComplete == true or IsQuestIdComplete(qid, nil) then
                        readyQuestIDs[qid] = true
                        AddQuestieTurnInNpcs(qid, nil, qdb)
                    end
                end
            end
        elseif C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetQuestIDForQuestLogIndex then
            local numEntries = C_QuestLog.GetNumQuestLogEntries() or 0
            for i = 1, numEntries do
                local qid = tonumber(C_QuestLog.GetQuestIDForQuestLogIndex(i))
                if qid and qid > 0 then
                    questieQuestIDs[qid] = true
                    if IsQuestIdComplete(qid, nil) then
                        readyQuestIDs[qid] = true
                        AddQuestieTurnInNpcs(qid, nil, qdb)
                    end
                end
            end
        end

        -- 3. Harvest turn-in NPCs and active quest objective mobs from QuestieTooltips.lookupByKey ("m_<npcId>")
        if qt and type(qt.lookupByKey) == "table" then
            local questCompleteMemo = {}
            for qid, isReady in pairs(readyQuestIDs) do
                if isReady then
                    questCompleteMemo[qid] = true
                end
            end
            local processedInProgressQuests = {}

            local function IsEntryQuestComplete(qid)
                local cached = questCompleteMemo[qid]
                if cached ~= nil then
                    return cached
                end
                local comp = IsQuestIdComplete(qid, nil)
                questCompleteMemo[qid] = comp
                if comp then
                    readyQuestIDs[qid] = true
                end
                return comp
            end

            for key, entries in pairs(qt.lookupByKey) do
                if type(key) == "string" and key:sub(1, 2) == "m_" and type(entries) == "table" then
                    local npcId = tonumber(key:sub(3))
                    if npcId and npcId > 0 then
                        for _, entry in pairs(entries) do
                            local entryQid = type(entry) == "table" and tonumber(entry.questId) or nil
                            if entryQid and entryQid > 0 and IsQuestIdOnPlayer(entryQid) then
                                questieQuestIDs[entryQid] = true
                                if IsEntryQuestComplete(entryQid) then
                                    questieTurnInNpcIDs[npcId] = true
                                    AddQuestieTurnInNpcs(entryQid, nil, qdb)
                                else
                                    local obj = type(entry) == "table" and entry.objective or nil
                                    if type(obj) == "table" then
                                        local isObjDone = (obj.Completed == true)
                                            or (type(obj.Needed) == "number" and type(obj.Collected) == "number" and obj.Needed > 0 and obj.Collected >= obj.Needed)
                                        if not isObjDone then
                                            questieMobNpcIDs[npcId] = true
                                        end
                                    else
                                        questieMobNpcIDs[npcId] = true
                                    end

                                    if not processedInProgressQuests[entryQid] and qdb and type(qdb.GetQuest) == "function" then
                                        processedInProgressQuests[entryQid] = true
                                        local okQ, qObj = pcall(qdb.GetQuest, qdb, entryQid)
                                        if okQ and type(qObj) == "table" then
                                            if type(qObj.Objectives) == "table" then
                                                for _, qSubObj in pairs(qObj.Objectives) do
                                                    AddQuestieObjectiveNpcs(qSubObj, qdb)
                                                end
                                            end
                                            if type(qObj.SpecialObjectives) == "table" then
                                                for _, qSubObj in pairs(qObj.SpecialObjectives) do
                                                    AddQuestieObjectiveNpcs(qSubObj, qdb)
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)

    if not ok then
        lastQuestieError = tostring(err)
        return false
    end

    questieCacheActive = true
    return true
end

--------------------------------------------------------------------------------
-- Standalone Blizzard Quest Log Cache (Fallback when Questie is absent)
--------------------------------------------------------------------------------

local function AddTurnInNPC(rawTarget, isQuestComplete)
    if not IsSafeString(rawTarget) then return end
    local npc = rawTarget:match("^([^%.%!%?,\r\n]+)") or rawTarget
    npc = npc:lower()
    local afterTo = npc:match("^.+%s+to%s+(.+)$")
    if afterTo and afterTo ~= "" then
        npc = afterTo
    end
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
    npc = npc:gsub("^the%s+", ""):gsub("^a%s+", ""):gsub("^an%s+", ""):match("^%s*(.-)%s*$")
    if npc and npc ~= "" and #npc >= 3 then
        turnInTargets[npc] = true
        if isQuestComplete then
            completedTurnInNPCs[npc] = true
        end
    end
end

local function ScanTextForTurnInNPCs(text, isQuestComplete)
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
            AddTurnInNPC(match, isQuestComplete)
        end
    end
end

local rebuildingQuestCache = false
local lastQuestieEmptyRetryTime = 0

function FNC:RebuildQuestCache()
    if rebuildingQuestCache then return end
    rebuildingQuestCache = true
    questCacheGeneration = questCacheGeneration + 1
    local usingQuestie = RebuildQuestieCache()
    hasUnrecognizedQuest = false

    wipe(activeQuestTitles)
    wipe(incompleteQuestTitles)
    wipe(completedQuestTitles)
    wipe(incompleteObjectiveTargets)
    wipe(incompleteObjectiveLabels)
    wipe(completedObjectiveTargets)
    wipe(turnInTargets)
    wipe(completedTurnInNPCs)
    questTextCorpus = ""

    if not GetNumQuestLogEntries or not GetQuestLogTitle then
        rebuildingQuestCache = false
        return
    end

    local numEntries = GetNumQuestLogEntries() or 0

    -- When Questie is active, verify if all player quests exist in Questie's quest log.
    -- If every quest is tracked by Questie, we don't even need heavy quest log text selection.
    if usingQuestie then
        for i = 1, numEntries do
            local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
            if IsSafeString(title) and not isHeader then
                local cleanTitle = CleanTooltipText(title):gsub("^%[.-%]%s*", ""):gsub("%s*%(complete%)%s*$", ""):lower()
                if cleanTitle ~= "" then
                    activeQuestTitles[cleanTitle] = true
                end
                if type(questID) == "number" and questID > 0 and not questieQuestIDs[questID] then
                    hasUnrecognizedQuest = true
                end
            end
        end
        if not hasUnrecognizedQuest then
            rebuildingQuestCache = false
            return
        end
    end

    -- Fallback Blizzard Quest Log scanner (only runs when Questie is absent or for unrecognized custom quests)
    local corpusParts = {}
    local prevSelection = GetQuestLogSelection and GetQuestLogSelection() or 0

    for i = 1, numEntries do
        local title, _, _, isHeader, _, isComplete = GetQuestLogTitle(i)
        if IsSafeString(title) and not isHeader then
            local numObjectives = (GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i)) or 0
            local allBoardsDone = (numObjectives > 0) and (GetQuestLogLeaderBoard ~= nil)
            local questDescription, questObjectives, completionText

            if SelectQuestLogEntry then
                SelectQuestLogEntry(i)
                if GetQuestLogQuestText then
                    questDescription, questObjectives = GetQuestLogQuestText()
                end
                if GetQuestLogCompletionText then
                    completionText = GetQuestLogCompletionText()
                end
            end

            if allBoardsDone then
                for j = 1, numObjectives do
                    local desc, _, isDone = GetQuestLogLeaderBoard(j, i)
                    local curStr, reqStr = IsSafeString(desc) and desc:match("(%d+)%s*/%s*(%d+)") or nil
                    local curNum, reqNum = tonumber(curStr), tonumber(reqStr)
                    local boardDone = isDone or (curNum and reqNum and reqNum > 0 and curNum >= reqNum)
                    if not boardDone then
                        allBoardsDone = false
                        break
                    end
                end
            end

            local questReadyToTurnIn = (isComplete == 1) or (isComplete == true)
                or allBoardsDone
                or (numObjectives == 0)

            local cleanTitle = CleanTooltipText(title):gsub("^%[.-%]%s*", ""):gsub("%s*%(complete%)%s*$", ""):lower()
            if cleanTitle ~= "" then
                activeQuestTitles[cleanTitle] = true
                if questReadyToTurnIn then
                    completedQuestTitles[cleanTitle] = true
                else
                    incompleteQuestTitles[cleanTitle] = true
                end
                table.insert(corpusParts, cleanTitle)
            end

            if GetQuestLogLeaderBoard then
                for j = 1, numObjectives do
                    local desc, _, isDone = GetQuestLogLeaderBoard(j, i)
                    if IsSafeString(desc) then
                        local cleanDesc = CleanTooltipText(desc)
                        table.insert(corpusParts, cleanDesc:lower())

                        local curNum, reqNum, parsedTarget = ParseObjectiveProgressLine(cleanDesc)
                        local target = parsedTarget
                        local objComplete = isDone or (isComplete == 1) or (curNum and reqNum and reqNum > 0 and curNum >= reqNum)

                        if not objComplete then
                            if target and target ~= "" then
                                incompleteObjectiveLabels[target] = true
                            end
                            local descPrefix = cleanDesc:gsub(":%s*%d+%s*/%s*%d+.*$", ""):gsub("^%d+%s*/%s*%d+%s+", ""):match("^%s*(.-)%s*$"):lower()
                            if descPrefix ~= "" then
                                incompleteObjectiveLabels[descPrefix] = true
                            end
                        end

                        if target and target ~= "" then
                            if objComplete then
                                completedObjectiveTargets[target] = true
                            else
                                incompleteObjectiveTargets[target] = true
                            end
                        end

                        ScanTextForTurnInNPCs(cleanDesc, questReadyToTurnIn)
                    end
                end
            end

            if IsSafeString(questObjectives) then
                table.insert(corpusParts, CleanTooltipText(questObjectives):lower())
                ScanTextForTurnInNPCs(questObjectives, questReadyToTurnIn)
            end
            if IsSafeString(questDescription) then
                table.insert(corpusParts, CleanTooltipText(questDescription):lower())
                ScanTextForTurnInNPCs(questDescription, questReadyToTurnIn)
            end
            if IsSafeString(completionText) then
                table.insert(corpusParts, CleanTooltipText(completionText):lower())
                ScanTextForTurnInNPCs(completionText, questReadyToTurnIn)
            end
        end
    end

    questTextCorpus = " " .. table.concat(corpusParts, " | ") .. " "

    if prevSelection and prevSelection > 0 and SelectQuestLogEntry then
        SelectQuestLogEntry(prevSelection)
    end
    rebuildingQuestCache = false
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
    local inCombat = UnitAffectingCombat and UnitAffectingCombat(unit) or false

    if UnitThreatSituation and UnitThreatSituation("player", unit) ~= nil then
        return true
    end
    if hasMobTarget and UnitIsUnit(mobTarget, "player") then
        return true
    end
    if inCombat and UnitExists("playertarget") and UnitIsUnit("playertarget", unit) then
        return true
    end
    if UnitExists("pet") then
        if UnitThreatSituation and UnitThreatSituation("pet", unit) ~= nil then
            return true
        end
        if hasMobTarget and UnitIsUnit(mobTarget, "pet") then
            return true
        end
        if inCombat and UnitExists("pettarget") and UnitIsUnit("pettarget", unit) then
            return true
        end
    end

    if IsInRaid() then
        local anyGroupInCombat = inCombat and (UnitAffectingCombat("player") or (UnitExists("pet") and UnitAffectingCombat("pet")))
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
                if inCombat and UnitExists(rUnit .. "target") and UnitIsUnit(rUnit .. "target", unit) then
                    return true
                end
                if inCombat and UnitAffectingCombat(rUnit) then
                    anyGroupInCombat = true
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
                if inCombat and UnitExists(rPet .. "target") and UnitIsUnit(rPet .. "target", unit) then
                    return true
                end
                if inCombat and UnitAffectingCombat(rPet) then
                    anyGroupInCombat = true
                end
            end
        end
        if inCombat and anyGroupInCombat then
            return true
        end
    elseif IsInGroup() then
        local anyPartyInCombat = inCombat and (UnitAffectingCombat("player") or (UnitExists("pet") and UnitAffectingCombat("pet")))
        for i = 1, 4 do
            local pUnit = PARTY_UNITS[i]
            if UnitExists(pUnit) then
                if UnitThreatSituation and UnitThreatSituation(pUnit, unit) ~= nil then
                    return true
                end
                if hasMobTarget and UnitIsUnit(mobTarget, pUnit) then
                    return true
                end
                if inCombat and UnitExists(pUnit .. "target") and UnitIsUnit(pUnit .. "target", unit) then
                    return true
                end
                if inCombat and UnitAffectingCombat(pUnit) then
                    anyPartyInCombat = true
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
                if inCombat and UnitExists(pPet .. "target") and UnitIsUnit(pPet .. "target", unit) then
                    return true
                end
                if inCombat and UnitAffectingCombat(pPet) then
                    anyPartyInCombat = true
                end
            end
        end
        if inCombat and anyPartyInCombat then
            return true
        end
    end

    return false
end

function FNC:IsTaggedByPlayerOrParty(unit)
    if not IsSafeString(unit) then return false end
    EnsurePassCacheFresh()
    local guid = UnitGUID and UnitGUID(unit) or ""
    local combatFlag = (UnitAffectingCombat and UnitAffectingCombat(unit)) and "1" or "0"
    local tapFlag = (UnitIsTapDenied and UnitIsTapDenied(unit)) and "1" or "0"
    local key = unit .. "|" .. tostring(guid) .. "|" .. combatFlag .. "|" .. tapFlag
    local cached = taggedCache[key]
    if cached ~= nil then
        return cached
    end
    local ok, result = pcall(CheckTaggedByPlayerOrPartyInternal, unit)
    local res = ok and result == true
    taggedCache[key] = res
    return res
end

-- Hidden Tooltip Scraper for NPC Role/Job Subtitles, Minion Owner Tags, and Fallback Quest Objectives
local scanTooltip = CreateFrame("GameTooltip", "FNCScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function GetUnitTooltipLines(unit)
    wipe(tooltipLines)
    local count = 0

    if not IsSafeString(unit) then
        return tooltipLines, 0
    end

    EnsurePassCacheFresh()
    local guid = UnitGUID and UnitGUID(unit) or ""
    local cacheKey = unit .. "|" .. tostring(guid)
    local cachedEntry = tooltipCache[cacheKey]
    if cachedEntry then
        for i = 1, cachedEntry.count do
            tooltipLines[i] = cachedEntry[i]
        end
        return tooltipLines, cachedEntry.count
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

    local saved = { count = count }
    for i = 1, count do
        saved[i] = tooltipLines[i]
    end
    tooltipCache[cacheKey] = saved

    return tooltipLines, count
end

local function MatchesCompletedTurnInNPCName(lowerName)
    if not IsSafeString(lowerName) then return false end
    if completedTurnInNPCs[lowerName] then
        return true
    end
    for cachedNPC in pairs(completedTurnInNPCs) do
        if #cachedNPC >= 4 and lowerName:find(cachedNPC, 1, true) then
            return true
        end
    end
    return false
end

local function IsMobPortionCompletedFallback(unit, lowerName, lines, count)
    if not IsSafeString(unit) or not UnitCanAttack("player", unit) then
        return false
    end

    local hasIncompleteSignal = false
    if lowerName and incompleteObjectiveTargets[lowerName] then
        hasIncompleteSignal = true
    end

    if lines and count and count > 0 then
        for i = 1, count do
            local lineText = lines[i]
            if IsSafeString(lineText) then
                local curNum, reqNum = ParseObjectiveProgressLine(lineText)
                if curNum and reqNum and reqNum > 0 and curNum < reqNum then
                    hasIncompleteSignal = true
                end
            end
        end
    end

    if hasIncompleteSignal then
        return false
    end

    if lowerName and completedObjectiveTargets[lowerName] then
        return true
    end

    if lines and count and count > 0 then
        for i = 1, count do
            local lineText = lines[i]
            if IsSafeString(lineText) then
                local curNum, reqNum = ParseObjectiveProgressLine(lineText)
                if curNum and reqNum and reqNum > 0 and curNum >= reqNum then
                    return true
                end
            end
        end
    end

    return false
end

local function HasCompletedQuestTurnInForNPCFallback(lowerName, lines, count)
    if next(completedQuestTitles) == nil and next(completedTurnInNPCs) == nil then
        return false
    end

    if lowerName and MatchesCompletedTurnInNPCName(lowerName) then
        return true
    end

    if lines and count and count > 0 then
        for i = 1, count do
            local lineText = lines[i]
            if IsSafeString(lineText) then
                local lowerLine = lineText:lower()
                local cleanedLower = lowerLine:gsub("%s*%(complete%)%s*$", ""):match("^%s*(.-)%s*$")
                if completedQuestTitles[cleanedLower] then
                    return true
                end
                if lowerLine:find("(complete)", 1, true) or lowerLine:find("ready to turn in", 1, true) then
                    return true
                end
            end
        end
    end

    return false
end

local function IsPartyMemberProgressLine(lowerLine)
    local playerName = UnitName("player")
    local lowerPlayer = IsSafeString(playerName) and playerName:lower():gsub("%-.*$", "") or nil

    local prefix = lowerLine:gsub("^%-+%s*", ""):match("^([^:]+):")
    if prefix and prefix ~= "" then
        local cleanPrefix = prefix:gsub("%-.*$", ""):match("^%s*(.-)%s*$")
        if cleanPrefix ~= "" then
            if lowerPlayer and cleanPrefix == lowerPlayer then
                return false
            end
            if IsInRaid() then
                local numMembers = GetNumGroupMembers()
                for i = 1, numMembers do
                    local rName = UnitName(RAID_UNITS[i])
                    if IsSafeString(rName) and cleanPrefix == rName:lower():gsub("%-.*$", "") then
                        return true
                    end
                end
            elseif IsInGroup() then
                for i = 1, 4 do
                    local pName = UnitName(PARTY_UNITS[i])
                    if IsSafeString(pName) and cleanPrefix == pName:lower():gsub("%-.*$", "") then
                        return true
                    end
                end
            end
        end
    end

    if IsInRaid() then
        local numMembers = GetNumGroupMembers()
        for i = 1, numMembers do
            local rName = UnitName(RAID_UNITS[i])
            local cleanR = IsSafeString(rName) and rName:lower():gsub("%-.*$", "") or ""
            if #cleanR >= 2 and cleanR ~= lowerPlayer and lowerLine:find(cleanR, 1, true) then
                return true
            end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local pName = UnitName(PARTY_UNITS[i])
            local cleanP = IsSafeString(pName) and pName:lower():gsub("%-.*$", "") or ""
            if #cleanP >= 2 and cleanP ~= lowerPlayer and lowerLine:find(cleanP, 1, true) then
                return true
            end
        end
    end

    return false
end

local function HasIncompletePlayerObjectiveOnUnitFallback(lowerName, lines, count)
    if lowerName and incompleteObjectiveTargets[lowerName] then
        return true
    end

    if lowerName and #lowerName >= 4 and next(incompleteObjectiveTargets) ~= nil then
        local stemName = lowerName:gsub("s$", "")
        for targetName in pairs(incompleteObjectiveTargets) do
            local stemTarget = targetName:gsub("s$", "")
            if #targetName >= 4 and (
                lowerName:find(targetName, 1, true)
                or targetName:find(lowerName, 1, true)
                or (#stemName >= 4 and #stemTarget >= 4 and (stemName:find(stemTarget, 1, true) or stemTarget:find(stemName, 1, true)))
            ) then
                return true
            end
        end
    end

    if not lines or not count or count <= 0 then
        return false
    end

    local underPlayerIncompleteQuest = false
    for i = 1, count do
        local lineText = lines[i]
        if IsSafeString(lineText) then
            local lowerLine = lineText:lower()
            local cleanedTitle = lowerLine:gsub("^%[.-%]%s*", ""):gsub("%s*%(complete%)%s*$", ""):match("^%s*(.-)%s*$")
            if incompleteQuestTitles[cleanedTitle] then
                underPlayerIncompleteQuest = true
            elseif activeQuestTitles[cleanedTitle] and not incompleteQuestTitles[cleanedTitle] then
                underPlayerIncompleteQuest = false
            else
                local curNum, reqNum, parsedTarget = ParseObjectiveProgressLine(lineText)
                if curNum and reqNum and reqNum > 0 and curNum < reqNum then
                    if not IsPartyMemberProgressLine(lowerLine) then
                        local cleanTarget = parsedTarget or ""
                        if cleanTarget == ""
                            or not lowerName
                            or underPlayerIncompleteQuest
                            or next(incompleteQuestTitles) ~= nil
                            or cleanTarget:find(lowerName, 1, true)
                            or lowerName:find(cleanTarget, 1, true) then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

local function CheckActiveQuestUnitInternal(unit, uf)
    if not IsSafeString(unit) or UnitIsPlayer(unit) then return false end
    if UnitPlayerControlled(unit) or (UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(unit)) then
        return false
    end

    local canAttack = UnitCanAttack and UnitCanAttack("player", unit) or false

    -- If another player/party has tagged this mob, revert to Blizzard default tapped color
    if canAttack and UnitIsTapDenied and UnitIsTapDenied(unit) then
        return false
    end

    if FNC:IsQuestieReady() then
        if not questieCacheActive then
            FNC:RebuildQuestCache()
        elseif next(questieMobNpcIDs) == nil and next(questieTurnInNpcIDs) == nil then
            local now = (GetTime and GetTime()) or 0
            if (now - lastQuestieEmptyRetryTime) >= 2.0 then
                lastQuestieEmptyRetryTime = now
                FNC:RebuildQuestCache()
            end
        end
    end

    local npcID = GetNpcIDFromUnit(unit)

    -- 1. Primary path: Authoritative QuestieDB + QuestiePlayer exact npcID lookup
    if questieCacheActive then
        if not canAttack then
            if npcID and questieTurnInNpcIDs[npcID] then
                return true
            end
        else
            if npcID and questieMobNpcIDs[npcID] then
                return true
            end
        end

        -- If every quest in the player's quest log is recognized by Questie, do NOT fall back to
        -- tooltip scraping (which prevents party member quest lines from ever bleeding through).
        if not hasUnrecognizedQuest then
            return false
        end
    end

    -- 2. Fallback path: Standalone Blizzard Quest Log + Tooltip scanner (when Questie is absent or custom quest)
    local unitName = UnitName(unit)
    local lowerName = IsSafeString(unitName) and unitName:lower() or nil
    local lines, count = GetUnitTooltipLines(unit)

    if not canAttack then
        return HasCompletedQuestTurnInForNPCFallback(lowerName, lines, count)
    end

    if IsMobPortionCompletedFallback(unit, lowerName, lines, count) then
        return false
    end

    if HasIncompletePlayerObjectiveOnUnitFallback(lowerName, lines, count) then
        return true
    end

    if lowerName and #lowerName >= 4 and next(incompleteQuestTitles) ~= nil then
        if questTextCorpus:find(lowerName, 1, true) then
            return true
        end
    end

    if UnitIsQuestBoss and UnitIsQuestBoss(unit) then
        if lowerName and completedObjectiveTargets[lowerName] then
            return false
        end
        if next(incompleteQuestTitles) == nil then
            return false
        end
        for i = 1, count do
            local lineText = lines[i]
            if IsSafeString(lineText) then
                local cleanedTitle = lineText:gsub("%s*%(complete%)%s*$", ""):match("^%s*(.-)%s*$"):lower()
                if incompleteQuestTitles[cleanedTitle] then
                    return true
                end
            end
        end
    end

    return false
end

function FNC:IsActiveQuestUnit(unit, uf)
    if not IsSafeString(unit) then return false end
    EnsurePassCacheFresh()
    local guid = UnitGUID and UnitGUID(unit) or ""
    local key = unit .. "|" .. tostring(guid)
    local cached = questUnitCache[key]
    if cached ~= nil then
        return cached
    end
    local ok, result = pcall(CheckActiveQuestUnitInternal, unit, uf)
    local res = ok and result == true
    questUnitCache[key] = res
    return res
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
    if not IsSafeString(unit) then return nil end
    EnsurePassCacheFresh()
    local guid = UnitGUID and UnitGUID(unit) or ""
    local key = unit .. "|" .. tostring(guid)
    if subtitleCache[key] ~= nil then
        return subtitleCache[key] or nil
    end
    local ok, result = pcall(GetNPCSubtitleInternal, unit)
    local res = ok and result or false
    subtitleCache[key] = res
    return res or nil
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

-- Fast cached check for neutral ("yellow") attackable mobs (reaction == 4)
local yellowMobCache = {}
local yellowMobCacheGen = -1

function FNC:IsNeutralYellowMob(unit)
    if not IsSafeString(unit) or UnitIsPlayer(unit) then return false end
    if UnitPlayerControlled(unit) or (UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(unit)) then
        return false
    end
    local curGen = (FNC.updatePassGeneration or 0) * 100000 + questCacheGeneration
    if yellowMobCacheGen ~= curGen then
        yellowMobCacheGen = curGen
        wipe(yellowMobCache)
    end
    local guid = UnitGUID and UnitGUID(unit) or ""
    local key = unit .. "|" .. tostring(guid)
    local cached = yellowMobCache[key]
    if cached ~= nil then
        return cached
    end
    local isYellow = false
    if UnitCanAttack and UnitCanAttack("player", unit) and UnitReaction then
        local ok, reaction = pcall(UnitReaction, "player", unit)
        if ok and reaction == 4 then
            isYellow = true
        end
    end
    yellowMobCache[key] = isYellow
    return isYellow
end

function FNC:DumpQuestDebug(unit)
    local qp, qdb, qt = GetQuestieModules()
    local qLogPairs = 0
    if qp and type(qp.currentQuestlog) == "table" then
        for _ in pairs(qp.currentQuestlog) do qLogPairs = qLogPairs + 1 end
    end
    local qtKeys = 0
    if qt and type(qt.lookupByKey) == "table" then
        for _ in pairs(qt.lookupByKey) do qtKeys = qtKeys + 1 end
    end

    FNC:RebuildQuestCache()
    local mobCount, turnInCount = 0, 0
    for _ in pairs(questieMobNpcIDs) do mobCount = mobCount + 1 end
    for _ in pairs(questieTurnInNpcIDs) do turnInCount = turnInCount + 1 end

    local npcID = IsSafeString(unit) and GetNpcIDFromUnit(unit) or nil
    if lastQuestieError then
        print("QuestieCacheError: " .. tostring(lastQuestieError))
    end
    print(string.format("QuestieActive=%s Loader=%s QP=%s QDB=%s Started=%s QLog=%d QTKeys=%d Mobs=%d TurnIns=%d NpcID=%s InMobs=%s InTurnIn=%s IsQuestNow=%s",
        tostring(questieCacheActive),
        tostring(QuestieLoader ~= nil),
        tostring(qp ~= nil),
        tostring(qdb ~= nil),
        tostring(type(Questie) == "table" and Questie.started or nil),
        qLogPairs,
        qtKeys,
        mobCount,
        turnInCount,
        tostring(npcID),
        tostring(npcID and questieMobNpcIDs[npcID] == true),
        tostring(npcID and questieTurnInNpcIDs[npcID] == true),
        tostring(IsSafeString(unit) and FNC:IsActiveQuestUnit(unit) or nil)
    ))

    if npcID and qt and type(qt.lookupByKey) == "table" then
        local entries = qt.lookupByKey["m_" .. tostring(npcID)]
        if type(entries) == "table" then
            print("QuestieTooltips[m_" .. tostring(npcID) .. "]:")
            for k, v in pairs(entries) do
                print("  " .. tostring(k) .. " -> questId=" .. tostring(type(v) == "table" and v.questId or nil))
            end
        end
    end

    if IsSafeString(unit) then
        local lines, count = GetUnitTooltipLines(unit)
        print("Tooltip lines (" .. tostring(count) .. "):")
        for i = 1, count do
            print("  [" .. i .. "] " .. tostring(lines[i]))
        end
    end
end
