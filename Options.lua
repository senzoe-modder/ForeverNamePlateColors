--------------------------------------------------------------------------------
-- Options.lua
-- Lazy-Loaded Blizzard Settings Canvas, Category Cards, & Color Picker
--------------------------------------------------------------------------------

local addonName, FNC = ...

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

-- Register lightweight shell frame at load time; build heavy cards lazily on first OnShow
local configFrame = CreateFrame("Frame", "FNCConfigPanel", UIParent)
configFrame.name = "ForeverNamePlateColors"
configFrame:SetSize(620, 520)
FNC.configFrame = configFrame

FNC.categoryCards = {}
FNC.cardsByKey = {}
FNC.sectionHeaders = {}
FNC.headersByGroup = {}

local uiBuilt = false
local scrollChild, enableCB, matchBtn, enableAllBtn, disableAllBtn

local function CreateSectionHeader(parent, groupKey, label)
    local header = CreateFrame("Frame", nil, parent)
    header:SetSize(560, 22)

    local text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("LEFT", 4, 0)
    text:SetText(label)

    local line = header:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("LEFT", text, "RIGHT", 10, 0)
    line:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    line:SetColorTexture(0.5, 0.5, 0.5, 0.5)

    table.insert(FNC.sectionHeaders, header)
    FNC.headersByGroup[groupKey] = header
    return header
end

local function CreateSubCategoryRow(parent, parentCfg, subCfg, yOffset)
    local rowHeight = 50
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetSize(540, rowHeight)
    row:SetPoint("TOPLEFT", 0, yOffset)
    row:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    row:SetBackdropColor(0.06, 0.06, 0.06, 0.9)
    row:SetBackdropBorderColor(0.32, 0.32, 0.32, 1)

    -- Line 1: Sub-category Title + Enabled Checkbox
    local titleStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleStr:SetPoint("TOPLEFT", 10, -7)
    titleStr:SetText(subCfg.label)

    local enabledCB = CreateFrame("CheckButton", nil, row, "InterfaceOptionsCheckButtonTemplate")
    enabledCB:SetSize(22, 22)
    enabledCB:SetPoint("LEFT", titleStr, "RIGHT", 10, 0)
    enabledCB.Text:SetFontObject("GameFontHighlightSmall")
    enabledCB.Text:SetText("Enabled")
    SetTooltip(enabledCB, subCfg.tooltip or ("Enable color overrides for " .. subCfg.label .. "."))

    -- Line 2: Health Checkbox + Swatch, Name Checkbox + Swatch, Tag Checkbox + Swatch, Reset
    local healthCB = CreateFrame("CheckButton", nil, row, "InterfaceOptionsCheckButtonTemplate")
    healthCB:SetSize(22, 22)
    healthCB:SetPoint("BOTTOMLEFT", 8, 3)
    SetTooltip(healthCB, "Toggle custom health bar color for " .. subCfg.label .. ".")

    local healthBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    healthBtn:SetSize(112, 18)
    healthBtn:SetPoint("LEFT", healthCB, "RIGHT", 1, 0)
    healthBtn:SetText("Health Color")
    local healthSwatch = healthBtn:CreateTexture(nil, "OVERLAY")
    healthSwatch:SetSize(12, 12)
    healthSwatch:SetPoint("RIGHT", healthBtn, "RIGHT", -5, 0)
    healthBtn.swatch = healthSwatch

    local nameCB = CreateFrame("CheckButton", nil, row, "InterfaceOptionsCheckButtonTemplate")
    nameCB:SetSize(22, 22)
    nameCB:SetPoint("LEFT", healthBtn, "RIGHT", 10, 0)
    SetTooltip(nameCB, "Toggle custom name text color for " .. subCfg.label .. ".")

    local nameBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    nameBtn:SetSize(106, 18)
    nameBtn:SetPoint("LEFT", nameCB, "RIGHT", 1, 0)
    nameBtn:SetText("Name Color")
    local nameSwatch = nameBtn:CreateTexture(nil, "OVERLAY")
    nameSwatch:SetSize(12, 12)
    nameSwatch:SetPoint("RIGHT", nameBtn, "RIGHT", -5, 0)
    nameBtn.swatch = nameSwatch

    local subtitleCB = CreateFrame("CheckButton", nil, row, "InterfaceOptionsCheckButtonTemplate")
    subtitleCB:SetSize(22, 22)
    subtitleCB:SetPoint("LEFT", nameBtn, "RIGHT", 10, 0)
    SetTooltip(subtitleCB, "Toggle custom owner tag color for " .. subCfg.label .. ".\nRequires Show Owner Tag to be enabled above.")

    local subtitleBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    subtitleBtn:SetSize(100, 18)
    subtitleBtn:SetPoint("LEFT", subtitleCB, "RIGHT", 1, 0)
    subtitleBtn:SetText("Tag Color")
    local subtitleSwatch = subtitleBtn:CreateTexture(nil, "OVERLAY")
    subtitleSwatch:SetSize(12, 12)
    subtitleSwatch:SetPoint("RIGHT", subtitleBtn, "RIGHT", -5, 0)
    subtitleBtn.swatch = subtitleSwatch

    local resetBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    resetBtn:SetSize(56, 18)
    resetBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 4)
    resetBtn:SetText("Reset")
    SetTooltip(resetBtn, "Reset " .. subCfg.label .. " to default colors and settings.")

    row.subCfg = subCfg
    row.rowHeight = rowHeight
    row.enabledCB = enabledCB
    row.healthCB = healthCB
    row.healthBtn = healthBtn
    row.nameCB = nameCB
    row.nameBtn = nameBtn
    row.subtitleCB = subtitleCB
    row.subtitleBtn = subtitleBtn
    row.resetBtn = resetBtn

    local function GetSubCat()
        local parentCat = ForeverNamePlateColorsDB.categories and ForeverNamePlateColorsDB.categories[parentCfg.key]
        return parentCat and parentCat.subCategories and parentCat.subCategories[subCfg.key]
    end

    enabledCB:SetScript("OnClick", function(self)
        local subCat = GetSubCat()
        if subCat then
            subCat.enabled = self:GetChecked()
            FNC:UpdateConfigPanelUI()
            FNC:RefreshAllPlates()
        end
    end)

    healthCB:SetScript("OnClick", function(self)
        local subCat = GetSubCat()
        if subCat then
            subCat.healthEnabled = self:GetChecked()
            FNC:UpdateConfigPanelUI()
            FNC:RefreshAllPlates()
        end
    end)

    nameCB:SetScript("OnClick", function(self)
        local subCat = GetSubCat()
        if subCat then
            subCat.nameEnabled = self:GetChecked()
            FNC:UpdateConfigPanelUI()
            FNC:RefreshAllPlates()
        end
    end)

    subtitleCB:SetScript("OnClick", function(self)
        local subCat = GetSubCat()
        if subCat then
            subCat.subtitleEnabled = self:GetChecked()
            FNC:UpdateConfigPanelUI()
            FNC:RefreshAllPlates()
        end
    end)

    healthBtn:SetScript("OnClick", function()
        FNC:OpenColorPicker(parentCfg.key, "health", healthSwatch, subCfg.key)
    end)

    nameBtn:SetScript("OnClick", function()
        FNC:OpenColorPicker(parentCfg.key, "name", nameSwatch, subCfg.key)
    end)

    subtitleBtn:SetScript("OnClick", function()
        FNC:OpenColorPicker(parentCfg.key, "subtitle", subtitleSwatch, subCfg.key)
    end)

    resetBtn:SetScript("OnClick", function()
        local subCat = GetSubCat()
        if subCat then
            subCat.enabled = (subCfg.defaultEnabled ~= nil) and subCfg.defaultEnabled or false
            subCat.healthEnabled = true
            subCat.nameEnabled = true
            subCat.subtitleEnabled = true
            subCat.colorHealth = FNC.GetDefaultHealth(subCfg)
            subCat.colorName = { r = subCfg.defaultName.r, g = subCfg.defaultName.g, b = subCfg.defaultName.b }
            subCat.colorSubtitle = FNC.GetDefaultSubtitle(subCfg)
            FNC:UpdateConfigPanelUI()
            FNC:RefreshAllPlates()
            print(string.format("|cFF00FFCCForeverNamePlateColors|r Reset %s to defaults.", subCfg.label))
        end
    end)

    return row
end

local function CreateCategoryCard(parent, cfg)
    local baseHeight = (cfg.hasHealthBarOption or cfg.hasSubtitleOption) and 78 or 54
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetSize(560, baseHeight)
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
    local enabledTooltip = cfg.enabledTooltip or ("Enable or disable color overrides for " .. cfg.label .. ".\nWhen unchecked, Blizzard defaults are used.")
    if not cfg.enabledTooltip and cfg.cvarSync then
        enabledTooltip = enabledTooltip .. "\nAlso synchronizes Blizzard nameplate visibility for this category."
    end
    SetTooltip(enabledCB, enabledTooltip)

    -- Optional Advanced Drawer Toggle Button on Row 1
    if cfg.subCategories then
        local advancedBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
        advancedBtn:SetSize(115, 20)
        advancedBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -6)
        advancedBtn:SetText("Show Advanced")
        SetTooltip(advancedBtn, "Expand or collapse granular overrides for Personal Minion, Party Minion (Subgroup), and Raid Minion (Other Subgroups).")
        card.advancedBtn = advancedBtn

        advancedBtn:SetScript("OnClick", function()
            local cat = ForeverNamePlateColorsDB.categories and ForeverNamePlateColorsDB.categories[cfg.key]
            if cat then
                cat.advancedExpanded = not cat.advancedExpanded
                FNC:UpdateConfigPanelUI()
            end
        end)
    end

    -- Row 2 (Optional Display Toggles): Show Health Bar, Show Subtitle/Owner Tag
    if cfg.hasHealthBarOption then
        local healthBarCB = CreateFrame("CheckButton", nil, card, "InterfaceOptionsCheckButtonTemplate")
        healthBarCB:SetPoint("TOPLEFT", 10, -28)
        healthBarCB.Text:SetText("Show Health Bar")
        SetTooltip(healthBarCB, "When unchecked, activates Headline Mode: hides the health bar and level text.\nWhen checked, displays the standard health bar.")
        card.healthBarCB = healthBarCB

        healthBarCB:SetScript("OnClick", function(self)
            local cat = ForeverNamePlateColorsDB.categories[cfg.key]
            if cat then
                cat.showHealthBar = self:GetChecked()
                FNC:UpdateConfigPanelUI()
                FNC:RefreshAllPlates()
            end
        end)
    end

    if cfg.hasSubtitleOption then
        local subtitleCB = CreateFrame("CheckButton", nil, card, "InterfaceOptionsCheckButtonTemplate")
        if card.healthBarCB then
            subtitleCB:SetPoint("LEFT", card.healthBarCB.Text, "RIGHT", 16, 0)
        else
            subtitleCB:SetPoint("TOPLEFT", 10, -28)
        end
        subtitleCB.Text:SetText(cfg.subtitleLabel or "Show Subtitle")
        SetTooltip(subtitleCB, cfg.subtitleTooltip or "Toggle displaying the unit's subtitle below their name.")
        card.subtitleCB = subtitleCB

        subtitleCB:SetScript("OnClick", function(self)
            local cat = ForeverNamePlateColorsDB.categories[cfg.key]
            if cat then
                cat.showSubtitle = self:GetChecked()
                FNC:UpdateConfigPanelUI()
                FNC:RefreshAllPlates()
            end
        end)
    end

    -- Row 3 (Base Category Color Channels): Health Color, Name Color, Optional Tag/Title Color, Reset Button
    local baseRowY = (cfg.hasHealthBarOption or cfg.hasSubtitleOption) and -54 or -30

    local healthCB = CreateFrame("CheckButton", nil, card, "InterfaceOptionsCheckButtonTemplate")
    healthCB:SetPoint("TOPLEFT", 10, baseRowY + 4)
    SetTooltip(healthCB, "Toggle custom health bar color for " .. cfg.label .. ".\nWhen unchecked, Blizzard default health color is used.")

    local healthBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    healthBtn:SetSize(120, 20)
    healthBtn:SetPoint("LEFT", healthCB, "RIGHT", 2, 0)
    healthBtn:SetText("Health Color")
    local healthSwatch = healthBtn:CreateTexture(nil, "OVERLAY")
    healthSwatch:SetSize(14, 14)
    healthSwatch:SetPoint("RIGHT", healthBtn, "RIGHT", -6, 0)
    healthBtn.swatch = healthSwatch

    local nameCB = CreateFrame("CheckButton", nil, card, "InterfaceOptionsCheckButtonTemplate")
    nameCB:SetPoint("LEFT", healthBtn, "RIGHT", 12, 0)
    SetTooltip(nameCB, "Toggle custom name text color for " .. cfg.label .. ".\nWhen unchecked, Blizzard default name color is used.")

    local nameBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    nameBtn:SetSize(120, 20)
    nameBtn:SetPoint("LEFT", nameCB, "RIGHT", 2, 0)
    nameBtn:SetText("Name Color")
    local nameSwatch = nameBtn:CreateTexture(nil, "OVERLAY")
    nameSwatch:SetSize(14, 14)
    nameSwatch:SetPoint("RIGHT", nameBtn, "RIGHT", -6, 0)
    nameBtn.swatch = nameSwatch

    if cfg.hasSubtitleOption then
        local subtitleBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
        subtitleBtn:SetSize(105, 20)
        subtitleBtn:SetPoint("LEFT", nameBtn, "RIGHT", 14, 0)
        subtitleBtn:SetText(cfg.subtitleButtonLabel or "Subtitle Color")
        SetTooltip(subtitleBtn, "Customize the color of " .. (cfg.subtitleLabel or "the subtitle") .. ".")
        local subtitleSwatch = subtitleBtn:CreateTexture(nil, "OVERLAY")
        subtitleSwatch:SetSize(14, 14)
        subtitleSwatch:SetPoint("RIGHT", subtitleBtn, "RIGHT", -6, 0)
        subtitleBtn.swatch = subtitleSwatch
        card.subtitleBtn = subtitleBtn

        subtitleBtn:SetScript("OnClick", function()
            FNC:OpenColorPicker(cfg.key, "subtitle", subtitleSwatch)
        end)
    end

    local resetBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    resetBtn:SetSize(65, 20)
    resetBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, baseRowY + 2)
    resetBtn:SetText("Reset")
    SetTooltip(resetBtn, "Reset " .. cfg.label .. " to default colors and settings.")

    -- Optional Expandable Advanced Container
    if cfg.subCategories then
        local advContainer = CreateFrame("Frame", nil, card)
        advContainer:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -baseHeight - 2)
        advContainer:SetWidth(540)
        advContainer:Hide()

        local subRows = {}
        local subY = 0
        for _, subCfg in ipairs(cfg.subCategories) do
            local row = CreateSubCategoryRow(advContainer, cfg, subCfg, subY)
            subY = subY - row.rowHeight - 4
            table.insert(subRows, row)
        end
        local advHeight = math.abs(subY) + 4
        advContainer:SetHeight(advHeight)

        card.advancedContainer = advContainer
        card.advancedHeight = advHeight
        card.subRows = subRows
    end

    -- Attach references for easy access
    card.cfg = cfg
    card.baseHeight = baseHeight
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
            if not cat.enabled and cfg.syncHealthBarWithEnabled then
                cat.showHealthBar = false
            end
            FNC:SyncAllCVars()
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
            if cfg.defaultEnabled ~= nil then
                cat.enabled = cfg.defaultEnabled
            else
                cat.enabled = true
            end
            cat.healthEnabled = true
            cat.nameEnabled = true
            if cfg.hasHealthBarOption then
                if cfg.defaultShowHealthBar ~= nil then
                    cat.showHealthBar = cfg.defaultShowHealthBar
                else
                    cat.showHealthBar = false
                end
            end
            if cfg.hasSubtitleOption then
                cat.showSubtitle = true
                cat.colorSubtitle = FNC.GetDefaultSubtitle(cfg)
            end
            cat.colorHealth = FNC.GetDefaultHealth(cfg)
            cat.colorName = { r = cfg.defaultName.r, g = cfg.defaultName.g, b = cfg.defaultName.b }

            if cfg.subCategories and cat.subCategories then
                for _, subCfg in ipairs(cfg.subCategories) do
                    local subCat = cat.subCategories[subCfg.key]
                    if subCat then
                        subCat.enabled = (subCfg.defaultEnabled ~= nil) and subCfg.defaultEnabled or false
                        subCat.healthEnabled = true
                        subCat.nameEnabled = true
                        subCat.subtitleEnabled = true
                        subCat.colorHealth = FNC.GetDefaultHealth(subCfg)
                        subCat.colorName = { r = subCfg.defaultName.r, g = subCfg.defaultName.g, b = subCfg.defaultName.b }
                        subCat.colorSubtitle = FNC.GetDefaultSubtitle(subCfg)
                    end
                end
            end

            FNC:SyncAllCVars()
            FNC:UpdateConfigPanelUI()
            FNC:RefreshAllPlates()
            print(string.format("|cFF00FFCCForeverNamePlateColors|r Reset %s to defaults.", cfg.label))
        end
    end)

    table.insert(FNC.categoryCards, card)
    FNC.cardsByKey[cfg.key] = card
    return card
end

local function BuildConfigPanelUI()
    if uiBuilt then return end
    uiBuilt = true

    local title = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("ForeverNamePlateColors Options")

    local scrollFrame = CreateFrame("ScrollFrame", "FNCConfigScrollFrame", configFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -42)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 10)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        local step = 35
        local new = cur - (delta * step)
        if new < 0 then new = 0 end
        if new > max then new = max end
        self:SetVerticalScroll(new)
    end)

    scrollChild = CreateFrame("Frame", "FNCConfigScrollChild", scrollFrame)
    scrollChild:SetSize(570, 600)
    scrollFrame:SetScrollChild(scrollChild)

    -- Global Settings Box
    local globalBox = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
    globalBox:SetSize(560, 74)
    globalBox:SetPoint("TOPLEFT", 6, -6)
    globalBox:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    globalBox:SetBackdropColor(0.08, 0.08, 0.08, 0.85)
    globalBox:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    enableCB = CreateFrame("CheckButton", nil, globalBox, "InterfaceOptionsCheckButtonTemplate")
    enableCB:SetPoint("TOPLEFT", 10, -6)
    enableCB.Text:SetText("Enable Addon")
    SetTooltip(enableCB, "Master toggle for ForeverNamePlateColors.\nWhen unchecked, all nameplates revert to Blizzard defaults.")

    enableCB:SetScript("OnClick", function(self)
        ForeverNamePlateColorsDB.enabled = self:GetChecked()
        FNC:SyncAllCVars()
        FNC:UpdateConfigPanelUI()
        if ForeverNamePlateColorsDB.enabled then
            FNC:RefreshAllPlates()
        else
            FNC:ResetAllPlates()
        end
    end)

    matchBtn = CreateFrame("Button", nil, globalBox, "UIPanelButtonTemplate")
    matchBtn:SetSize(200, 22)
    matchBtn:SetPoint("BOTTOMLEFT", 10, 8)
    matchBtn:SetText("Match Name to Health Colors")
    SetTooltip(matchBtn, "One-click action to copy every category's health bar color to its name color.\nYou can still customize individual name colors afterwards.")

    matchBtn:SetScript("OnClick", function()
        local db = ForeverNamePlateColorsDB
        if not db or not db.categories then return end
        for _, cfg in ipairs(FNC.CATEGORY_CONFIG) do
            local cat = db.categories[cfg.key]
            if cat and cat.colorHealth then
                cat.colorName = { r = cat.colorHealth.r, g = cat.colorHealth.g, b = cat.colorHealth.b }
            end
            if cfg.subCategories and cat and cat.subCategories then
                for _, subCfg in ipairs(cfg.subCategories) do
                    local subCat = cat.subCategories[subCfg.key]
                    if subCat and subCat.colorHealth then
                        subCat.colorName = { r = subCat.colorHealth.r, g = subCat.colorHealth.g, b = subCat.colorHealth.b }
                    end
                end
            end
        end
        FNC:UpdateConfigPanelUI()
        FNC:RefreshAllPlates()
        print("|cFF00FFCCForeverNamePlateColors|r All name colors matched to their health colors.")
    end)

    enableAllBtn = CreateFrame("Button", nil, globalBox, "UIPanelButtonTemplate")
    enableAllBtn:SetSize(145, 22)
    enableAllBtn:SetPoint("LEFT", matchBtn, "RIGHT", 10, 0)
    enableAllBtn:SetText("Enable All Categories")
    SetTooltip(enableAllBtn, "Enable color overrides across all categories.\nDoes not change your individual health/name channel settings.")

    enableAllBtn:SetScript("OnClick", function()
        local db = ForeverNamePlateColorsDB
        if not db or not db.categories then return end
        for _, cfg in ipairs(FNC.CATEGORY_CONFIG) do
            local cat = db.categories[cfg.key]
            if cat then cat.enabled = true end
        end
        FNC:SyncAllCVars()
        FNC:UpdateConfigPanelUI()
        FNC:RefreshAllPlates()
        print("|cFF00FFCCForeverNamePlateColors|r All categories enabled.")
    end)

    disableAllBtn = CreateFrame("Button", nil, globalBox, "UIPanelButtonTemplate")
    disableAllBtn:SetSize(145, 22)
    disableAllBtn:SetPoint("LEFT", enableAllBtn, "RIGHT", 10, 0)
    disableAllBtn:SetText("Disable All Categories")
    SetTooltip(disableAllBtn, "Disable color overrides across all categories.\nGreys out all category controls and restores Blizzard defaults.")

    disableAllBtn:SetScript("OnClick", function()
        local db = ForeverNamePlateColorsDB
        if not db or not db.categories then return end
        for _, cfg in ipairs(FNC.CATEGORY_CONFIG) do
            local cat = db.categories[cfg.key]
            if cat then
                cat.enabled = false
                if cfg.syncHealthBarWithEnabled then
                    cat.showHealthBar = false
                end
            end
        end
        FNC:SyncAllCVars()
        FNC:UpdateConfigPanelUI()
        FNC:RefreshAllPlates()
        print("|cFF00FFCCForeverNamePlateColors|r All categories disabled.")
    end)

    -- Instantiate Section Headers & Category Cards inside scrollChild
    for _, group in ipairs(FNC.UI_GROUPS) do
        CreateSectionHeader(scrollChild, group.key, group.label)
        for _, cfg in ipairs(FNC.CATEGORY_CONFIG) do
            if cfg.group == group.key then
                CreateCategoryCard(scrollChild, cfg)
            end
        end
    end
end

function FNC:RelayoutConfigPanel()
    if not uiBuilt then return end
    local cardY = -96
    for groupIdx, group in ipairs(FNC.UI_GROUPS) do
        if groupIdx > 1 then
            cardY = cardY - 22
        end

        local header = FNC.headersByGroup[group.key]
        if header then
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", 6, cardY)
            cardY = cardY - 26
        end

        for _, cfg in ipairs(FNC.CATEGORY_CONFIG) do
            if cfg.group == group.key then
                local card = FNC.cardsByKey[cfg.key]
                if card then
                    local cat = ForeverNamePlateColorsDB and ForeverNamePlateColorsDB.categories and ForeverNamePlateColorsDB.categories[cfg.key]
                    local totalHeight = card.baseHeight
                    if card.advancedContainer then
                        local expanded = cat and cat.advancedExpanded
                        if expanded then
                            card.advancedContainer:Show()
                            totalHeight = card.baseHeight + card.advancedHeight
                            if card.advancedBtn then card.advancedBtn:SetText("Hide Advanced") end
                        else
                            card.advancedContainer:Hide()
                            if card.advancedBtn then card.advancedBtn:SetText("Show Advanced") end
                        end
                    end
                    card:SetHeight(totalHeight)
                    card:ClearAllPoints()
                    card:SetPoint("TOPLEFT", 6, cardY)
                    cardY = cardY - totalHeight - 8
                end
            end
        end
    end
    scrollChild:SetHeight(math.abs(cardY) + 20)
end

function FNC:UpdateConfigPanelUI()
    if not uiBuilt then return end

    FNC:RelayoutConfigPanel()

    local addonEnabled = ForeverNamePlateColorsDB and (ForeverNamePlateColorsDB.enabled ~= false)
    enableCB:SetChecked(addonEnabled)

    -- Global action buttons: grey out and disable when master addon is disabled
    matchBtn:SetEnabled(addonEnabled)
    matchBtn:SetAlpha(addonEnabled and 1.0 or 0.4)
    enableAllBtn:SetEnabled(addonEnabled)
    enableAllBtn:SetAlpha(addonEnabled and 1.0 or 0.4)
    disableAllBtn:SetEnabled(addonEnabled)
    disableAllBtn:SetAlpha(addonEnabled and 1.0 or 0.4)

    for _, header in ipairs(FNC.sectionHeaders) do
        header:SetAlpha(addonEnabled and 1.0 or 0.4)
    end

    for _, card in ipairs(FNC.categoryCards) do
        local cfg = card.cfg
        local cat = ForeverNamePlateColorsDB.categories and ForeverNamePlateColorsDB.categories[cfg.key]
        if cat then
            card.enabledCB:SetChecked(cat.enabled)
            card.healthCB:SetChecked(cat.healthEnabled)
            card.nameCB:SetChecked(cat.nameEnabled)

            if card.healthBarCB then
                card.healthBarCB:SetChecked(cat.showHealthBar ~= false)
            end
            if card.subtitleCB then
                card.subtitleCB:SetChecked(cat.showSubtitle ~= false)
            end
            if card.subtitleBtn and cat.colorSubtitle then
                card.subtitleBtn.swatch:SetColorTexture(cat.colorSubtitle.r, cat.colorSubtitle.g, cat.colorSubtitle.b)
            end

            if cat.colorHealth then
                card.healthBtn.swatch:SetColorTexture(cat.colorHealth.r, cat.colorHealth.g, cat.colorHealth.b)
            end
            if cat.colorName then
                card.nameBtn.swatch:SetColorTexture(cat.colorName.r, cat.colorName.g, cat.colorName.b)
            end

            -- Visual Grey-out logic
            if not addonEnabled then
                card:SetAlpha(0.4)
                card.enabledCB:SetEnabled(false)
                if card.advancedBtn then card.advancedBtn:SetEnabled(false) end
                if card.healthBarCB then card.healthBarCB:SetEnabled(false) end
                if card.subtitleCB then card.subtitleCB:SetEnabled(false) end
                if card.subtitleBtn then card.subtitleBtn:SetEnabled(false) end
                card.healthCB:SetEnabled(false)
                card.nameCB:SetEnabled(false)
                card.healthBtn:SetEnabled(false)
                card.nameBtn:SetEnabled(false)
                card.resetBtn:SetEnabled(false)
                if card.subRows then
                    for _, row in ipairs(card.subRows) do
                        row:SetAlpha(0.4)
                        row.enabledCB:SetEnabled(false)
                        row.healthCB:SetEnabled(false)
                        row.healthBtn:SetEnabled(false)
                        row.nameCB:SetEnabled(false)
                        row.nameBtn:SetEnabled(false)
                        row.subtitleCB:SetEnabled(false)
                        row.subtitleBtn:SetEnabled(false)
                        row.resetBtn:SetEnabled(false)
                    end
                end
            else
                card:SetAlpha(1.0)
                card.enabledCB:SetEnabled(true)
                card.enabledCB:SetAlpha(1.0)

                if not cat.enabled then
                    if card.advancedBtn then
                        card.advancedBtn:SetEnabled(false)
                        card.advancedBtn:SetAlpha(0.4)
                    end
                    if card.healthBarCB then
                        card.healthBarCB:SetEnabled(false)
                        card.healthBarCB:SetAlpha(0.4)
                    end
                    if card.subtitleCB then
                        card.subtitleCB:SetEnabled(false)
                        card.subtitleCB:SetAlpha(0.4)
                    end
                    if card.subtitleBtn then
                        card.subtitleBtn:SetEnabled(false)
                        card.subtitleBtn:SetAlpha(0.4)
                    end
                    card.healthCB:SetEnabled(false)
                    card.healthCB:SetAlpha(0.4)
                    card.nameCB:SetEnabled(false)
                    card.nameCB:SetAlpha(0.4)
                    card.healthBtn:SetEnabled(false)
                    card.healthBtn:SetAlpha(0.4)
                    card.nameBtn:SetEnabled(false)
                    card.nameBtn:SetAlpha(0.4)
                    card.resetBtn:SetEnabled(false)
                    card.resetBtn:SetAlpha(0.4)

                    if card.subRows then
                        for _, row in ipairs(card.subRows) do
                            row:SetAlpha(0.4)
                            row.enabledCB:SetEnabled(false)
                            row.healthCB:SetEnabled(false)
                            row.healthBtn:SetEnabled(false)
                            row.nameCB:SetEnabled(false)
                            row.nameBtn:SetEnabled(false)
                            row.subtitleCB:SetEnabled(false)
                            row.subtitleBtn:SetEnabled(false)
                            row.resetBtn:SetEnabled(false)
                        end
                    end
                else
                    local hbShown = (cat.showHealthBar ~= false)
                    local subShown = (cat.showSubtitle ~= false)

                    if card.advancedBtn then
                        card.advancedBtn:SetEnabled(true)
                        card.advancedBtn:SetAlpha(1.0)
                    end

                    if card.healthBarCB then
                        card.healthBarCB:SetEnabled(true)
                        card.healthBarCB:SetAlpha(1.0)
                    end

                    if card.subtitleCB then
                        card.subtitleCB:SetEnabled(true)
                        card.subtitleCB:SetAlpha(1.0)
                    end

                    if card.subtitleBtn then
                        card.subtitleBtn:SetEnabled(subShown)
                        card.subtitleBtn:SetAlpha(subShown and 1.0 or 0.4)
                    end

                    card.nameCB:SetEnabled(true)
                    card.nameCB:SetAlpha(1.0)
                    card.nameBtn:SetEnabled(cat.nameEnabled)
                    card.nameBtn:SetAlpha(cat.nameEnabled and 1.0 or 0.4)

                    card.healthCB:SetEnabled(hbShown)
                    card.healthCB:SetAlpha(hbShown and 1.0 or 0.4)
                    local hbBtnActive = hbShown and cat.healthEnabled
                    card.healthBtn:SetEnabled(hbBtnActive)
                    card.healthBtn:SetAlpha(hbBtnActive and 1.0 or 0.4)

                    card.resetBtn:SetEnabled(true)
                    card.resetBtn:SetAlpha(1.0)

                    -- Update Advanced Sub-Rows
                    if card.subRows and cat.subCategories then
                        for _, row in ipairs(card.subRows) do
                            local subCfg = row.subCfg
                            local subCat = cat.subCategories[subCfg.key]
                            if subCat then
                                row:SetAlpha(1.0)
                                row.enabledCB:SetChecked(subCat.enabled)
                                row.healthCB:SetChecked(subCat.healthEnabled)
                                row.nameCB:SetChecked(subCat.nameEnabled)
                                row.subtitleCB:SetChecked(subCat.subtitleEnabled ~= false)

                                if subCat.colorHealth then
                                    row.healthBtn.swatch:SetColorTexture(subCat.colorHealth.r, subCat.colorHealth.g, subCat.colorHealth.b)
                                end
                                if subCat.colorName then
                                    row.nameBtn.swatch:SetColorTexture(subCat.colorName.r, subCat.colorName.g, subCat.colorName.b)
                                end
                                if subCat.colorSubtitle then
                                    row.subtitleBtn.swatch:SetColorTexture(subCat.colorSubtitle.r, subCat.colorSubtitle.g, subCat.colorSubtitle.b)
                                end

                                row.enabledCB:SetEnabled(true)
                                row.enabledCB:SetAlpha(1.0)

                                if not subCat.enabled then
                                    row.healthCB:SetEnabled(false)
                                    row.healthCB:SetAlpha(0.4)
                                    row.healthBtn:SetEnabled(false)
                                    row.healthBtn:SetAlpha(0.4)
                                    row.nameCB:SetEnabled(false)
                                    row.nameCB:SetAlpha(0.4)
                                    row.nameBtn:SetEnabled(false)
                                    row.nameBtn:SetAlpha(0.4)
                                    row.subtitleCB:SetEnabled(false)
                                    row.subtitleCB:SetAlpha(0.4)
                                    row.subtitleBtn:SetEnabled(false)
                                    row.subtitleBtn:SetAlpha(0.4)
                                    row.resetBtn:SetEnabled(false)
                                    row.resetBtn:SetAlpha(0.4)
                                else
                                    row.healthCB:SetEnabled(hbShown)
                                    row.healthCB:SetAlpha(hbShown and 1.0 or 0.4)
                                    local subHbActive = hbShown and subCat.healthEnabled
                                    row.healthBtn:SetEnabled(subHbActive)
                                    row.healthBtn:SetAlpha(subHbActive and 1.0 or 0.4)

                                    row.nameCB:SetEnabled(true)
                                    row.nameCB:SetAlpha(1.0)
                                    row.nameBtn:SetEnabled(subCat.nameEnabled)
                                    row.nameBtn:SetAlpha(subCat.nameEnabled and 1.0 or 0.4)

                                    row.subtitleCB:SetEnabled(subShown)
                                    row.subtitleCB:SetAlpha(subShown and 1.0 or 0.4)
                                    local subTagActive = subShown and (subCat.subtitleEnabled ~= false)
                                    row.subtitleBtn:SetEnabled(subTagActive)
                                    row.subtitleBtn:SetAlpha(subTagActive and 1.0 or 0.4)

                                    row.resetBtn:SetEnabled(true)
                                    row.resetBtn:SetAlpha(1.0)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

configFrame:SetScript("OnShow", function()
    BuildConfigPanelUI()
    FNC:UpdateConfigPanelUI()
end)

if Settings and Settings.RegisterCanvasLayoutCategory then
    local category, layout = Settings.RegisterCanvasLayoutCategory(configFrame, "ForeverNamePlateColors")
    Settings.RegisterAddOnCategory(category)
    FNC.settingsCategory = category
else
    InterfaceOptions_AddCategory(configFrame)
end

function FNC:OpenColorPicker(catKey, channel, swatchTexture, subKey)
    local parentCat = ForeverNamePlateColorsDB.categories and ForeverNamePlateColorsDB.categories[catKey]
    local cat = subKey and (parentCat and parentCat.subCategories and parentCat.subCategories[subKey]) or parentCat
    if not cat then return end
    local colorField = (channel == "health") and "colorHealth" or ((channel == "name") and "colorName" or "colorSubtitle")
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