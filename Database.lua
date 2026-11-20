--------------------------------------------------------------------------------
-- Database.lua
-- SavedVariables Initialization, Migration, and CVar Synchronization
--------------------------------------------------------------------------------

local addonName, FNC = ...

-- Deep-copy helper
function FNC.CopyColor(c)
    return { r = c.r, g = c.g, b = c.b }
end

function FNC.EnsureDefaults(db)
    if db.enabled == nil then
        db.enabled = true
    end
    if db.showErrors == nil then
        db.showErrors = false
    end
    if type(db.errorLog) ~= "table" then
        db.errorLog = {}
    end
    if type(db.cvars) ~= "table" then
        db.cvars = {}
    end
    for cvar, defaultVal in pairs(FNC.CVAR_DEFAULTS) do
        if db.cvars[cvar] == nil then
            db.cvars[cvar] = defaultVal
        end
    end

    if type(db.categories) ~= "table" then
        db.categories = {}
    end

    for _, cfg in ipairs(FNC.CATEGORY_CONFIG) do
        local cat = db.categories[cfg.key]
        if type(cat) ~= "table" then
            cat = {}
            db.categories[cfg.key] = cat
        end

        if cat.enabled == nil then
            cat.enabled = true
        end
        if cfg.hasHealthBarOption and cat.showHealthBar == nil then
            cat.showHealthBar = (cfg.defaultShowHealthBar ~= false)
        end
        if cfg.hasSubtitleOption and cat.showSubtitle == nil then
            cat.showSubtitle = (cfg.defaultShowSubtitle == true)
        end
        if cfg.hasHealthOption and cat.healthEnabled == nil then
            cat.healthEnabled = true
        end
        if cat.nameEnabled == nil then
            cat.nameEnabled = true
        end
        if cfg.hasHealthOption and type(cat.colorHealth) ~= "table" then
            cat.colorHealth = FNC.CopyColor(cfg.defaultHealth)
        end
        if type(cat.colorName) ~= "table" then
            cat.colorName = FNC.CopyColor(cfg.defaultName)
        end
        if cfg.hasSubtitleOption and type(cat.colorSubtitle) ~= "table" then
            cat.colorSubtitle = FNC.CopyColor(cfg.defaultSubtitle or { r = 1.0, g = 0.82, b = 0.0 })
        end

        -- Initialize nested subCategories (e.g., Personal / Party / Raid Friendly Minions)
        if cfg.subCategories then
            if type(cat.subCategories) ~= "table" then
                cat.subCategories = {}
            end
            for _, subCfg in ipairs(cfg.subCategories) do
                local subCat = cat.subCategories[subCfg.key]
                if type(subCat) ~= "table" then
                    subCat = {}
                    cat.subCategories[subCfg.key] = subCat
                end
                if subCat.enabled == nil then
                    subCat.enabled = (subCfg.defaultEnabled == true)
                end
                if subCat.healthEnabled == nil then
                    subCat.healthEnabled = true
                end
                if subCat.nameEnabled == nil then
                    subCat.nameEnabled = true
                end
                if subCat.subtitleEnabled == nil then
                    subCat.subtitleEnabled = true
                end
                if type(subCat.colorHealth) ~= "table" then
                    subCat.colorHealth = FNC.CopyColor(subCfg.defaultHealth)
                end
                if type(subCat.colorName) ~= "table" then
                    subCat.colorName = FNC.CopyColor(subCfg.defaultName)
                end
                if type(subCat.colorSubtitle) ~= "table" then
                    subCat.colorSubtitle = FNC.CopyColor(subCfg.defaultSubtitle or cfg.defaultSubtitle or { r = 1.0, g = 0.82, b = 0.0 })
                end
            end
        end
    end
end

-- Migrate older flat SavedVariables schema into db.categories
function FNC.MigrateDB(db)
    if type(db) ~= "table" then
        ForeverNamePlateColorsDB = {}
        db = ForeverNamePlateColorsDB
    end
    if type(db.categories) ~= "table" then
        db.categories = {}
    end

    if db.partyHealthEnabled ~= nil or db.colorPartyHealth or db.colorPartyName then
        db.categories.Party = db.categories.Party or {}
        if db.partyHealthEnabled ~= nil then db.categories.Party.healthEnabled = db.partyHealthEnabled end
        if db.partyNameEnabled ~= nil then db.categories.Party.nameEnabled = db.partyNameEnabled end
        if db.colorPartyHealth then db.categories.Party.colorHealth = FNC.CopyColor(db.colorPartyHealth) end
        if db.colorPartyName then db.categories.Party.colorName = FNC.CopyColor(db.colorPartyName) end
    end

    if db.raidHealthEnabled ~= nil or db.colorRaidHealth or db.colorRaidName then
        db.categories.Raid = db.categories.Raid or {}
        if db.raidHealthEnabled ~= nil then db.categories.Raid.healthEnabled = db.raidHealthEnabled end
        if db.raidNameEnabled ~= nil then db.categories.Raid.nameEnabled = db.raidNameEnabled end
        if db.colorRaidHealth then db.categories.Raid.colorHealth = FNC.CopyColor(db.colorRaidHealth) end
        if db.colorRaidName then db.categories.Raid.colorName = FNC.CopyColor(db.colorRaidName) end
    end

    db.partyHealthEnabled = nil
    db.partyNameEnabled = nil
    db.raidHealthEnabled = nil
    db.raidNameEnabled = nil
    db.colorPartyHealth = nil
    db.colorPartyName = nil
    db.colorRaidHealth = nil
    db.colorRaidName = nil
    db.matchNameToHealth = nil
    db.partyMatchNameToHealth = nil
    db.raidMatchNameToHealth = nil
end

-- Apply CVar setting safely (respecting master addon enabled state)
function FNC:ApplyCVar(cvarName, enabled)
    if not SetCVar then return end
    local val = (ForeverNamePlateColorsDB.enabled and enabled) and "1" or "0"
    pcall(SetCVar, cvarName, val)
end

function FNC:SyncAllCVars()
    if not ForeverNamePlateColorsDB or not ForeverNamePlateColorsDB.cvars then return end
    for _, item in ipairs(FNC.VISIBILITY_CVARS) do
        local isEnabled = ForeverNamePlateColorsDB.cvars[item.cvar]
        self:ApplyCVar(item.cvar, isEnabled)
    end
end