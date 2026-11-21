--------------------------------------------------------------------------------
-- Nameplates.lua
-- Nameplate Frame Caching, Native Hook Integration, Color & Subtitle Rendering
--------------------------------------------------------------------------------

local addonName, FNC = ...

-- Track hooked UnitFrames, hooked FontStrings, cached original colors, and custom subtitles
local hookedFrames = setmetatable({}, { __mode = "k" })
local hookedWidgets = setmetatable({}, { __mode = "k" })
local defaultNameColors = setmetatable({}, { __mode = "k" })
local customSubtitles = setmetatable({}, { __mode = "k" })

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

local function SafeSetShown(widget, visible)
    if not widget or (widget.IsForbidden and widget:IsForbidden()) then return end
    if widget.SetShown then
        pcall(widget.SetShown, widget, visible and true or false)
    end
end

-- Locate the primary name FontString on a Classic Era UnitFrame
local function GetUnitFrameNameText(uf)
    if not uf or (uf.IsForbidden and uf:IsForbidden()) then return nil end
    if uf.NameContainer and uf.NameContainer.Name and uf.NameContainer.Name.SetTextColor then
        return uf.NameContainer.Name
    end
    if uf.name and uf.name.SetTextColor then
        return uf.name
    end

    local numRegions = uf:GetNumRegions()
    for i = 1, numRegions do
        local region = select(i, uf:GetRegions())
        if region and region:IsObjectType("FontString") then
            local parentKey = region.GetParentKey and region:GetParentKey()
            if IsSafeString(parentKey) and parentKey:lower():find("name") then
                return region
            end
        end
    end

    return nil
end

-- Locate the HealthBar on a Classic Era UnitFrame
local function GetUnitFrameHealthBar(uf)
    if not uf or (uf.IsForbidden and uf:IsForbidden()) then return nil end
    if uf.healthBar and uf.healthBar.SetStatusBarColor then
        return uf.healthBar
    end
    if uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar and uf.HealthBarsContainer.healthBar.SetStatusBarColor then
        return uf.HealthBarsContainer.healthBar
    end

    local numChildren = uf:GetNumChildren()
    for i = 1, numChildren do
        local child = select(i, uf:GetChildren())
        if child and not (child.IsForbidden and child:IsForbidden()) and child:IsObjectType("StatusBar") then
            local parentKey = child.GetParentKey and child:GetParentKey()
            if IsSafeString(parentKey) and parentKey:lower():find("health") then
                return child
            end
        end
    end

    return nil
end

-- Toggle visibility of ONLY the health bar, borders, and unit level/skull elements
-- (never touch uf.castBar or uf.powerBar, which are separate StatusBars on player plates)
local function ToggleFrameTreeExtras(frame, nameFS, subFS, visible, depth)
    if not frame or depth > 4 or (frame.IsForbidden and frame:IsForbidden()) then return end

    if frame.GetNumRegions then
        local numRegions = frame:GetNumRegions()
        for i = 1, numRegions do
            local region = select(i, frame:GetRegions())
            if region and region ~= nameFS and region ~= subFS then
                if region:IsObjectType("FontString") then
                    SafeSetShown(region, visible)
                    if region.SetAlpha then
                        pcall(region.SetAlpha, region, visible and 1 or 0)
                    end
                elseif not visible then
                    local parentKey = region.GetParentKey and region:GetParentKey()
                    local regName = region.GetName and region:GetName()
                    local keyLower = IsSafeString(parentKey) and parentKey:lower() or ""
                    local nameLower = IsSafeString(regName) and regName:lower() or ""
                    if keyLower:find("level") or keyLower:find("health") or keyLower:find("border")
                        or nameLower:find("level") or nameLower:find("health") or nameLower:find("border") then
                        SafeSetShown(region, false)
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

                -- Skip castBar and powerBar so we never force-show Blizzard's yellow cast bar
                local isCastOrPower = keyLower:find("cast") or keyLower:find("power")
                    or nameLower:find("cast") or nameLower:find("power")

                if not isCastOrPower and (keyLower:find("health") or keyLower:find("level")
                    or nameLower:find("health") or nameLower:find("level")) then
                    SafeSetShown(child, visible)
                end

                if not isCastOrPower then
                    ToggleFrameTreeExtras(child, nameFS, subFS, visible, depth + 1)
                end
            end
        end
    end
end

local function SetHealthBarAndLevelVisible(uf, hb, nameFS, visible)
    if not uf or (uf.IsForbidden and uf:IsForbidden()) then return end

    SafeSetShown(uf.HealthBarsContainer, visible)
    SafeSetShown(hb, visible)
    SafeSetShown(uf.level, visible)
    SafeSetShown(uf.LevelFrame, visible)
    SafeSetShown(uf.highLevelTexture, visible)
    SafeSetShown(uf.classificationIndicator, visible)

    local subFS = customSubtitles[uf]
    ToggleFrameTreeExtras(uf, nameFS, subFS, visible, 0)

    local parent = uf:GetParent()
    if parent and not (parent.IsForbidden and parent:IsForbidden()) then
        ToggleFrameTreeExtras(parent, nameFS, subFS, visible, 0)
    end
end

-- Create or update the custom NPC Title / Minion Owner subtitle FontString below the unit name
local function ApplySubtitle(uf, nameFS, showSubtitle, subtitleText, color)
    local subFS = customSubtitles[uf]
    if not showSubtitle or not IsSafeString(subtitleText) then
        if subFS then
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
        subFS:SetFont(fontPath, math.max(fontSize - 2, 8), fontFlags or "")
    end

    subFS:ClearAllPoints()
    subFS:SetPoint("TOP", nameFS, "BOTTOM", 0, -1)
    subFS:SetText(subtitleText)
    if color then
        subFS:SetTextColor(color.r, color.g, color.b, 1)
    else
        subFS:SetTextColor(1.0, 0.82, 0.0, 1)
    end
    subFS:Show()
end

-- Hook a FontString so Blizzard SetText / SetTextColor calls cannot overwrite our custom name color
local function EnsureNameFontStringHooked(uf, nameFS)
    if not nameFS or hookedWidgets[nameFS] then return end
    hookedWidgets[nameFS] = true

    local function ReapplyOnBlizzardChange()
        if uf._fncUpdating then return end
        if not ForeverNamePlateColorsDB or not ForeverNamePlateColorsDB.enabled then return end
        local unit = uf.displayedUnit or uf.unit
        if IsSafeString(unit) and unit:match("^nameplate%d+$") then
            FNC:UpdateUnitFrame(uf, unit)
        end
    end

    hooksecurefunc(nameFS, "SetTextColor", ReapplyOnBlizzardChange)
    hooksecurefunc(nameFS, "SetText", ReapplyOnBlizzardChange)
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
            if uf._fncUpdating then return end
            if not ForeverNamePlateColorsDB or not ForeverNamePlateColorsDB.enabled then return end
            local unit = uf.displayedUnit or uf.unit
            if IsSafeString(unit) and unit:match("^nameplate%d+$") then
                FNC:UpdateUnitFrame(uf, unit)
            end
        end)
    end

    if uf.HealthBarsContainer and uf.HealthBarsContainer.Show and not hookedWidgets[uf.HealthBarsContainer] then
        hookedWidgets[uf.HealthBarsContainer] = true
        hooksecurefunc(uf.HealthBarsContainer, "Show", function()
            if uf._fncUpdating then return end
            if not ForeverNamePlateColorsDB or not ForeverNamePlateColorsDB.enabled then return end
            local unit = uf.displayedUnit or uf.unit
            if IsSafeString(unit) and unit:match("^nameplate%d+$") then
                FNC:UpdateUnitFrame(uf, unit)
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
        local orig = defaultNameColors[nameFS]
        if orig then
            nameFS:SetTextColor(orig.r, orig.g, orig.b, orig.a or 1)
        end
    end

    if customSubtitles[uf] then
        customSubtitles[uf]:Hide()
    end

    uf._fncUpdating = false
end

-- Core UnitFrame styling routine
function FNC:UpdateUnitFrame(uf, unit)
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
    local isSubgroup = isUnitPlayer and FNC.IsInMySubgroup(unit) or false
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

    if matchedCfg.key == "FriendlyMinion" and matchedCat.subCategories then
        local subKey = FNC.ResolveFriendlyMinionSubKey(unit)
        if subKey and matchedCat.subCategories[subKey] and matchedCat.subCategories[subKey].enabled then
            activeStyle = matchedCat.subCategories[subKey]
            subtitleEnabled = subtitleEnabled and (activeStyle.subtitleEnabled ~= false)
        end
    end

    local hb = GetUnitFrameHealthBar(uf)
    local nameFS = GetUnitFrameNameText(uf)

    if nameFS and not defaultNameColors[nameFS] then
        local r, g, b, a = nameFS:GetTextColor()
        if IsSafeNumber(r) and IsSafeNumber(g) and IsSafeNumber(b) then
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

        if activeStyle.nameEnabled and activeStyle.colorName then
            local c = activeStyle.colorName
            nameFS:SetTextColor(c.r, c.g, c.b, 1)
        else
            local orig = defaultNameColors[nameFS]
            if orig then
                nameFS:SetTextColor(orig.r, orig.g, orig.b, orig.a or 1)
            end
        end
    end

    -- Apply NPC Title or Minion Owner subtitle
    local hasSubtitleCapable = matchedCfg.hasSubtitleOption or (matchedCfg.key == "ActiveQuestUnit" and (not canAttack))
    if nameFS and hasSubtitleCapable then
        if subtitleEnabled then
            local subText = FNC:GetNPCSubtitle(unit)
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

local function OnCompactUnitFrameHook(uf)
    if not uf or uf._fncUpdating or (uf.IsForbidden and uf:IsForbidden()) then return end
    local unit = uf.displayedUnit or uf.unit
    if IsSafeString(unit) and unit:match("^nameplate%d+$") then
        HookUnitFrame(uf)
        FNC:UpdateUnitFrame(uf, unit)
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

-- Refresh or reset all active nameplates on screen
function FNC:RefreshAllPlates()
    if FNC.SyncAllCVars then
        FNC:SyncAllCVars()
    end
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local uf = plate.UnitFrame or plate.unitFrame
        if uf and not uf:IsForbidden() then
            HookUnitFrame(uf)
            self:ResetUnitFrame(uf)
            if CompactUnitFrame_UpdateHealthColor then pcall(CompactUnitFrame_UpdateHealthColor, uf) end
            if CompactUnitFrame_UpdateName then pcall(CompactUnitFrame_UpdateName, uf) end
            local unit = uf.displayedUnit or uf.unit
            if IsSafeString(unit) then
                self:UpdateUnitFrame(uf, unit)
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