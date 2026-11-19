--------------------------------------------------------------------------------
-- ForeverNamePlateColors.lua
-- Categorized Nameplate & Health Bar Color Customizer for Classic Era
--------------------------------------------------------------------------------

local addonName, addonTable = ...
local FNC = CreateFrame("Frame", "ForeverNamePlateColorsMainFrame", UIParent)

-- Category Definitions (single source of truth)
-- Future categories can simply be appended to this table.
local CATEGORY_CONFIG = {
    {
        key = "Party",
        label = "Party (Subgroup)",
        defaultHealth = { r = 0.6392, g = 0.6431, b = 1.0 },
        defaultName   = { r = 1.0,    g = 1.0,    b = 1.0 },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack)
            return isSubgroup
        end,
    },
    {
        key = "Raid",
        label = "Raid (Other Subgroups)",
        defaultHealth = { r = 0.3961, g = 0.3686, b = 1.0 },
        defaultName   = { r = 1.0,    g = 1.0,    b = 1.0 },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack)
            return (not isSubgroup) and isRaidMember
        end,
    },
    {
        key = "Hostile",
        label = "Hostile Faction",
        defaultHealth = { r = 1.0, g = 0.0, b = 0.0 },
        defaultName   = { r = 1.0, g = 1.0, b = 1.0 },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack)
            return isUnitPlayer and isEnemy
        end,
    },
    {
        key = "FriendlyPlayer",
        label = "Faction Member",
        defaultHealth = { r = 0.3961, g = 0.3686, b = 1.0 },
        defaultName   = { r = 1.0,    g = 1.0,    b = 1.0 },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack)
            return isUnitPlayer and (not isEnemy)
        end,
    },
    {
        key = "Enemy",
        label = "Enemy Mob",
        defaultHealth = { r = 1.0, g = 0.0, b = 0.0 },
        defaultName   = { r = 1.0, g = 1.0, b = 1.0 },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack)
            return canAttack and (not isUnitPlayer)
        end,
    },
    {
        key = "NPC",
        label = "Quest NPC",
        defaultHealth = nil, -- Resolved dynamically via FACTION_BAR_COLORS or fallback green
        defaultName   = { r = 1.0, g = 1.0, b = 1.0 },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack)
            return (not canAttack) and (not isUnitPlayer)
        end,
    },
}

local function GetDefaultHealth(cfg)
    if cfg.defaultHealth then
        return { r = cfg.defaultHealth.r, g = cfg.defaultHealth.g, b = cfg.defaultHealth.b }
    end
    local defaultNPCCol = (FACTION_BAR_COLORS and FACTION_BAR_COLORS[5]) or { r = 0.0, g = 1.0, b = 0.0 }
    return { r = defaultNPCCol.r, g = defaultNPCCol.g, b = defaultNPCCol.b }
end

-- Migration mapping from legacy flat keys
local LEGACY_KEY_MAP = {
    Party          = { health = "colorParty",          name = "colorPartyName" },
    Raid           = { health = "colorRaid",           name = "colorRaidName" },
    FriendlyPlayer = { health = "colorFriendlyPlayer", name = "colorFriendlyPlayerName" },
    Hostile        = { health = "colorHostile",        name = "colorHostileName" },
    Enemy          = { health = "colorEnemy",          name = "colorEnemyName" },
    NPC            = { health = "colorNPC",            name = "colorNPCName" },
}

local function MigrateDB(db)
    if not db.colorParty and not db.colorEnemy then return end

    db.categories = db.categories or {}
    for catKey, legacyKeys in pairs(LEGACY_KEY_MAP) do
        local oldHealth = db[legacyKeys.health]
        local oldName = db[legacyKeys.name]
        if oldHealth or oldName then
            db.categories[catKey] = db.categories[catKey] or {}
            local cat = db.categories[catKey]
            if cat.enabled == nil then cat.enabled = true end
            if cat.healthEnabled == nil then cat.healthEnabled = true end
            if cat.nameEnabled == nil then cat.nameEnabled = true end
            if oldHealth then
                cat.colorHealth = { r = oldHealth.r, g = oldHealth.g, b = oldHealth.b }
            end
            if oldName then
                cat.colorName = { r = oldName.r, g = oldName.g, b = oldName.b }
            end
            db[legacyKeys.health] = nil
            db[legacyKeys.name] = nil
        end
    end
    print("|cFF00FFCCForeverNamePlateColors|r Settings migrated to v1.3.0 format.")
end

local function EnsureDefaults(db)
    if db.enabled == nil then db.enabled = true end
    db.categories = db.categories or {}

    for _, cfg in ipairs(CATEGORY_CONFIG) do
        local cat = db.categories[cfg.key] or {}
        if cat.enabled == nil then cat.enabled = true end
        if cat.healthEnabled == nil then cat.healthEnabled = true end
        if cat.nameEnabled == nil then cat.nameEnabled = true end
        if not cat.colorHealth then
            cat.colorHealth = GetDefaultHealth(cfg)
        end
        if not cat.colorName then
            cat.colorName = { r = cfg.defaultName.r, g = cfg.defaultName.g, b = cfg.defaultName.b }
        end
        db.categories[cfg.key] = cat
    end
end

-- Initialize SavedVariables table if already present in memory
ForeverNamePlateColorsDB = ForeverNamePlateColorsDB or {}
MigrateDB(ForeverNamePlateColorsDB)
EnsureDefaults(ForeverNamePlateColorsDB)

FNC:RegisterEvent("ADDON_LOADED")
FNC:RegisterEvent("NAME_PLATE_UNIT_ADDED")
FNC:RegisterEvent("GROUP_ROSTER_UPDATE")

FNC:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        MigrateDB(ForeverNamePlateColorsDB)
        EnsureDefaults(ForeverNamePlateColorsDB)
        FNC:UpdateConfigPanelUI()
        print("|cFF00FFCCForeverNamePlateColors|r v1.3.0 loaded successfully. Type |cFFFFFFFF/fnc|r to open options.")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = arg1
        if unit then
            local plate = C_NamePlate.GetNamePlateForUnit(unit)
            if plate then
                local uf = plate.UnitFrame or plate.unitFrame
                if uf and not uf:IsForbidden() then
                    self:UpdateUnitFrame(uf, unit)
                end
            end
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        FNC:RefreshAllPlates()
    end
end)

-- Hook into Blizzard's internal update functions so colors persist
if CompactUnitFrame_UpdateHealthColor then
    hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame)
        if frame and frame.unit then
            FNC:UpdateUnitFrame(frame, frame.unit)
        end
    end)
end

if CompactUnitFrame_UpdateName then
    hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
        if frame and frame.unit then
            FNC:UpdateUnitFrame(frame, frame.unit)
        end
    end)
end

-- Subgroup Check using UnitInRaid index lookup
local function IsInMySubgroup(unit)
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

function FNC:UpdateUnitFrame(uf, unit)
    if not ForeverNamePlateColorsDB.enabled then return end
    if not uf or uf:IsForbidden() then return end
    if not unit then return end

    local isSubgroup = IsInMySubgroup(unit)
    local isRaidMember = UnitInRaid(unit) ~= nil
    local isUnitPlayer = UnitIsPlayer(unit)
    local isEnemy = UnitIsEnemy("player", unit)
    local canAttack = UnitCanAttack("player", unit)

    for _, cfg in ipairs(CATEGORY_CONFIG) do
        if cfg.match(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack) then
            local cat = ForeverNamePlateColorsDB.categories and ForeverNamePlateColorsDB.categories[cfg.key]
            if not cat or not cat.enabled then
                return -- Category coloring disabled: Blizzard default runs
            end

            if cat.healthEnabled and cat.colorHealth then
                local hb = uf.healthBar or uf.HealthBar
                if hb then
                    hb:SetStatusBarColor(cat.colorHealth.r, cat.colorHealth.g, cat.colorHealth.b)
                end
            end

            if cat.nameEnabled and cat.colorName then
                local nameText = uf.name or uf.Name
                if nameText then
                    nameText:SetTextColor(cat.colorName.r, cat.colorName.g, cat.colorName.b)
                end
            end

            return
        end
    end
end

function FNC:ResetAllPlates()
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local uf = plate.UnitFrame or plate.unitFrame
        if uf and not uf:IsForbidden() and uf.unit then
            if CompactUnitFrame_UpdateHealthColor then CompactUnitFrame_UpdateHealthColor(uf) end
            if CompactUnitFrame_UpdateName then CompactUnitFrame_UpdateName(uf) end
        end
    end
end

function FNC:RefreshAllPlates()
    if not ForeverNamePlateColorsDB.enabled then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local uf = plate.UnitFrame or plate.unitFrame
        if uf and not uf:IsForbidden() and uf.unit then
            -- Reset to Blizzard defaults first so un-checked channels cleanly revert
            if CompactUnitFrame_UpdateHealthColor then CompactUnitFrame_UpdateHealthColor(uf) end
            if CompactUnitFrame_UpdateName then CompactUnitFrame_UpdateName(uf) end
            self:UpdateUnitFrame(uf, uf.unit)
        end
    end
end

-- Helper: Add Blizzard GameTooltip to interactive elements
local function SetTooltip(frame, text)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- Options Panel Setup
local configFrame = CreateFrame("Frame", "FNCConfigPanel", UIParent)
configFrame.name = "ForeverNamePlateColors"
configFrame:SetSize(620, 520)

local title = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("ForeverNamePlateColors Options")

-- Global Settings Box
local globalBox = CreateFrame("Frame", nil, configFrame, "BackdropTemplate")
globalBox:SetSize(580, 74)
globalBox:SetPoint("TOPLEFT", 16, -45)
globalBox:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
})
globalBox:SetBackdropColor(0.08, 0.08, 0.08, 0.85)
globalBox:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

local enableCB = CreateFrame("CheckButton", nil, globalBox, "InterfaceOptionsCheckButtonTemplate")
enableCB:SetPoint("TOPLEFT", 10, -6)
enableCB.Text:SetText("Enable Addon")
SetTooltip(enableCB, "Master toggle for ForeverNamePlateColors.\nWhen unchecked, all nameplates revert to Blizzard defaults.")

enableCB:SetScript("OnClick", function(self)
    ForeverNamePlateColorsDB.enabled = self:GetChecked()
    FNC:UpdateConfigPanelUI()
    if ForeverNamePlateColorsDB.enabled then
        FNC:RefreshAllPlates()
    else
        FNC:ResetAllPlates()
    end
end)

local matchBtn = CreateFrame("Button", nil, globalBox, "UIPanelButtonTemplate")
matchBtn:SetSize(210, 22)
matchBtn:SetPoint("BOTTOMLEFT", 10, 8)
matchBtn:SetText("Match Name to Health Colors")
SetTooltip(matchBtn, "One-click action to copy every category's health bar color to its name color.\nYou can still customize individual name colors afterwards.")

matchBtn:SetScript("OnClick", function()
    local db = ForeverNamePlateColorsDB
    if not db or not db.categories then return end
    for _, cfg in ipairs(CATEGORY_CONFIG) do
        local cat = db.categories[cfg.key]
        if cat and cat.colorHealth then
            cat.colorName = { r = cat.colorHealth.r, g = cat.colorHealth.g, b = cat.colorHealth.b }
        end
    end
    FNC:UpdateConfigPanelUI()
    FNC:RefreshAllPlates()
    print("|cFF00FFCCForeverNamePlateColors|r All name colors matched to their health colors.")
end)

local enableAllBtn = CreateFrame("Button", nil, globalBox, "UIPanelButtonTemplate")
enableAllBtn:SetSize(145, 22)
enableAllBtn:SetPoint("LEFT", matchBtn, "RIGHT", 10, 0)
enableAllBtn:SetText("Enable All Categories")
SetTooltip(enableAllBtn, "Enable color overrides across all categories.\nDoes not change your individual health/name channel settings.")

enableAllBtn:SetScript("OnClick", function()
    local db = ForeverNamePlateColorsDB
    if not db or not db.categories then return end
    for _, cfg in ipairs(CATEGORY_CONFIG) do
        local cat = db.categories[cfg.key]
        if cat then cat.enabled = true end
    end
    FNC:UpdateConfigPanelUI()
    FNC:RefreshAllPlates()
    print("|cFF00FFCCForeverNamePlateColors|r All categories enabled.")
end)

local disableAllBtn = CreateFrame("Button", nil, globalBox, "UIPanelButtonTemplate")
disableAllBtn:SetSize(145, 22)
disableAllBtn:SetPoint("LEFT", enableAllBtn, "RIGHT", 10, 0)
disableAllBtn:SetText("Disable All Categories")
SetTooltip(disableAllBtn, "Disable color overrides across all categories.\nGreys out all category controls and restores Blizzard defaults.")

disableAllBtn:SetScript("OnClick", function()
    local db = ForeverNamePlateColorsDB
    if not db or not db.categories then return end
    for _, cfg in ipairs(CATEGORY_CONFIG) do
        local cat = db.categories[cfg.key]
        if cat then cat.enabled = false end
    end
    FNC:UpdateConfigPanelUI()
    FNC:RefreshAllPlates()
    print("|cFF00FFCCForeverNamePlateColors|r All categories disabled.")
end)

-- Category Card Builder (Option C)
FNC.categoryCards = {}

local function CreateCategoryCard(parent, cfg, yOffset)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetSize(580, 54)
    card:SetPoint("TOPLEFT", 16, yOffset)
    card:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    card:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    card:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    -- Row 1: Category Title and Master Enabled Checkbox
    local titleStr = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleStr:SetPoint("TOPLEFT", 12, -8)
    titleStr:SetText(cfg.label)

    local enabledCB = CreateFrame("CheckButton", nil, card, "InterfaceOptionsCheckButtonTemplate")
    enabledCB:SetPoint("LEFT", titleStr, "RIGHT", 14, 0)
    enabledCB.Text:SetText("Enabled")
    SetTooltip(enabledCB, "Enable or disable color overrides for " .. cfg.label .. ".\nWhen unchecked, Blizzard defaults are used.")

    -- Row 2: Health Checkbox + Button, Name Checkbox + Button, Reset Button
    local healthCB = CreateFrame("CheckButton", nil, card, "InterfaceOptionsCheckButtonTemplate")
    healthCB:SetPoint("BOTTOMLEFT", 10, 6)
    SetTooltip(healthCB, "Toggle custom health bar color for " .. cfg.label .. ".\nWhen unchecked, Blizzard default health color is used.")

    local healthBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    healthBtn:SetSize(125, 20)
    healthBtn:SetPoint("LEFT", healthCB, "RIGHT", 2, 0)
    healthBtn:SetText("Health Color")
    local healthSwatch = healthBtn:CreateTexture(nil, "OVERLAY")
    healthSwatch:SetSize(14, 14)
    healthSwatch:SetPoint("RIGHT", healthBtn, "RIGHT", -6, 0)
    healthBtn.swatch = healthSwatch

    local nameCB = CreateFrame("CheckButton", nil, card, "InterfaceOptionsCheckButtonTemplate")
    nameCB:SetPoint("LEFT", healthBtn, "RIGHT", 14, 0)
    SetTooltip(nameCB, "Toggle custom name text color for " .. cfg.label .. ".\nWhen unchecked, Blizzard default name color is used.")

    local nameBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    nameBtn:SetSize(125, 20)
    nameBtn:SetPoint("LEFT", nameCB, "RIGHT", 2, 0)
    nameBtn:SetText("Name Color")
    local nameSwatch = nameBtn:CreateTexture(nil, "OVERLAY")
    nameSwatch:SetSize(14, 14)
    nameSwatch:SetPoint("RIGHT", nameBtn, "RIGHT", -6, 0)
    nameBtn.swatch = nameSwatch

    local resetBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    resetBtn:SetSize(70, 20)
    resetBtn:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -8, 6)
    resetBtn:SetText("Reset")
    SetTooltip(resetBtn, "Reset " .. cfg.label .. " to default colors and re-enable both health and name overrides.")

    -- Attach references for easy access
    card.cfg = cfg
    card.titleStr = titleStr
    card.enabledCB = enabledCB
    card.healthCB = healthCB
    card.healthBtn = healthBtn
    card.nameCB = nameCB
    card.nameBtn = nameBtn
    card.resetBtn = resetBtn

    enabledCB:SetScript("OnClick", function(self)
        local cat = ForeverNamePlateColorsDB.categories[cfg.key]
        if cat then
            cat.enabled = self:GetChecked()
            FNC:UpdateConfigPanelUI()
            FNC:RefreshAllPlates()
        end
    end)

    healthCB:SetScript("OnClick", function(self)
        local cat = ForeverNamePlateColorsDB.categories[cfg.key]
        if cat then
            cat.healthEnabled = self:GetChecked()
            FNC:UpdateConfigPanelUI()
            FNC:RefreshAllPlates()
        end
    end)

    nameCB:SetScript("OnClick", function(self)
        local cat = ForeverNamePlateColorsDB.categories[cfg.key]
        if cat then
            cat.nameEnabled = self:GetChecked()
            FNC:UpdateConfigPanelUI()
            FNC:RefreshAllPlates()
        end
    end)

    healthBtn:SetScript("OnClick", function()
        FNC:OpenColorPicker(cfg.key, "health", healthSwatch)
    end)

    nameBtn:SetScript("OnClick", function()
        FNC:OpenColorPicker(cfg.key, "name", nameSwatch)
    end)

    resetBtn:SetScript("OnClick", function()
        local cat = ForeverNamePlateColorsDB.categories[cfg.key]
        if cat then
            cat.enabled = true
            cat.healthEnabled = true
            cat.nameEnabled = true
            cat.colorHealth = GetDefaultHealth(cfg)
            cat.colorName = { r = 1.0, g = 1.0, b = 1.0 }
            FNC:UpdateConfigPanelUI()
            FNC:RefreshAllPlates()
            print(string.format("|cFF00FFCCForeverNamePlateColors|r Reset %s to defaults.", cfg.label))
        end
    end)

    table.insert(FNC.categoryCards, card)
    return card
end

-- Instantiate Category Cards sequentially
local cardY = -128
for _, cfg in ipairs(CATEGORY_CONFIG) do
    CreateCategoryCard(configFrame, cfg, cardY)
    cardY = cardY - 60
end

function FNC:UpdateConfigPanelUI()
    if not configFrame then return end
    enableCB:SetChecked(ForeverNamePlateColorsDB.enabled)

    for _, card in ipairs(FNC.categoryCards) do
        local cfg = card.cfg
        local cat = ForeverNamePlateColorsDB.categories and ForeverNamePlateColorsDB.categories[cfg.key]
        if cat then
            card.enabledCB:SetChecked(cat.enabled)
            card.healthCB:SetChecked(cat.healthEnabled)
            card.nameCB:SetChecked(cat.nameEnabled)

            if cat.colorHealth then
                card.healthBtn.swatch:SetColorTexture(cat.colorHealth.r, cat.colorHealth.g, cat.colorHealth.b)
            end
            if cat.colorName then
                card.nameBtn.swatch:SetColorTexture(cat.colorName.r, cat.colorName.g, cat.colorName.b)
            end

            -- Visual Grey-out logic
            if not cat.enabled then
                card:SetAlpha(0.4)
                card.healthCB:SetEnabled(false)
                card.nameCB:SetEnabled(false)
                card.healthBtn:SetEnabled(false)
                card.nameBtn:SetEnabled(false)
                card.resetBtn:SetEnabled(false)
                card.healthBtn:SetAlpha(0.4)
                card.nameBtn:SetAlpha(0.4)
            else
                card:SetAlpha(1.0)
                card.healthCB:SetEnabled(true)
                card.nameCB:SetEnabled(true)
                card.resetBtn:SetEnabled(true)

                card.healthBtn:SetEnabled(cat.healthEnabled)
                card.healthBtn:SetAlpha(cat.healthEnabled and 1.0 or 0.4)

                card.nameBtn:SetEnabled(cat.nameEnabled)
                card.nameBtn:SetAlpha(cat.nameEnabled and 1.0 or 0.4)
            end
        end
    end
end

configFrame:SetScript("OnShow", function()
    FNC:UpdateConfigPanelUI()
end)

if Settings and Settings.RegisterCanvasLayoutCategory then
    local category, layout = Settings.RegisterCanvasLayoutCategory(configFrame, "ForeverNamePlateColors")
    Settings.RegisterAddOnCategory(category)
    FNC.settingsCategory = category
else
    InterfaceOptions_AddCategory(configFrame)
end

function FNC:OpenColorPicker(catKey, channel, swatchTexture)
    local cat = ForeverNamePlateColorsDB.categories and ForeverNamePlateColorsDB.categories[catKey]
    if not cat then return end
    local colorField = (channel == "health") and "colorHealth" or "colorName"
    if not cat[colorField] then
        cat[colorField] = { r = 1, g = 1, b = 1 }
    end

    local col = cat[colorField]
    local prevR, prevG, prevB = col.r, col.g, col.b

    local function ApplyColor(r, g, b)
        col.r, col.g, col.b = r, g, b
        if swatchTexture then
            swatchTexture:SetColorTexture(r, g, b)
        end
        FNC:UpdateConfigPanelUI()
        FNC:RefreshAllPlates()
    end

    if ColorPickerFrame.SetupColorPickerAndShow then
        local info = {
            r = col.r,
            g = col.g,
            b = col.b,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                ApplyColor(r, g, b)
            end,
            func = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                ApplyColor(r, g, b)
                ColorPickerFrame:Hide()
            end,
            cancelFunc = function()
                ApplyColor(prevR, prevG, prevB)
                ColorPickerFrame:Hide()
            end,
            hasOpacity = false,
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
    else
        ColorPickerFrame:SetColorRGB(col.r, col.g, col.b)
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.swatchFunc = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            ApplyColor(r, g, b)
        end
        ColorPickerFrame.func = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            ApplyColor(r, g, b)
            ColorPickerFrame:Hide()
        end
        ColorPickerFrame.cancelFunc = function()
            ApplyColor(prevR, prevG, prevB)
            ColorPickerFrame:Hide()
        end
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end

-- Slash Command Handler
SlashCmdList["FOREVERNAMEPLATECOLORS"] = function(msg)
    msg = string.lower(strtrim(msg or ""))
    if msg == "toggle" then
        ForeverNamePlateColorsDB.enabled = not ForeverNamePlateColorsDB.enabled
        print("|cFF00FFCCForeverNamePlateColors|r Enabled: " .. tostring(ForeverNamePlateColorsDB.enabled))
        if ForeverNamePlateColorsDB.enabled then
            FNC:RefreshAllPlates()
        else
            FNC:ResetAllPlates()
        end
        FNC:UpdateConfigPanelUI()
    else
        if Settings and Settings.OpenToCategory and FNC.settingsCategory then
            Settings.OpenToCategory(FNC.settingsCategory.ID)
        else
            InterfaceOptionsFrame_OpenToCategory(configFrame)
        end
    end
end
SLASH_FOREVERNAMEPLATECOLORS1 = "/fnc"
SLASH_FOREVERNAMEPLATECOLORS2 = "/forevernameplatecolors"
