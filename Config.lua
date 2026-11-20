--------------------------------------------------------------------------------
-- Config.lua
-- Add-on Defaults, CVar Definitions, and Sectioned Category Registry
--------------------------------------------------------------------------------

local addonName, FNC = ...

-- Smooth horizontal rainbow gradient across "ForeverNamePlateColors" for chat output
local function BuildRainbowTitle(text)
    local stops = {
        { 1.00, 0.28, 0.28 }, -- Red
        { 1.00, 0.62, 0.18 }, -- Orange
        { 1.00, 0.90, 0.22 }, -- Yellow
        { 0.30, 0.92, 0.45 }, -- Green
        { 0.25, 0.85, 1.00 }, -- Cyan
        { 0.55, 0.55, 1.00 }, -- Indigo
        { 0.88, 0.45, 1.00 }, -- Violet
    }
    local len = #text
    local numSegments = #stops - 1
    local out = {}

    for i = 1, len do
        local t = (len > 1) and ((i - 1) / (len - 1)) or 0
        local scaled = t * numSegments
        local idx = math.min(math.floor(scaled) + 1, numSegments)
        local localT = scaled - (idx - 1)

        local c1, c2 = stops[idx], stops[idx + 1]
        local r = math.floor((c1[1] + (c2[1] - c1[1]) * localT) * 255 + 0.5)
        local g = math.floor((c1[2] + (c2[2] - c1[2]) * localT) * 255 + 0.5)
        local b = math.floor((c1[3] + (c2[3] - c1[3]) * localT) * 255 + 0.5)

        out[i] = string.format("|cFF%02X%02X%02X%s|r", r, g, b, text:sub(i, i))
    end

    return table.concat(out)
end

FNC.RAINBOW_TITLE = BuildRainbowTitle("ForeverNamePlateColors")

-- Nameplate Visibility CVars (managed in Settings)
FNC.VISIBILITY_CVARS = {
    { cvar = "nameplateShowFriendlyNPCs",     label = "Friendly NPCs",     default = false },
    { cvar = "nameplateShowFriendlyPets",     label = "Friendly Pets",     default = false },
    { cvar = "nameplateShowFriendlyMinions",  label = "Friendly Minions",  default = false },
    { cvar = "nameplateShowEnemyPets",        label = "Enemy Pets",        default = false },
    { cvar = "nameplateShowEnemyMinions",     label = "Enemy Minions",     default = false },
}

FNC.CVAR_DEFAULTS = {
    nameplateShowFriendlyNPCs    = false,
    nameplateShowFriendlyPets    = false,
    nameplateShowFriendlyMinions = false,
    nameplateShowEnemyPets       = false,
    nameplateShowEnemyMinions    = false,
}

-- Ordered Unit Categories (evaluated top-to-bottom; first match wins)
FNC.CATEGORY_CONFIG = {
    {
        section = "Friendly",
        key = "Party",
        label = "Party (Subgroup)",
        hasHealthOption = true,
        defaultHealth = { r = 0.639, g = 0.643, b = 1.0 },
        defaultName   = { r = 0.639, g = 0.643, b = 1.0 },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer)
            return isUnitPlayer and isSubgroup
        end,
    },
    {
        section = "Friendly",
        key = "Raid",
        label = "Raid (Other Subgroups)",
        hasHealthOption = true,
        defaultHealth = { r = 0.396, g = 0.369, b = 1.0 },
        defaultName   = { r = 0.396, g = 0.369, b = 1.0 },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer)
            return isUnitPlayer and isRaidMember and not isSubgroup
        end,
    },
    {
        section = "Friendly",
        key = "FactionMember",
        label = "Faction Member",
        hasHealthOption = true,
        defaultHealth = { r = 0.396, g = 0.369, b = 1.0 },
        defaultName   = { r = 0.396, g = 0.369, b = 1.0 },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack)
            return isUnitPlayer and not isEnemy and not canAttack
        end,
    },
    {
        section = "Friendly",
        key = "FriendlyMinion",
        label = "Friendly Minion",
        hasHealthOption = true,
        hasHealthBarOption = true,
        defaultShowHealthBar = true,
        hasSubtitleOption = true,
        subtitleLabel = "Show Owner",
        defaultShowSubtitle = false,
        defaultHealth = { r = 0.45, g = 0.85, b = 0.45 },
        defaultName   = { r = 0.45, g = 0.85, b = 0.45 },
        defaultSubtitle = { r = 0.72, g = 0.92, b = 0.72 },
        subCategories = {
            {
                key = "PersonalMinion",
                label = "Personal Minions / Pets",
                defaultEnabled = false,
                defaultHealth = { r = 0.25, g = 0.95, b = 0.85 },
                defaultName   = { r = 0.25, g = 0.95, b = 0.85 },
                defaultSubtitle = { r = 0.65, g = 0.98, b = 0.92 },
            },
            {
                key = "PartyMinion",
                label = "Party Minions / Pets (Subgroup)",
                defaultEnabled = false,
                defaultHealth = { r = 0.639, g = 0.643, b = 1.0 },
                defaultName   = { r = 0.639, g = 0.643, b = 1.0 },
                defaultSubtitle = { r = 0.80, g = 0.82, b = 1.0 },
            },
            {
                key = "RaidMinion",
                label = "Raid Minions / Pets (Other Subgroups)",
                defaultEnabled = false,
                defaultHealth = { r = 0.396, g = 0.369, b = 1.0 },
                defaultName   = { r = 0.396, g = 0.369, b = 1.0 },
                defaultSubtitle = { r = 0.70, g = 0.72, b = 1.0 },
            },
        },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack)
            return (not isUnitPlayer) and (not isEnemy) and (not canAttack)
                and (UnitPlayerControlled(unit) or (UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(unit)))
        end,
    },
    {
        section = "Friendly",
        key = "NPC",
        label = "NPC",
        hasHealthOption = true,
        hasHealthBarOption = true,
        defaultShowHealthBar = false,
        hasSubtitleOption = true,
        subtitleLabel = "Show Title",
        defaultShowSubtitle = false,
        defaultHealth = { r = 0.2, g = 0.9, b = 0.2 },
        defaultName   = { r = 0.2, g = 0.9, b = 0.2 },
        defaultSubtitle = { r = 1.0, g = 0.82, b = 0.0 },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack, uf)
            if isUnitPlayer or isEnemy or canAttack then return false end
            if UnitPlayerControlled(unit) or (UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(unit)) then return false end
            local activeQuestCat = ForeverNamePlateColorsDB and ForeverNamePlateColorsDB.categories and ForeverNamePlateColorsDB.categories["ActiveQuestUnit"]
            if activeQuestCat and activeQuestCat.enabled and FNC:IsActiveQuestUnit(unit, uf) then
                return false
            end
            return true
        end,
    },
    {
        section = "Neutral",
        key = "NeutralMob",
        label = "Neutral Mob",
        hasHealthOption = true,
        defaultHealth = { r = 1.0, g = 0.82, b = 0.0 },
        defaultName   = { r = 1.0, g = 0.82, b = 0.0 },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack, uf)
            if isUnitPlayer or isEnemy or not canAttack then return false end
            if UnitPlayerControlled(unit) or (UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(unit)) then return false end
            local activeQuestCat = ForeverNamePlateColorsDB and ForeverNamePlateColorsDB.categories and ForeverNamePlateColorsDB.categories["ActiveQuestUnit"]
            if activeQuestCat and activeQuestCat.enabled and FNC:IsActiveQuestUnit(unit, uf) then
                return false
            end
            return true
        end,
    },
    {
        section = "Hostile",
        key = "HostileFaction",
        label = "Hostile Faction",
        hasHealthOption = true,
        defaultHealth = { r = 1.0, g = 0.0, b = 0.0 },
        defaultName   = { r = 1.0, g = 0.0, b = 0.0 },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack)
            return isUnitPlayer and (isEnemy or canAttack)
        end,
    },
    {
        section = "Hostile",
        key = "HostileMinion",
        label = "Hostile Minion",
        hasHealthOption = true,
        hasSubtitleOption = true,
        subtitleLabel = "Show Owner",
        defaultShowSubtitle = false,
        defaultHealth = { r = 1.0, g = 0.35, b = 0.1 },
        defaultName   = { r = 1.0, g = 0.35, b = 0.1 },
        defaultSubtitle = { r = 1.0, g = 0.65, b = 0.45 },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack)
            return (not isUnitPlayer) and (isEnemy or canAttack)
                and (UnitPlayerControlled(unit) or (UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(unit)))
        end,
    },
    {
        section = "Hostile",
        key = "EnemyMob",
        label = "Enemy Mob",
        hasHealthOption = true,
        defaultHealth = { r = 1.0, g = 0.0, b = 0.0 },
        defaultName   = { r = 1.0, g = 0.0, b = 0.0 },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack, uf)
            if isUnitPlayer or not (isEnemy or canAttack) then return false end
            if UnitPlayerControlled(unit) or (UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(unit)) then return false end
            local activeQuestCat = ForeverNamePlateColorsDB and ForeverNamePlateColorsDB.categories and ForeverNamePlateColorsDB.categories["ActiveQuestUnit"]
            if activeQuestCat and activeQuestCat.enabled and FNC:IsActiveQuestUnit(unit, uf) then
                return false
            end
            return true
        end,
    },
    {
        section = "Quests",
        key = "ActiveQuestUnit",
        label = "Quest NPC / Mob",
        hasHealthOption = true,
        defaultHealth = { r = 1.0, g = 0.85, b = 0.0 },
        defaultName   = { r = 1.0, g = 0.85, b = 0.0 },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack, uf)
            if isUnitPlayer then return false end
            if UnitPlayerControlled(unit) or (UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(unit)) then return false end
            return FNC:IsActiveQuestUnit(unit, uf)
        end,
    },
}