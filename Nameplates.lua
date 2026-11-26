--------------------------------------------------------------------------------
-- Nameplates.lua
-- Nameplate Frame Caching, Native Hook Integration, Color & Subtitle Rendering
--------------------------------------------------------------------------------

local addonName, FNC = ...
FNC.updatePassGeneration = FNC.updatePassGeneration or 0

-- Track hooked UnitFrames, hooked FontStrings, cached original colors, and custom subtitles
local hookedFrames = setmetatable({}, { __mode = "k" })
local hookedWidgets = setmetatable({}, { __mode = "k" })
local defaultNameColors = setmetatable({}, { __mode = "k" })
local customSubtitles = setmetatable({}, { __mode = "k" })
local hiddenByFNC = setmetatable({}, { __mode = "k" })
local customNameApplied = setmetatable({}, { __mode = "k" })

-- Cached frame parts & scanned extra nodes per UnitFrame to avoid repeated tree walks
local cachedNameFS = setmetatable({}, { __mode = "k" })
local cachedHealthBar = setmetatable({}, { __mode = "k" })
local cachedExtras = setmetatable({}, { __mode = "k" })

-- Coalesce multiple updates for the same UnitFrame within a single render frame
local pendingUnitFrames = setmetatable({}, { __mode = "k" })
local pendingFlushScheduled = false

local flushBatchUFs = {}
local flushBatchUnits = {}

local function FlushPendingUnitFrames()
    pendingFlushScheduled = false
    FNC.updatePassGeneration = (FNC.updatePassGeneration or 0) + 1
    local n = 0
    for uf, unit in pairs(pendingUnitFrames) do
        pendingUnitFrames[uf] = nil
        n = n + 1
        flushBatchUFs[n] = uf
        flushBatchUnits[n] = unit
    end
    for i = 1, n do
        local uf = flushBatchUFs[i]
        local unit = flushBatchUnits[i]
        flushBatchUFs[i] = nil
        flushBatchUnits[i] = nil
        if uf and not (uf.IsForbidden and uf:IsForbidden()) then
            local liveUnit = uf.displayedUnit or uf.unit or unit
            FNC:UpdateUnitFrameNow(uf, liveUnit)
        end
    end
end

local function ScheduleUnitFrameUpdate(uf, unit)
    if not uf or (uf.IsForbidden and uf:IsForbidden()) then return end
    if uf._fncUpdating or uf._fncUpdatingBlizzardName then return end
    if pendingUnitFrames[uf] then return end
    pendingUnitFrames[uf] = unit or uf.displayedUnit or uf.unit or true
    if not pendingFlushScheduled then
        pendingFlushScheduled = true
        C_Timer.After(0, FlushPendingUnitFrames)
    end
end

function FNC:QueueUnitFrameUpdate(uf, unit)
    ScheduleUnitFrameUpdate(uf, unit)
end

local function SafeSetShown(widget, visible)
    if not widget or (widget.IsForbidden and widget:IsForbidden()) then return end
    if widget.SetShown then
        pcall(widget.SetShown, widget, visible and true or false)
    end
end

local function HideWidgetForHeadline(widget)
    if not widget or (widget.IsForbidden and widget:IsForbidden()) then return end
    if widget.IsShown and widget:IsShown() then
        hiddenByFNC[widget] = true
    end
    SafeSetShown(widget, false)
end

local function RestoreWidgetFromHeadline(widget)
    if not widget or (widget.IsForbidden and widget:IsForbidden()) then return end
    if hiddenByFNC[widget] then
        hiddenByFNC[widget] = nil
        SafeSetShown(widget, true)
    end
end

local function IsSafeString(val)
    if issecretvalue and issecretvalue(val) then return false end
    if type(val) ~= "string" or val == "" then return false end
    return true
end

local function IsSafeNumber(val)
    if issecretvalue and issecretvalue(val) then return false end
    if type(val) ~= "number" then return false end
    return true
end

local function GetSafeGuid(unit)
    if not IsSafeString(unit) or not UnitGUID then return "" end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or not IsSafeString(guid) then return "" end
    return guid
end

local function GetCVarBoolSafe(cvarName)
    if type(cvarName) ~= "string" then return false end
    if C_CVar and C_CVar.GetCVarBool then
        local ok, val = pcall(C_CVar.GetCVarBool, cvarName)
        if ok and type(val) == "boolean" then return val end
    end
    if GetCVarBool then
        local ok, val = pcall(GetCVarBool, cvarName)
        if ok and type(val) == "boolean" then return val end
    end
    local raw = nil
    if C_CVar and C_CVar.GetCVar then
        local ok, val = pcall(C_CVar.GetCVar, cvarName)
        if ok and not (issecretvalue and issecretvalue(val)) then raw = val end
    elseif GetCVar then
        local ok, val = pcall(GetCVar, cvarName)
        if ok and not (issecretvalue and issecretvalue(val)) then raw = val end
    end
    return tostring(raw or "0") == "1"
end

-- Cache class color setting per pass so we don't query CVars hundreds of times when spinning in Stormwind/Orgrimmar
local cachedClassColorPass = -1
local cachedClassColorAll = false
local cachedClassColorFriendly = false
local cachedClassColorEnemy = false

local function GetBlizzardClassColorForUnit(unit, isEnemy, canAttack)
    if not IsSafeString(unit) or not UnitIsPlayer or not UnitIsPlayer(unit) then
        return nil
    end

    local pass = FNC.updatePassGeneration or 0
    if cachedClassColorPass ~= pass then
        cachedClassColorPass = pass
        cachedClassColorAll = GetCVarBoolSafe("ShowClassColorInNameplate")
        cachedClassColorFriendly = GetCVarBoolSafe("ShowClassColorInFriendlyNameplate")
        cachedClassColorEnemy = GetCVarBoolSafe("ShowClassColorInEnemyNameplate")
    end

    local classColorEnabled = cachedClassColorAll
        or ((not isEnemy and not canAttack) and cachedClassColorFriendly)
        or ((isEnemy or canAttack) and cachedClassColorEnemy)

    if not classColorEnabled then
        return nil
    end

    local _, classFile = UnitClass(unit)
    if not IsSafeString(classFile) then return nil end

    if C_ClassColor and C_ClassColor.GetClassColor then
        local ok, col = pcall(C_ClassColor.GetClassColor, classFile)
        if ok and col and IsSafeNumber(col.r) and IsSafeNumber(col.g) and IsSafeNumber(col.b) then
            return col.r, col.g, col.b
        end
    end

    local tbl = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if tbl and IsSafeNumber(tbl.r) and IsSafeNumber(tbl.g) and IsSafeNumber(tbl.b) then
        return tbl.r, tbl.g, tbl.b
    end

    return nil
end

-- Locate and cache the primary name FontString on a Classic Era UnitFrame
local function GetUnitFrameNameText(uf)
    if not uf or (uf.IsForbidden and uf:IsForbidden()) then return nil end
    if cachedNameFS[uf] then return cachedNameFS[uf] end

    if uf.NameContainer and uf.NameContainer.Name and uf.NameContainer.Name.SetTextColor then
        cachedNameFS[uf] = uf.NameContainer.Name
        return uf.NameContainer.Name
    end
    if uf.name and uf.name.SetTextColor then
        cachedNameFS[uf] = uf.name
        return uf.name
    end

    local numRegions = uf:GetNumRegions()
    for i = 1, numRegions do
        local region = select(i, uf:GetRegions())
        if region and region:IsObjectType("FontString") then
            local parentKey = region.GetParentKey and region:GetParentKey()
            if IsSafeString(parentKey) and parentKey:lower():find("name") then
                cachedNameFS[uf] = region
                return region
            end
        end
    end

    return nil
end

-- Locate and cache the HealthBar on a Classic Era UnitFrame
local function GetUnitFrameHealthBar(uf)
    if not uf or (uf.IsForbidden and uf:IsForbidden()) then return nil end
    if cachedHealthBar[uf] then return cachedHealthBar[uf] end

    if uf.healthBar and uf.healthBar.SetStatusBarColor then
        cachedHealthBar[uf] = uf.healthBar
        return uf.healthBar
    end
    if uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar and uf.HealthBarsContainer.healthBar.SetStatusBarColor then
        cachedHealthBar[uf] = uf.HealthBarsContainer.healthBar
        return uf.HealthBarsContainer.healthBar
    end

    local numChildren = uf:GetNumChildren()
    for i = 1, numChildren do
        local child = select(i, uf:GetChildren())
        if child and not (child.IsForbidden and child:IsForbidden()) and child:IsObjectType("StatusBar") then
            local parentKey = child.GetParentKey and child:GetParentKey()
            if IsSafeString(parentKey) and parentKey:lower():find("health") then
                cachedHealthBar[uf] = child
                return child
            end
        end
    end

    return nil
end

-- Collect extra FontStrings / health / level / border regions & children once per UnitFrame
local function CollectFrameTreeExtrasInto(frame, nameFS, outList, depth)
    if not frame or depth > 4 or (frame.IsForbidden and frame:IsForbidden()) then return end

    if frame.GetNumRegions then
        local numRegions = frame:GetNumRegions()
        for i = 1, numRegions do
            local region = select(i, frame:GetRegions())
            if region and region ~= nameFS and not customSubtitles[region] then
                if region:IsObjectType("FontString") then
                    outList[#outList + 1] = { widget = region, isFontString = true }
                else
                    local parentKey = region.GetParentKey and region:GetParentKey()
                    local regName = region.GetName and region:GetName()
                    local keyLower = IsSafeString(parentKey) and parentKey:lower() or ""
                    local nameLower = IsSafeString(regName) and regName:lower() or ""
                    if keyLower:find("level") or keyLower:find("health") or keyLower:find("border")
                        or nameLower:find("level") or nameLower:find("health") or nameLower:find("border") then
                        outList[#outList + 1] = { widget = region, isFontString = false }
                    end
                end
            end
        end
    end

    if frame.GetNumChildren then
        local numChildren = frame:GetNumChildren()
        for i = 1, numChildren do
            local child = select(i, frame:GetChildren())
            if child and not (child.IsForbidden and child:IsForbidden()) then
                local parentKey = child.GetParentKey and child:GetParentKey()
                local childName = child.GetName and child:GetName()
                local keyLower = IsSafeString(parentKey) and parentKey:lower() or ""
                local nameLower = IsSafeString(childName) and childName:lower() or ""

                local isCastOrPower = keyLower:find("cast") or keyLower:find("power")
                    or nameLower:find("cast") or nameLower:find("power")

                if not isCastOrPower and (keyLower:find("health") or keyLower:find("level")
                    or nameLower:find("health") or nameLower:find("level")) then
                    outList[#outList + 1] = { widget = child, isFontString = false }
                end

                if not isCastOrPower then
                    CollectFrameTreeExtrasInto(child, nameFS, outList, depth + 1)
                end
            end
        end
    end
end

local function GetOrBuildExtras(uf, nameFS)
    local extras = cachedExtras[uf]
    if extras then return extras end

    extras = {}
    CollectFrameTreeExtrasInto(uf, nameFS, extras, 0)

    local parent = uf:GetParent()
    if parent and not (parent.IsForbidden and parent:IsForbidden()) then
        CollectFrameTreeExtrasInto(parent, nameFS, extras, 0)
    end

    cachedExtras[uf] = extras
    return extras
end

local function ApplyExtrasVisibility(uf, nameFS, visible)
    local extras = GetOrBuildExtras(uf, nameFS)
    for i = 1, #extras do
        local entry = extras[i]
        local widget = entry.widget
        if entry.isFontString then
            if not visible then
                HideWidgetForHeadline(widget)
                if widget.SetAlpha then
                    pcall(widget.SetAlpha, widget, 0)
                end
            elseif hiddenByFNC[widget] then
                RestoreWidgetFromHeadline(widget)
                if widget.SetAlpha then
                    pcall(widget.SetAlpha, widget, 1)
                end
            end
        else
            if not visible then
                HideWidgetForHeadline(widget)
            else
                RestoreWidgetFromHeadline(widget)
            end
        end
    end
end

local function SetHealthBarAndLevelVisible(uf, hb, nameFS, visible)
    if not uf or (uf.IsForbidden and uf:IsForbidden()) then return end

    if not visible then
        HideWidgetForHeadline(uf.HealthBarsContainer)
        HideWidgetForHeadline(hb)
        HideWidgetForHeadline(uf.level)
        HideWidgetForHeadline(uf.LevelFrame)
        HideWidgetForHeadline(uf.highLevelTexture)
        HideWidgetForHeadline(uf.classificationIndicator)
    else
        SafeSetShown(uf.HealthBarsContainer, true)
        SafeSetShown(hb, true)
        RestoreWidgetFromHeadline(uf.level)
        RestoreWidgetFromHeadline(uf.LevelFrame)
        RestoreWidgetFromHeadline(uf.highLevelTexture)
        RestoreWidgetFromHeadline(uf.classificationIndicator)
    end

    ApplyExtrasVisibility(uf, nameFS, visible)
end

-- Create or update the custom NPC Title / Minion Owner subtitle FontString below the unit name
local function ApplySubtitle(uf, nameFS, showSubtitle, subtitleText, color)
    local subFS = customSubtitles[uf]
    if not showSubtitle or not IsSafeString(subtitleText) then
        if subFS and subFS:IsShown() then
            subFS:Hide()
        end
        return
    end

    if not subFS then
        subFS = uf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        customSubtitles[uf] = subFS
    end

    local fontPath, fontSize, fontFlags = nameFS:GetFont()
    if IsSafeString(fontPath) and IsSafeNumber(fontSize) and fontSize > 0 then
        local targetSize = math.max(fontSize - 2, 8)
        local flagsStr = fontFlags or ""
        local fontKey = fontPath .. "|" .. tostring(targetSize) .. "|" .. flagsStr
        if subFS._fncFontKey ~= fontKey then
            subFS._fncFontKey = fontKey
            subFS:SetFont(fontPath, targetSize, flagsStr)
        end
    end

    if not subFS._fncAnchored then
        subFS._fncAnchored = true
        subFS:ClearAllPoints()
        subFS:SetPoint("TOP", nameFS, "BOTTOM", 0, -1)
    end
    subFS:SetText(subtitleText)
    if color then
        subFS:SetTextColor(color.r, color.g, color.b, 1)
    else
        subFS:SetTextColor(1.0, 0.82, 0.0, 1)
    end
    if not subFS:IsShown() then
        subFS:Show()
    end
end

-- Hook a FontString so Blizzard SetText / SetTextColor calls cannot overwrite our custom name color
local function EnsureNameFontStringHooked(uf, nameFS)
    if not nameFS or hookedWidgets[nameFS] then return end
    hookedWidgets[nameFS] = true

    hooksecurefunc(nameFS, "SetTextColor", function()
        if uf._fncUpdating or uf._fncUpdatingBlizzardName then return end
        if not ForeverNamePlateColorsDB or not ForeverNamePlateColorsDB.enabled then return end
        local unit = uf.displayedUnit or uf.unit
        if IsSafeString(unit) and unit:match("^nameplate%d+$") then
            ScheduleUnitFrameUpdate(uf, unit)
        end
    end)

    hooksecurefunc(nameFS, "SetText", function()
        if uf._fncUpdating or uf._fncUpdatingBlizzardName then return end
        if not ForeverNamePlateColorsDB or not ForeverNamePlateColorsDB.enabled then return end
        local unit = uf.displayedUnit or uf.unit
        if IsSafeString(unit) and unit:match("^nameplate%d+$") then
            ScheduleUnitFrameUpdate(uf, unit)
        end
    end)
end

-- Hook Blizzard's CompactUnitFrame updates once per nameplate frame
local function HookUnitFrame(uf)
    if not uf or (uf.IsForbidden and uf:IsForbidden()) then return end

    local nameFS = GetUnitFrameNameText(uf)
    if nameFS then
        EnsureNameFontStringHooked(uf, nameFS)
    end
    if uf.name and uf.name ~= nameFS then
        EnsureNameFontStringHooked(uf, uf.name)
    end

    if hookedFrames[uf] then return end
    hookedFrames[uf] = true

    local hb = GetUnitFrameHealthBar(uf)
    if hb and not hookedWidgets[hb] then
        hookedWidgets[hb] = true
        hooksecurefunc(hb, "SetStatusBarColor", function()
            if uf._fncUpdating or uf._fncUpdatingBlizzardName then return end
            if not ForeverNamePlateColorsDB or not ForeverNamePlateColorsDB.enabled then return end
            local unit = uf.displayedUnit or uf.unit
            if IsSafeString(unit) and unit:match("^nameplate%d+$") then
                ScheduleUnitFrameUpdate(uf, unit)
            end
        end)
    end

    if uf.HealthBarsContainer and uf.HealthBarsContainer.Show and not hookedWidgets[uf.HealthBarsContainer] then
        hookedWidgets[uf.HealthBarsContainer] = true
        hooksecurefunc(uf.HealthBarsContainer, "Show", function()
            if uf._fncUpdating or uf._fncUpdatingBlizzardName then return end
            if not ForeverNamePlateColorsDB or not ForeverNamePlateColorsDB.enabled then return end
            local unit = uf.displayedUnit or uf.unit
            if IsSafeString(unit) and unit:match("^nameplate%d+$") then
                ScheduleUnitFrameUpdate(uf, unit)
            end
        end)
    end
end

-- Restore Blizzard's default health bar, level visibility, name color, and hide custom subtitles
function FNC:ResetUnitFrame(uf)
    if not uf or (uf.IsForbidden and uf:IsForbidden()) then return end
    if uf._fncUpdating then return end
    uf._fncUpdating = true

    local hb = GetUnitFrameHealthBar(uf)
    local nameFS = GetUnitFrameNameText(uf)
    SetHealthBarAndLevelVisible(uf, hb, nameFS, true)

    if nameFS then
        local unit = uf.displayedUnit or uf.unit
        local isEnemy = IsSafeString(unit) and UnitIsEnemy("player", unit) or false
        local canAttack = IsSafeString(unit) and UnitCanAttack("player", unit) or false
        local cr, cg, cb = GetBlizzardClassColorForUnit(unit, isEnemy, canAttack)
        if cr and cg and cb then
            nameFS:SetTextColor(cr, cg, cb, 1)
        else
            local orig = defaultNameColors[nameFS]
            if orig then
                nameFS:SetTextColor(orig.r, orig.g, orig.b, orig.a or 1)
            elseif CompactUnitFrame_UpdateName and not uf._fncUpdatingBlizzardName then
                uf._fncUpdatingBlizzardName = true
                pcall(CompactUnitFrame_UpdateName, uf)
                uf._fncUpdatingBlizzardName = false
            end
        end
    end

    if customSubtitles[uf] and customSubtitles[uf]:IsShown() then
        customSubtitles[uf]:Hide()
    end

    uf._fncUpdating = false
end

-- Core UnitFrame styling routine
function FNC:UpdateUnitFrameNow(uf, unit)
    if not uf or (uf.IsForbidden and uf:IsForbidden()) then return end
    if uf._fncUpdating then return end

    if not ForeverNamePlateColorsDB or not ForeverNamePlateColorsDB.enabled then
        self:ResetUnitFrame(uf)
        return
    end

    unit = unit or uf.displayedUnit or uf.unit
    if not IsSafeString(unit) or not UnitExists(unit) then return end

    -- Skip personal nameplate if shown
    if UnitIsUnit(unit, "player") then return end

    HookUnitFrame(uf)
    uf._fncUpdating = true

    local isUnitPlayer = UnitIsPlayer(unit)
    local isEnemy = UnitIsEnemy("player", unit)
    local canAttack = UnitCanAttack("player", unit)
    local isSubgroup = (isUnitPlayer and FNC.IsInMySubgroup) and FNC.IsInMySubgroup(unit) or false
    local isRaidMember = isUnitPlayer and (UnitInRaid(unit) ~= nil) or false
    local isTapDenied = canAttack and (not isUnitPlayer) and UnitIsTapDenied and UnitIsTapDenied(unit)

    local matchedCfg = nil
    local matchedCat = nil

    for _, cfg in ipairs(FNC.CATEGORY_CONFIG) do
        local cat = ForeverNamePlateColorsDB.categories and ForeverNamePlateColorsDB.categories[cfg.key]
        if cat and cat.enabled and cfg.match(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack, uf) then
            matchedCfg = cfg
            matchedCat = cat
            break
        end
    end

    if not matchedCfg or not matchedCat then
        uf._fncUpdating = false
        self:ResetUnitFrame(uf)
        return
    end

    local npcCat = ForeverNamePlateColorsDB.categories and ForeverNamePlateColorsDB.categories["NPC"]

    -- Resolve FriendlyMinion sub-category overrides (Personal / Party / Raid) if enabled
    local activeStyle = matchedCat
    local subtitleEnabled = (matchedCfg.hasSubtitleOption and matchedCat.showSubtitle == true)
    if matchedCfg.key == "ActiveQuestUnit" and (not canAttack) and npcCat and npcCat.enabled and npcCat.showSubtitle then
        subtitleEnabled = true
    end

    local activeSubCat = nil
    if matchedCfg.key == "FriendlyMinion" and matchedCat.subCategories then
        local subKey = (FNC.ResolveFriendlyMinionSubKey and FNC.ResolveFriendlyMinionSubKey(unit) or nil)
        if subKey and matchedCat.subCategories[subKey] and matchedCat.subCategories[subKey].enabled then
            activeSubCat = matchedCat.subCategories[subKey]
            activeStyle = activeSubCat
            subtitleEnabled = subtitleEnabled and (activeStyle.subtitleEnabled ~= false)
        end
    end

    local hb = GetUnitFrameHealthBar(uf)
    local nameFS = GetUnitFrameNameText(uf)

    if nameFS and not defaultNameColors[nameFS] then
        local r, g, b, a = nameFS:GetTextColor()
        local isPureWhite = IsSafeNumber(r) and IsSafeNumber(g) and IsSafeNumber(b)
            and math.abs(r - 1) < 0.001 and math.abs(g - 1) < 0.001 and math.abs(b - 1) < 0.001
        if IsSafeNumber(r) and IsSafeNumber(g) and IsSafeNumber(b) and not isPureWhite then
            defaultNameColors[nameFS] = { r = r, g = g, b = b, a = IsSafeNumber(a) and a or 1 }
        end
    end

    -- Apply Health Bar & Level visibility and color (ActiveQuestUnit friendly NPCs inherit NPC headline mode)
    local showHealthBar = not (matchedCfg.hasHealthBarOption and matchedCat.showHealthBar == false)
    if matchedCfg.key == "ActiveQuestUnit" then
        if canAttack then
            showHealthBar = true
        elseif npcCat and npcCat.enabled then
            showHealthBar = (npcCat.showHealthBar ~= false)
        else
            showHealthBar = false
        end
    end
    SetHealthBarAndLevelVisible(uf, hb, nameFS, showHealthBar)

    if hb and showHealthBar and (not isTapDenied) then
        if matchedCfg.hasHealthOption and activeStyle.healthEnabled and activeStyle.colorHealth then
            local c = activeStyle.colorHealth
            hb:SetStatusBarColor(c.r, c.g, c.b, 1)
        end
    end

    -- Apply Name text and color (SetText first so SetTextColor sticks cleanly afterward)
    if nameFS then
        if not showHealthBar then
            local unitName = UnitName(unit)
            if IsSafeString(unitName) then
                local currentText = nameFS:GetText()
                if IsSafeString(currentText) and currentText ~= unitName then
                    nameFS:SetText(unitName)
                end
            end
        end

        local resolvedNameColor = nil
        if activeSubCat and activeSubCat.nameEnabled and activeSubCat.colorName then
            resolvedNameColor = activeSubCat.colorName
        elseif matchedCat.nameEnabled and matchedCat.colorName then
            resolvedNameColor = matchedCat.colorName
        elseif matchedCfg.key == "ActiveQuestUnit" and matchedCat.colorName then
            resolvedNameColor = matchedCat.colorName
        elseif matchedCfg.key == "FriendlyMinion" and matchedCfg.defaultName then
            resolvedNameColor = matchedCfg.defaultName
        end

        if resolvedNameColor then
            nameFS:SetTextColor(resolvedNameColor.r, resolvedNameColor.g, resolvedNameColor.b, 1)
            customNameApplied[nameFS] = true
        else
            local cr, cg, cb = GetBlizzardClassColorForUnit(unit, isEnemy, canAttack)
            if cr and cg and cb then
                nameFS:SetTextColor(cr, cg, cb, 1)
                customNameApplied[nameFS] = true
            else
                if customNameApplied[nameFS] and CompactUnitFrame_UpdateName and not uf._fncUpdatingBlizzardName then
                    uf._fncUpdatingBlizzardName = true
                    pcall(CompactUnitFrame_UpdateName, uf)
                    uf._fncUpdatingBlizzardName = false
                end
                customNameApplied[nameFS] = nil
            end
        end
    end

    -- Apply NPC Title or Minion Owner subtitle
    local hasSubtitleCapable = matchedCfg.hasSubtitleOption or (matchedCfg.key == "ActiveQuestUnit" and (not canAttack))
    if nameFS and hasSubtitleCapable then
        if subtitleEnabled then
            local subText = (FNC.GetNPCSubtitle and FNC:GetNPCSubtitle(unit) or nil)
            local subColor = activeStyle.colorSubtitle
            if matchedCfg.key == "ActiveQuestUnit" then
                subColor = (matchedCat.nameEnabled and matchedCat.colorName)
                    or (npcCat and npcCat.colorSubtitle)
                    or matchedCat.colorName
            end
            ApplySubtitle(uf, nameFS, true, subText, subColor)
        else
            ApplySubtitle(uf, nameFS, false)
        end
    elseif customSubtitles[uf] and customSubtitles[uf]:IsShown() then
        customSubtitles[uf]:Hide()
    end

    uf._fncUpdating = false
end

function FNC:UpdateUnitFrame(uf, unit)
    self:UpdateUnitFrameNow(uf, unit)
end

local function OnCompactUnitFrameHook(uf)
    if not uf or uf._fncUpdating or uf._fncUpdatingBlizzardName or (uf.IsForbidden and uf:IsForbidden()) then return end
    local unit = uf.displayedUnit or uf.unit
    if IsSafeString(unit) and unit:match("^nameplate%d+$") then
        HookUnitFrame(uf)
        ScheduleUnitFrameUpdate(uf, unit)
    end
end

if CompactUnitFrame_UpdateHealthColor then
    hooksecurefunc("CompactUnitFrame_UpdateHealthColor", OnCompactUnitFrameHook)
end

if CompactUnitFrame_UpdateName then
    hooksecurefunc("CompactUnitFrame_UpdateName", OnCompactUnitFrameHook)
end

if CompactUnitFrame_UpdateLevel then
    hooksecurefunc("CompactUnitFrame_UpdateLevel", OnCompactUnitFrameHook)
end

if CompactUnitFrame_UpdateSelectionHighlight then
    hooksecurefunc("CompactUnitFrame_UpdateSelectionHighlight", OnCompactUnitFrameHook)
end

-- Refresh or reset all active nameplates on screen in a single pass
function FNC:RefreshAllPlates()
    if FNC.SyncAllCVars then
        FNC:SyncAllCVars()
    end
    FNC.updatePassGeneration = (FNC.updatePassGeneration or 0) + 1
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local uf = plate.UnitFrame or plate.unitFrame
        if uf and not uf:IsForbidden() then
            HookUnitFrame(uf)
            local unit = uf.displayedUnit or uf.unit
            if IsSafeString(unit) then
                self:UpdateUnitFrameNow(uf, unit)
            else
                self:ResetUnitFrame(uf)
            end
        end
    end
end

function FNC:ResetAllPlates()
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local uf = plate.UnitFrame or plate.unitFrame
        if uf and not uf:IsForbidden() then
            self:ResetUnitFrame(uf)
            if CompactUnitFrame_UpdateHealthColor then pcall(CompactUnitFrame_UpdateHealthColor, uf) end
            if CompactUnitFrame_UpdateName then pcall(CompactUnitFrame_UpdateName, uf) end
        end
    end
end
