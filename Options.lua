--------------------------------------------------------------------------------
-- Options.lua
-- Scrollable Blizzard Settings Panel, Row Cards, Sub-Category Drawers, & Color Picker
--------------------------------------------------------------------------------

local addonName, FNC = ...

-- Color Picker Helper (compatible with Classic Era 1.15+ ColorPickerFrame API)
local function ShowColorPicker(r, g, b, callback)
    if ColorPickerFrame.SetupColorPickerAndShow then
        local info = {
            r = r,
            g = g,
            b = b,
            hasOpacity = false,
            swatchFunc = function()
                local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                callback(newR, newG, newB)
            end,
            cancelFunc = function(prev)
                if prev then
                    callback(prev.r, prev.g, prev.b)
                end
            end,
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
    else
        local prevR, prevG, prevB = r, g, b
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.func = function()
            local newR, newG, newB = ColorPickerFrame:GetColorRGB()
            callback(newR, newG, newB)
        end
        ColorPickerFrame.cancelFunc = function()
            callback(prevR, prevG, prevB)
        end
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end

-- Build Blizzard Interface Options Panel
local configFrame = CreateFrame("Frame", "ForeverNamePlateColorsOptionsPanel", UIParent)
configFrame.name = "ForeverNamePlateColors"
FNC.configFrame = configFrame

local scrollFrame = CreateFrame("ScrollFrame", "ForeverNamePlateColorsScrollFrame", configFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 0, -4)
scrollFrame:SetPoint("BOTTOMRIGHT", -26, 4)

local scrollChild = CreateFrame("Frame", "ForeverNamePlateColorsScrollChild", scrollFrame)
scrollChild:SetWidth(600)
scrollChild:SetHeight(1200)
scrollFrame:SetScrollChild(scrollChild)

configFrame:SetScript("OnSizeChanged", function(self, width)
    if width and width > 60 then
        scrollChild:SetWidth(width - 36)
    end
end)

local titleText = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
titleText:SetPoint("TOPLEFT", 16, -12)
titleText:SetText("ForeverNamePlateColors")

local descText = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
descText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -6)
descText:SetText("Customize health bar colors, name colors, and nameplate visibility across unit categories.")

-- Master Enable Checkbox
local enableCheckbox = CreateFrame("CheckButton", "FNCEnableCheck", scrollChild, "InterfaceOptionsCheckButtonTemplate")
enableCheckbox:SetPoint("TOPLEFT", descText, "BOTTOMLEFT", -2, -10)
enableCheckbox.Text:SetText("Enable ForeverNamePlateColors")
enableCheckbox:SetScript("OnClick", function(self)
    ForeverNamePlateColorsDB.enabled = self:GetChecked() and true or false
    if ForeverNamePlateColorsDB.enabled then
        FNC:RefreshAllPlates()
    else
        FNC:SyncAllCVars()
        FNC:ResetAllPlates()
    end
end)

-- Show Errors in Chat Checkbox (off by default; errors always log to SavedVariables on disk)
local showErrorsCheckbox = CreateFrame("CheckButton", "FNCShowErrorsCheck", scrollChild, "InterfaceOptionsCheckButtonTemplate")
showErrorsCheckbox:SetPoint("LEFT", enableCheckbox.Text, "RIGHT", 28, 0)
showErrorsCheckbox.Text:SetText("Show Errors in Chat")
showErrorsCheckbox:SetScript("OnClick", function(self)
    ForeverNamePlateColorsDB.showErrors = self:GetChecked() and true or false
end)

-- Nameplate Visibility Section (CVar Toggles)
local visBox = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
visBox:SetPoint("TOPLEFT", enableCheckbox, "BOTTOMLEFT", 2, -10)
visBox:SetPoint("RIGHT", scrollChild, "RIGHT", -12, 0)
visBox:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
visBox:SetBackdropColor(0.06, 0.06, 0.08, 0.75)
visBox:SetBackdropBorderColor(0.35, 0.35, 0.4, 0.9)

local visHeader = visBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
visHeader:SetPoint("TOPLEFT", 12, -10)
visHeader:SetText("Nameplate Visibility (Show Nameplates On)")

local cvarCheckboxes = {}
local colWidth = 185
for idx, item in ipairs(FNC.VISIBILITY_CVARS) do
    local col = (idx - 1) % 3
    local row = math.floor((idx - 1) / 3)
    local cb = CreateFrame("CheckButton", "FNCCVarCheck_" .. item.cvar, visBox, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", visHeader, "BOTTOMLEFT", (col * colWidth) - 2, -6 - (row * 26))
    cb.Text:SetText(item.label)
    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        ForeverNamePlateColorsDB.cvars[item.cvar] = checked
        FNC:ApplyCVar(item.cvar, checked)
        FNC:RefreshAllPlates()
    end)
    cvarCheckboxes[item.cvar] = cb
end

local numVisRows = math.ceil(#FNC.VISIBILITY_CVARS / 3)
visBox:SetHeight(42 + (numVisRows * 26))

-- Helper to create a color swatch button
local function CreateColorSwatch(parent, labelText)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(20, 20)

    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.8, 0.8, 0.8, 1)

    local swatch = btn:CreateTexture(nil, "ARTWORK")
    swatch:SetPoint("TOPLEFT", 2, -2)
    swatch:SetPoint("BOTTOMRIGHT", -2, 2)
    swatch:SetColorTexture(1, 1, 1, 1)
    btn.swatch = swatch

    local label = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("LEFT", btn, "RIGHT", 6, 0)
    label:SetText(labelText)
    btn.label = label

    return btn
end

-- Build Sectioned Category Cards & Rows
local uiRows = {}
local sectionHeaders = {}
local expandedState = {}

local function RelayoutOptionsPanel()
    local prevWidget = visBox
    local totalHeight = visBox:GetHeight() + 115

    for idx, cfg in ipairs(FNC.CATEGORY_CONFIG) do
        local secHeader = sectionHeaders[idx]
        if secHeader then
            secHeader:ClearAllPoints()
            secHeader:SetPoint("TOPLEFT", prevWidget, "BOTTOMLEFT", 2, -16)
            prevWidget = secHeader
            totalHeight = totalHeight + 32
        end

        local row = uiRows[cfg.key]
        if row and row.card then
            local isExpanded = cfg.subCategories and expandedState[cfg.key]
            local baseHeight = row.baseHeight
            local totalCardHeight = baseHeight

            if cfg.subCategories and row.advDrawer then
                if isExpanded then
                    row.advDrawer:Show()
                    totalCardHeight = baseHeight + row.advDrawerHeight + 6
                else
                    row.advDrawer:Hide()
                end
            end

            row.card:SetHeight(totalCardHeight)
            row.card:ClearAllPoints()
            local topOffset = secHeader and -6 or -8
            row.card:SetPoint("TOPLEFT", prevWidget, "BOTTOMLEFT", secHeader and -2 or 0, topOffset)
            row.card:SetPoint("RIGHT", scrollChild, "RIGHT", -12, 0)

            prevWidget = row.card
            totalHeight = totalHeight + totalCardHeight + math.abs(topOffset)
        end
    end

    scrollChild:SetHeight(totalHeight + 24)
end

local lastSection = nil
for idx, cfg in ipairs(FNC.CATEGORY_CONFIG) do
    if cfg.section and cfg.section ~= lastSection then
        lastSection = cfg.section
        local secHeader = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalMed2")
        secHeader:SetText(cfg.section)
        secHeader:SetTextColor(1.0, 0.82, 0.0)
        sectionHeaders[idx] = secHeader
    end

    local hasExtraRow = cfg.hasHealthBarOption or cfg.hasSubtitleOption or (cfg.subCategories ~= nil)
    local baseHeight = hasExtraRow and 98 or 72

    local card = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
    card:SetHeight(baseHeight)
    card:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    card:SetBackdropColor(0.08, 0.08, 0.1, 0.78)
    card:SetBackdropBorderColor(0.35, 0.35, 0.4, 0.9)

    local row = { card = card, baseHeight = baseHeight }

    local catEnable = CreateFrame("CheckButton", "FNCCatEnable_" .. cfg.key, card, "InterfaceOptionsCheckButtonTemplate")
    catEnable:SetPoint("TOPLEFT", 10, -8)
    catEnable.Text:SetText(cfg.label)
    catEnable.Text:SetFontObject("GameFontNormal")
    catEnable:SetScript("OnClick", function(self)
        ForeverNamePlateColorsDB.categories[cfg.key].enabled = self:GetChecked() and true or false
        FNC:RefreshAllPlates()
    end)
    row.catEnable = catEnable

    local resetBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    resetBtn:SetSize(74, 22)
    resetBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -10)
    resetBtn:SetText("Reset")
    row.resetBtn = resetBtn

    if cfg.hasHealthOption then
        local healthCheck = CreateFrame("CheckButton", "FNCHealthCheck_" .. cfg.key, card, "InterfaceOptionsCheckButtonTemplate")
        healthCheck:SetPoint("TOPLEFT", catEnable, "BOTTOMLEFT", 18, -2)
        healthCheck.Text:SetText("Health")
        healthCheck:SetScript("OnClick", function(self)
            ForeverNamePlateColorsDB.categories[cfg.key].healthEnabled = self:GetChecked() and true or false
            FNC:RefreshAllPlates()
        end)
        row.healthCheck = healthCheck

        local healthSwatch = CreateColorSwatch(card, "Color")
        healthSwatch:SetPoint("LEFT", healthCheck.Text, "RIGHT", 10, 0)
        healthSwatch:SetScript("OnClick", function()
            local c = ForeverNamePlateColorsDB.categories[cfg.key].colorHealth
            ShowColorPicker(c.r, c.g, c.b, function(r, g, b)
                c.r, c.g, c.b = r, g, b
                healthSwatch.swatch:SetColorTexture(r, g, b, 1)
                FNC:RefreshAllPlates()
            end)
        end)
        row.healthSwatch = healthSwatch
    end

    local nameCheck = CreateFrame("CheckButton", "FNCNameCheck_" .. cfg.key, card, "InterfaceOptionsCheckButtonTemplate")
    if cfg.hasHealthOption then
        nameCheck:SetPoint("TOPLEFT", catEnable, "BOTTOMLEFT", 215, -2)
    else
        nameCheck:SetPoint("TOPLEFT", catEnable, "BOTTOMLEFT", 18, -2)
    end
    nameCheck.Text:SetText("Name")
    nameCheck:SetScript("OnClick", function(self)
        ForeverNamePlateColorsDB.categories[cfg.key].nameEnabled = self:GetChecked() and true or false
        FNC:RefreshAllPlates()
    end)
    row.nameCheck = nameCheck

    local nameSwatch = CreateColorSwatch(card, "Color")
    nameSwatch:SetPoint("LEFT", nameCheck.Text, "RIGHT", 10, 0)
    nameSwatch:SetScript("OnClick", function()
        local c = ForeverNamePlateColorsDB.categories[cfg.key].colorName
        ShowColorPicker(c.r, c.g, c.b, function(r, g, b)
            c.r, c.g, c.b = r, g, b
            nameSwatch.swatch:SetColorTexture(r, g, b, 1)
            FNC:RefreshAllPlates()
        end)
    end)
    row.nameSwatch = nameSwatch

    if cfg.hasHealthBarOption then
        local showHBCheck = CreateFrame("CheckButton", "FNCShowHBCheck_" .. cfg.key, card, "InterfaceOptionsCheckButtonTemplate")
        showHBCheck:SetPoint("TOPLEFT", catEnable, "BOTTOMLEFT", 18, -28)
        showHBCheck.Text:SetText("Show Health Bar")
        showHBCheck:SetScript("OnClick", function(self)
            ForeverNamePlateColorsDB.categories[cfg.key].showHealthBar = self:GetChecked() and true or false
            FNC:RefreshAllPlates()
        end)
        row.showHBCheck = showHBCheck
    end

    if cfg.hasSubtitleOption then
        local showSubCheck = CreateFrame("CheckButton", "FNCShowSubCheck_" .. cfg.key, card, "InterfaceOptionsCheckButtonTemplate")
        if cfg.hasHealthBarOption then
            showSubCheck:SetPoint("TOPLEFT", catEnable, "BOTTOMLEFT", 215, -28)
        else
            showSubCheck:SetPoint("TOPLEFT", catEnable, "BOTTOMLEFT", 18, -28)
        end
        showSubCheck.Text:SetText(cfg.subtitleLabel or "Show Title")
        showSubCheck:SetScript("OnClick", function(self)
            ForeverNamePlateColorsDB.categories[cfg.key].showSubtitle = self:GetChecked() and true or false
            FNC:RefreshAllPlates()
        end)
        row.showSubCheck = showSubCheck

        local subSwatch = CreateColorSwatch(card, "Title Color")
        subSwatch:SetPoint("LEFT", showSubCheck.Text, "RIGHT", 10, 0)
        subSwatch:SetScript("OnClick", function()
            local c = ForeverNamePlateColorsDB.categories[cfg.key].colorSubtitle
            ShowColorPicker(c.r, c.g, c.b, function(r, g, b)
                c.r, c.g, c.b = r, g, b
                subSwatch.swatch:SetColorTexture(r, g, b, 1)
                FNC:RefreshAllPlates()
            end)
        end)
        row.subSwatch = subSwatch
    end

    if cfg.subCategories then
        local advBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
        advBtn:SetSize(112, 22)
        advBtn:SetPoint("RIGHT", resetBtn, "LEFT", -6, 0)
        advBtn:SetText("Advanced  v")
        row.advBtn = advBtn

        local subBlockHeight = 64
        local advDrawerHeight = 14 + (#cfg.subCategories * subBlockHeight)
        row.advDrawerHeight = advDrawerHeight

        local advDrawer = CreateFrame("Frame", nil, card, "BackdropTemplate")
        advDrawer:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -baseHeight)
        advDrawer:SetPoint("RIGHT", card, "RIGHT", -12, 0)
        advDrawer:SetHeight(advDrawerHeight)
        advDrawer:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        advDrawer:SetBackdropColor(0.04, 0.04, 0.06, 0.85)
        advDrawer:SetBackdropBorderColor(0.28, 0.28, 0.34, 0.85)
        advDrawer:Hide()
        row.advDrawer = advDrawer
        row.subRows = {}

        for sIdx, subCfg in ipairs(cfg.subCategories) do
            local yOffset = -8 - ((sIdx - 1) * subBlockHeight)
            local subRow = {}

            local subEnable = CreateFrame("CheckButton", "FNCSubEnable_" .. subCfg.key, advDrawer, "InterfaceOptionsCheckButtonTemplate")
            subEnable:SetPoint("TOPLEFT", advDrawer, "TOPLEFT", 8, yOffset)
            subEnable.Text:SetText(subCfg.label)
            subEnable.Text:SetFontObject("GameFontNormalSmall")
            subEnable:SetScript("OnClick", function(self)
                ForeverNamePlateColorsDB.categories[cfg.key].subCategories[subCfg.key].enabled = self:GetChecked() and true or false
                FNC:RefreshAllPlates()
            end)
            subRow.subEnable = subEnable

            local subHealthCheck = CreateFrame("CheckButton", "FNCSubHealthCheck_" .. subCfg.key, advDrawer, "InterfaceOptionsCheckButtonTemplate")
            subHealthCheck:SetPoint("TOPLEFT", subEnable, "BOTTOMLEFT", 16, 2)
            subHealthCheck.Text:SetText("Health")
            subHealthCheck:SetScript("OnClick", function(self)
                ForeverNamePlateColorsDB.categories[cfg.key].subCategories[subCfg.key].healthEnabled = self:GetChecked() and true or false
                FNC:RefreshAllPlates()
            end)
            subRow.subHealthCheck = subHealthCheck

            local subHealthSwatch = CreateColorSwatch(advDrawer, "Color")
            subHealthSwatch:SetPoint("LEFT", subHealthCheck.Text, "RIGHT", 6, 0)
            subHealthSwatch:SetScript("OnClick", function()
                local c = ForeverNamePlateColorsDB.categories[cfg.key].subCategories[subCfg.key].colorHealth
                ShowColorPicker(c.r, c.g, c.b, function(r, g, b)
                    c.r, c.g, c.b = r, g, b
                    subHealthSwatch.swatch:SetColorTexture(r, g, b, 1)
                    FNC:RefreshAllPlates()
                end)
            end)
            subRow.subHealthSwatch = subHealthSwatch

            local subNameCheck = CreateFrame("CheckButton", "FNCSubNameCheck_" .. subCfg.key, advDrawer, "InterfaceOptionsCheckButtonTemplate")
            subNameCheck:SetPoint("TOPLEFT", subEnable, "BOTTOMLEFT", 168, 2)
            subNameCheck.Text:SetText("Name")
            subNameCheck:SetScript("OnClick", function(self)
                ForeverNamePlateColorsDB.categories[cfg.key].subCategories[subCfg.key].nameEnabled = self:GetChecked() and true or false
                FNC:RefreshAllPlates()
            end)
            subRow.subNameCheck = subNameCheck

            local subNameSwatch = CreateColorSwatch(advDrawer, "Color")
            subNameSwatch:SetPoint("LEFT", subNameCheck.Text, "RIGHT", 6, 0)
            subNameSwatch:SetScript("OnClick", function()
                local c = ForeverNamePlateColorsDB.categories[cfg.key].subCategories[subCfg.key].colorName
                ShowColorPicker(c.r, c.g, c.b, function(r, g, b)
                    c.r, c.g, c.b = r, g, b
                    subNameSwatch.swatch:SetColorTexture(r, g, b, 1)
                    FNC:RefreshAllPlates()
                end)
            end)
            subRow.subNameSwatch = subNameSwatch

            local subTitleCheck = CreateFrame("CheckButton", "FNCSubTitleCheck_" .. subCfg.key, advDrawer, "InterfaceOptionsCheckButtonTemplate")
            subTitleCheck:SetPoint("TOPLEFT", subEnable, "BOTTOMLEFT", 315, 2)
            subTitleCheck.Text:SetText("Owner")
            subTitleCheck:SetScript("OnClick", function(self)
                ForeverNamePlateColorsDB.categories[cfg.key].subCategories[subCfg.key].subtitleEnabled = self:GetChecked() and true or false
                FNC:RefreshAllPlates()
            end)
            subRow.subTitleCheck = subTitleCheck

            local subTitleSwatch = CreateColorSwatch(advDrawer, "Color")
            subTitleSwatch:SetPoint("LEFT", subTitleCheck.Text, "RIGHT", 6, 0)
            subTitleSwatch:SetScript("OnClick", function()
                local c = ForeverNamePlateColorsDB.categories[cfg.key].subCategories[subCfg.key].colorSubtitle
                ShowColorPicker(c.r, c.g, c.b, function(r, g, b)
                    c.r, c.g, c.b = r, g, b
                    subTitleSwatch.swatch:SetColorTexture(r, g, b, 1)
                    FNC:RefreshAllPlates()
                end)
            end)
            subRow.subTitleSwatch = subTitleSwatch

            row.subRows[subCfg.key] = subRow
        end

        advBtn:SetScript("OnClick", function()
            expandedState[cfg.key] = not expandedState[cfg.key]
            advBtn:SetText(expandedState[cfg.key] and "Advanced  ^" or "Advanced  v")
            RelayoutOptionsPanel()
        end)
    end

    resetBtn:SetScript("OnClick", function()
        local cat = ForeverNamePlateColorsDB.categories[cfg.key]
        cat.enabled = true
        if cfg.hasHealthBarOption then
            cat.showHealthBar = (cfg.defaultShowHealthBar ~= false)
        end
        if cfg.hasSubtitleOption then
            cat.showSubtitle = (cfg.defaultShowSubtitle == true)
            cat.colorSubtitle = FNC.CopyColor(cfg.defaultSubtitle or { r = 1.0, g = 0.82, b = 0.0 })
        end
        if cfg.hasHealthOption then
            cat.healthEnabled = true
            cat.colorHealth = FNC.CopyColor(cfg.defaultHealth)
        end
        cat.nameEnabled = true
        cat.colorName = FNC.CopyColor(cfg.defaultName)

        if cfg.subCategories and cat.subCategories then
            for _, subCfg in ipairs(cfg.subCategories) do
                local subCat = cat.subCategories[subCfg.key]
                if subCat then
                    subCat.enabled = (subCfg.defaultEnabled == true)
                    subCat.healthEnabled = true
                    subCat.nameEnabled = true
                    subCat.subtitleEnabled = true
                    subCat.colorHealth = FNC.CopyColor(subCfg.defaultHealth)
                    subCat.colorName = FNC.CopyColor(subCfg.defaultName)
                    subCat.colorSubtitle = FNC.CopyColor(subCfg.defaultSubtitle or cfg.defaultSubtitle or { r = 1.0, g = 0.82, b = 0.0 })
                end
            end
        end

        FNC:UpdateConfigPanelUI()
        FNC:RefreshAllPlates()
    end)

    uiRows[cfg.key] = row
end

RelayoutOptionsPanel()

-- Sync UI controls with SavedVariables
function FNC:UpdateConfigPanelUI()
    if not ForeverNamePlateColorsDB then return end
    enableCheckbox:SetChecked(ForeverNamePlateColorsDB.enabled)
    showErrorsCheckbox:SetChecked(ForeverNamePlateColorsDB.showErrors == true)

    if ForeverNamePlateColorsDB.cvars then
        for cvar, cb in pairs(cvarCheckboxes) do
            cb:SetChecked(ForeverNamePlateColorsDB.cvars[cvar])
        end
    end

    if ForeverNamePlateColorsDB.categories then
        for _, cfg in ipairs(FNC.CATEGORY_CONFIG) do
            local cat = ForeverNamePlateColorsDB.categories[cfg.key]
            local row = uiRows[cfg.key]
            if cat and row then
                row.catEnable:SetChecked(cat.enabled)
                if cfg.hasHealthOption and row.healthCheck and row.healthSwatch then
                    row.healthCheck:SetChecked(cat.healthEnabled)
                    row.healthSwatch.swatch:SetColorTexture(cat.colorHealth.r, cat.colorHealth.g, cat.colorHealth.b, 1)
                end
                row.nameCheck:SetChecked(cat.nameEnabled)
                row.nameSwatch.swatch:SetColorTexture(cat.colorName.r, cat.colorName.g, cat.colorName.b, 1)

                if cfg.hasHealthBarOption and row.showHBCheck then
                    row.showHBCheck:SetChecked(cat.showHealthBar ~= false)
                end
                if cfg.hasSubtitleOption and row.showSubCheck and row.subSwatch then
                    row.showSubCheck:SetChecked(cat.showSubtitle == true)
                    local sc = cat.colorSubtitle or cfg.defaultSubtitle or { r = 1.0, g = 0.82, b = 0.0 }
                    row.subSwatch.swatch:SetColorTexture(sc.r, sc.g, sc.b, 1)
                end

                if cfg.subCategories and cat.subCategories and row.subRows then
                    for _, subCfg in ipairs(cfg.subCategories) do
                        local subCat = cat.subCategories[subCfg.key]
                        local subRow = row.subRows[subCfg.key]
                        if subCat and subRow then
                            subRow.subEnable:SetChecked(subCat.enabled == true)
                            subRow.subHealthCheck:SetChecked(subCat.healthEnabled ~= false)
                            subRow.subHealthSwatch.swatch:SetColorTexture(subCat.colorHealth.r, subCat.colorHealth.g, subCat.colorHealth.b, 1)
                            subRow.subNameCheck:SetChecked(subCat.nameEnabled ~= false)
                            subRow.subNameSwatch.swatch:SetColorTexture(subCat.colorName.r, subCat.colorName.g, subCat.colorName.b, 1)
                            subRow.subTitleCheck:SetChecked(subCat.subtitleEnabled ~= false)
                            local stc = subCat.colorSubtitle or subCfg.defaultSubtitle or { r = 1.0, g = 0.82, b = 0.0 }
                            subRow.subTitleSwatch.swatch:SetColorTexture(stc.r, stc.g, stc.b, 1)
                        end
                    end
                end
            end
        end
    end
end

configFrame:SetScript("OnShow", function()
    FNC:UpdateConfigPanelUI()
    RelayoutOptionsPanel()
end)

-- Register with modern Settings API (Classic Era 1.15+) or legacy InterfaceOptions
if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(configFrame, configFrame.name)
    Settings.RegisterAddOnCategory(category)
    FNC.settingsCategory = category
else
    InterfaceOptions_AddCategory(configFrame)
end