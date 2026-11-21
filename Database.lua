--------------------------------------------------------------------------------
-- Database.lua
-- SavedVariables Migration, Defaults Initialization, and Combat-Safe CVar Sync
--------------------------------------------------------------------------------

local addonName, FNC = ...

function FNC.MigrateDB(db)
    if type(db) ~= "table" then return end

    if db.categories and db.categories.FriendlyPet then
        if not db.categories.FriendlyMinion then
            db.categories.FriendlyMinion = db.categories.FriendlyPet
        end
        db.categories.FriendlyPet = nil
    end

    if not db.colorParty and not db.colorEnemy then return end

    db.categories = db.categories or {}
    if FNC.LEGACY_KEY_MAP then
        for catKey, legacyKeys in pairs(FNC.LEGACY_KEY_MAP) do
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
    end
end

function FNC.EnsureDefaults(db)
    if type(db) ~= "table" then return end
    if db.enabled == nil then db.enabled = true end
    db.categories = db.categories or {}

    for _, cfg in ipairs(FNC.CATEGORY_CONFIG or {}) do
        local cat = db.categories[cfg.key] or {}
        if cat.enabled == nil then
            if cfg.defaultEnabled ~= nil then
                cat.enabled = cfg.defaultEnabled
            else
                cat.enabled = true
            end
        end
        if cat.healthEnabled == nil then cat.healthEnabled = true end
        if cat.nameEnabled == nil then cat.nameEnabled = true end
        if cfg.hasHealthBarOption then
            if cat.showHealthBar == nil then
                if cfg.defaultShowHealthBar ~= nil then
                    cat.showHealthBar = cfg.defaultShowHealthBar
                else
                    cat.showHealthBar = false
                end
            end
            if cfg.syncHealthBarWithEnabled and cat.enabled == false then
                cat.showHealthBar = false
            end
        end
        if cfg.hasSubtitleOption then
            if cat.showSubtitle == nil then cat.showSubtitle = true end
            if not cat.colorSubtitle then
                cat.colorSubtitle = FNC.GetDefaultSubtitle and FNC.GetDefaultSubtitle(cfg) or { r = 1, g = 0.82, b = 0 }
            end
        end
        if not cat.colorHealth then
            cat.colorHealth = FNC.GetDefaultHealth and FNC.GetDefaultHealth(cfg) or { r = 1, g = 1, b = 1 }
        end
        if not cat.colorName then
            local dn = cfg.defaultName or { r = 1, g = 1, b = 1 }
            cat.colorName = { r = dn.r, g = dn.g, b = dn.b }
        end

        if cfg.subCategories then
            if cat.advancedExpanded == nil then cat.advancedExpanded = false end
            cat.subCategories = cat.subCategories or {}
            for _, subCfg in ipairs(cfg.subCategories) do
                local subCat = cat.subCategories[subCfg.key] or {}
                if subCat.enabled == nil then
                    if subCfg.defaultEnabled ~= nil then
                        subCat.enabled = subCfg.defaultEnabled
                    else
                        subCat.enabled = false
                    end
                end
                if subCat.healthEnabled == nil then subCat.healthEnabled = true end
                if subCat.nameEnabled == nil then subCat.nameEnabled = true end
                if subCat.subtitleEnabled == nil then subCat.subtitleEnabled = true end
                if not subCat.colorHealth then
                    subCat.colorHealth = FNC.GetDefaultHealth and FNC.GetDefaultHealth(subCfg) or { r = 1, g = 1, b = 1 }
                end
                if not subCat.colorName then
                    local sdn = subCfg.defaultName or { r = 1, g = 1, b = 1 }
                    subCat.colorName = { r = sdn.r, g = sdn.g, b = sdn.b }
                end
                if not subCat.colorSubtitle then
                    subCat.colorSubtitle = FNC.GetDefaultSubtitle and FNC.GetDefaultSubtitle(subCfg) or { r = 1, g = 0.82, b = 0 }
                end
                cat.subCategories[subCfg.key] = subCat
            end
        end

        db.categories[cfg.key] = cat
    end
end

local pendingCVars = {}

local function IsSafeCVarValue(val)
    if issecretvalue and issecretvalue(val) then return false end
    return type(val) == "string" or type(val) == "number"
end

local function ReadCVarSafe(cvarName)
    if type(cvarName) ~= "string" then return nil end
    if C_CVar and C_CVar.GetCVar then
        local ok, val = pcall(C_CVar.GetCVar, cvarName)
        if ok and IsSafeCVarValue(val) then return tostring(val) end
    end
    if GetCVar then
        local ok, val = pcall(GetCVar, cvarName)
        if ok and IsSafeCVarValue(val) then return tostring(val) end
    end
    return nil
end

local function WriteCVarSafe(cvarName, targetVal)
    if ReadCVarSafe(cvarName) == nil then return end
    if ReadCVarSafe(cvarName) == targetVal then return end
    if C_CVar and C_CVar.SetCVar then
        pcall(C_CVar.SetCVar, cvarName, targetVal)
    elseif SetCVar then
        pcall(SetCVar, cvarName, targetVal)
    end
end

local cvarWatcher = CreateFrame("Frame")
cvarWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
cvarWatcher:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        for cvar, val in pairs(pendingCVars) do
            WriteCVarSafe(cvar, tostring(val))
        end
        wipe(pendingCVars)
    end
end)

local function SyncCVar(cvarName, enabled)
    if ReadCVarSafe(cvarName) == nil then return end
    local targetVal = enabled and "1" or "0"
    if InCombatLockdown and InCombatLockdown() then
        pendingCVars[cvarName] = targetVal
    else
        WriteCVarSafe(cvarName, targetVal)
    end
end

function FNC:SyncAllCVars()
    local db = ForeverNamePlateColorsDB
    if not db then return end
    local addonEnabled = db.enabled ~= false

    for _, cfg in ipairs(FNC.CATEGORY_CONFIG or {}) do
        local cat = db.categories and db.categories[cfg.key]
        local shouldEnable = addonEnabled and (cat and cat.enabled == true)

        if shouldEnable and cfg.enableParentCVars then
            for _, parentCvar in ipairs(cfg.enableParentCVars) do
                SyncCVar(parentCvar, true)
            end
        end

        if cfg.cvarSync then
            for _, cvar in ipairs(cfg.cvarSync) do
                SyncCVar(cvar, shouldEnable)
            end
        end
    end
end

ForeverNamePlateColorsDB = ForeverNamePlateColorsDB or {}
FNC.MigrateDB(ForeverNamePlateColorsDB)
FNC.EnsureDefaults(ForeverNamePlateColorsDB)