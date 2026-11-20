--------------------------------------------------------------------------------
-- Nameplates.lua
-- Nameplate Rendering, Headline Mode, Frame Resets, and CompactUnitFrame Hooks
--------------------------------------------------------------------------------

local addonName, FNC = ...

local function IsLevelText(text)
    if type(text) ~= "string" or text == "" then return false end
    if issecretvalue and issecretvalue(text) then return false end
    local ok, clean = pcall(function()
        return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
    end)
    if not ok or type(clean) ~= "string" then return false end
    return clean:match("^%d+%+?$") ~= nil or clean == "??"
end

-- Zero-allocation region iterator via select()
local function SetLevelRegionsAlphaHelper(alpha, nameObj, subtitleObj, n, ...)
    for i = 1, n do
        local region = select(i, ...)
        if region and (not region:IsForbidden()) and region:IsObjectType("FontString") and region ~= nameObj and region ~= subtitleObj then
            local parentKey = region.GetParentKey and region:GetParentKey() or ""
            if (type(parentKey) == "string" and parentKey:lower():find("level")) or IsLevelText(region:GetText()) then
                region:SetAlpha(alpha)
            end
        end
    end
end

local function SetLevelRegionsAlpha(frame, alpha, nameObj, subtitleObj)
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
    SetLevelRegionsAlphaHelper(alpha, nameObj, subtitleObj, select("#", frame:GetRegions()), frame:GetRegions())
end

-- Zero-allocation child frame iterator via select()
local function SetChildLevelFramesAlphaHelper(alpha, nameObj, subtitleObj, n, ...)
    for i = 1, n do
        local child = select(i, ...)
        if child and (not child:IsForbidden()) and child ~= subtitleObj then
            local parentKey = child.GetParentKey and child:GetParentKey() or ""
            if type(parentKey) == "string" and (parentKey:lower():find("level") or parentKey == "ClassificationFrame") then
                child:SetAlpha(alpha)
            end
            SetLevelRegionsAlpha(child, alpha, nameObj, subtitleObj)
        end
    end
end

-- Helper: Update headline mode visibility (health bar + floating level text)
local function UpdateHeadlineMode(uf, unit, showHealthBar)
    local hb = uf.healthBar or uf.HealthBar
    local alpha = showHealthBar and 1 or 0

    if hb then
        hb:SetAlpha(alpha)
    end

    if uf.levelText then uf.levelText:SetAlpha(alpha) end
    if uf.LevelText then uf.LevelText:SetAlpha(alpha) end
    if uf.level then uf.level:SetAlpha(alpha) end
    if uf.Level then uf.Level:SetAlpha(alpha) end
    if uf.LevelFrame then uf.LevelFrame:SetAlpha(alpha) end
    if uf.ClassificationFrame then uf.ClassificationFrame:SetAlpha(alpha) end

    if hb then
        if hb.levelText then hb.levelText:SetAlpha(alpha) end
        if hb.LevelText then hb.LevelText:SetAlpha(alpha) end
        if hb.level then hb.level:SetAlpha(alpha) end
        if hb.Level then hb.Level:SetAlpha(alpha) end
        if hb.LevelFrame then hb.LevelFrame:SetAlpha(alpha) end
    end

    local nameObj = uf.name or uf.Name
    SetLevelRegionsAlpha(uf, alpha, nameObj, uf.fncSubtitle)
    SetLevelRegionsAlpha(hb, alpha, nameObj, uf.fncSubtitle)
    SetChildLevelFramesAlphaHelper(alpha, nameObj, uf.fncSubtitle, select("#", uf:GetChildren()), uf:GetChildren())
end

function FNC:ResetUnitFrame(uf)
    if not uf or uf:IsForbidden() then return end
    UpdateHeadlineMode(uf, uf.unit, true)
    if uf.fncSubtitle then
        uf.fncSubtitle:Hide()
    end
end

function FNC:UpdateUnitFrame(uf, unit)
    if not ForeverNamePlateColorsDB or not ForeverNamePlateColorsDB.enabled then return end
    if not uf or uf:IsForbidden() then return end
    if type(unit) ~= "string" or unit == "" then return end

    local isSubgroup = FNC.IsInMySubgroup(unit)
    local isRaidMember = UnitInRaid(unit) ~= nil
    local isUnitPlayer = UnitIsPlayer(unit)
    local isEnemy = UnitIsEnemy("player", unit)
    local canAttack = UnitCanAttack("player", unit)
    local isTapDenied = canAttack and (not isUnitPlayer) and UnitIsTapDenied and UnitIsTapDenied(unit)

    for _, cfg in ipairs(FNC.CATEGORY_CONFIG) do
        local cat = ForeverNamePlateColorsDB.categories and ForeverNamePlateColorsDB.categories[cfg.key]
        -- For ActiveQuestUnit, if disabled or tapped by another player, let unit fall through
        local canMatch = (cfg.key ~= "ActiveQuestUnit") or (cat and cat.enabled and not isTapDenied)

        if canMatch and cfg.match(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack, uf) then
            if not cat or not cat.enabled then
                FNC:ResetUnitFrame(uf)
                return
            end

            -- Resolve active color profile (check enabled Advanced sub-category if applicable)
            local activeStyle = cat
            local activeDefaultSub = cfg.defaultSubtitle
            if cfg.key == "FriendlyMinion" and cat.subCategories then
                local subKey = FNC.ResolveFriendlyMinionSubKey(unit)
                if subKey and cat.subCategories[subKey] and cat.subCategories[subKey].enabled then
                    activeStyle = cat.subCategories[subKey]
                    for _, subCfg in ipairs(cfg.subCategories) do
                        if subCfg.key == subKey then
                            activeDefaultSub = subCfg.defaultSubtitle
                            break
                        end
                    end
                end
            end

            local hb = uf.healthBar or uf.HealthBar
            local nameText = uf.name or uf.Name
            local npcCat = ForeverNamePlateColorsDB.categories and ForeverNamePlateColorsDB.categories["NPC"]

            -- Headline Mode: Show or Hide Health Bar and Level Text
            local showHB = (cat.showHealthBar ~= false)
            if cfg.key == "ActiveQuestUnit" then
                if canAttack then
                    showHB = true
                elseif npcCat then
                    showHB = (npcCat.showHealthBar ~= false)
                else
                    showHB = false
                end
            end
            UpdateHeadlineMode(uf, unit, showHB)

            -- Health Bar Color override (skip if tapped by another player so Blizzard grey tap color shows)
            if showHB and (not isTapDenied) and activeStyle.healthEnabled and activeStyle.colorHealth then
                if hb then
                    hb:SetStatusBarColor(activeStyle.colorHealth.r, activeStyle.colorHealth.g, activeStyle.colorHealth.b)
                end
            end

            -- Name Text Color override (apply both TextColor and VertexColor so Blizzard doesn't re-tint green)
            if activeStyle.nameEnabled and activeStyle.colorName then
                if nameText then
                    nameText:SetTextColor(activeStyle.colorName.r, activeStyle.colorName.g, activeStyle.colorName.b)
                    if nameText.SetVertexColor then
                        nameText:SetVertexColor(activeStyle.colorName.r, activeStyle.colorName.g, activeStyle.colorName.b)
                    end
                end
            end

            -- Subtitle / NPC Title / Minion Owner Tag
            local showSubtitle = cfg.hasSubtitleOption and cat.showSubtitle
            if cfg.key == "ActiveQuestUnit" and (not canAttack) and npcCat and npcCat.showSubtitle then
                showSubtitle = true
            end

            if showSubtitle then
                local subtitle = FNC:GetNPCSubtitle(unit)
                if subtitle and subtitle ~= "" and nameText then
                    if not uf.fncSubtitle then
                        uf.fncSubtitle = uf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    end
                    if cfg.key == "ActiveQuestUnit" then
                        local subCol = (cat.nameEnabled and cat.colorName) or (npcCat and npcCat.colorSubtitle) or { r = 1.0, g = 0.82, b = 0.0 }
                        uf.fncSubtitle:SetTextColor(subCol.r, subCol.g, subCol.b)
                    else
                        local useSubColor = (activeStyle == cat) or (activeStyle.subtitleEnabled ~= false)
                        if useSubColor then
                            local subCol = activeStyle.colorSubtitle or activeDefaultSub or { r = 1.0, g = 0.82, b = 0.0 }
                            uf.fncSubtitle:SetTextColor(subCol.r, subCol.g, subCol.b)
                        else
                            local fallbackCol = cat.colorSubtitle or cfg.defaultSubtitle or { r = 1.0, g = 0.82, b = 0.0 }
                            uf.fncSubtitle:SetTextColor(fallbackCol.r, fallbackCol.g, fallbackCol.b)
                        end
                    end
                    uf.fncSubtitle:ClearAllPoints()
                    uf.fncSubtitle:SetPoint("TOP", nameText, "BOTTOM", 0, -2)
                    uf.fncSubtitle:SetText(subtitle)
                    uf.fncSubtitle:Show()
                else
                    if uf.fncSubtitle then uf.fncSubtitle:Hide() end
                end
            else
                if uf.fncSubtitle then uf.fncSubtitle:Hide() end
            end

            return
        end
    end

    FNC:ResetUnitFrame(uf)
end

function FNC:ResetAllPlates()
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local uf = plate.UnitFrame or plate.unitFrame
        if uf and not uf:IsForbidden() and uf.unit then
            self:ResetUnitFrame(uf)
            if CompactUnitFrame_UpdateHealthColor then CompactUnitFrame_UpdateHealthColor(uf) end
            if CompactUnitFrame_UpdateName then CompactUnitFrame_UpdateName(uf) end
        end
    end
end

function FNC:RefreshAllPlates()
    self:SyncAllCVars()
    if not ForeverNamePlateColorsDB.enabled then
        self:ResetAllPlates()
        return
    end
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local uf = plate.UnitFrame or plate.unitFrame
        if uf and not uf:IsForbidden() and uf.unit then
            self:ResetUnitFrame(uf)
            if CompactUnitFrame_UpdateHealthColor then CompactUnitFrame_UpdateHealthColor(uf) end
            if CompactUnitFrame_UpdateName then CompactUnitFrame_UpdateName(uf) end
            self:UpdateUnitFrame(uf, uf.unit)
        end
    end
end

-- Hook into Blizzard's internal update functions so colors and headline states persist
if CompactUnitFrame_UpdateAll then
    hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
        if frame and frame.unit and not frame:IsForbidden() then
            FNC:UpdateUnitFrame(frame, frame.unit)
        end
    end)
end

if CompactUnitFrame_UpdateHealthColor then
    hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame)
        if frame and frame.unit and not frame:IsForbidden() then
            FNC:UpdateUnitFrame(frame, frame.unit)
        end
    end)
end

if CompactUnitFrame_UpdateName then
    hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
        if frame and frame.unit and not frame:IsForbidden() then
            FNC:UpdateUnitFrame(frame, frame.unit)
        end
    end)
end

if CompactUnitFrame_UpdateSelectionHighlight then
    hooksecurefunc("CompactUnitFrame_UpdateSelectionHighlight", function(frame)
        if frame and frame.unit and not frame:IsForbidden() then
            FNC:UpdateUnitFrame(frame, frame.unit)
        end
    end)
end

if CompactUnitFrame_UpdateLevel then
    hooksecurefunc("CompactUnitFrame_UpdateLevel", function(frame)
        if frame and frame.unit and not frame:IsForbidden() then
            FNC:UpdateUnitFrame(frame, frame.unit)
        end
    end)
end

if CompactUnitFrame_UpdateHealth then
    hooksecurefunc("CompactUnitFrame_UpdateHealth", function(frame)
        if frame and frame.unit and not frame:IsForbidden() then
            FNC:UpdateUnitFrame(frame, frame.unit)
        end
    end)
end

if CompactUnitFrame_UpdateClassificationIndicator then
    hooksecurefunc("CompactUnitFrame_UpdateClassificationIndicator", function(frame)
        if frame and frame.unit and not frame:IsForbidden() then
            FNC:UpdateUnitFrame(frame, frame.unit)
        end
    end)
end