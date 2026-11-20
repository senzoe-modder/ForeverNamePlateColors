--------------------------------------------------------------------------------
-- Config.lua
-- Category Definitions, UI Groupings, and Default Color Helpers
--------------------------------------------------------------------------------

local addonName, FNC = ...

-- Category Definitions (single source of truth)
-- Evaluated sequentially from top to bottom; first matching category claims the unit.
FNC.CATEGORY_CONFIG = {
    {
        key = "Party",
        group = "Friendly",
        label = "Party (Subgroup)",
        defaultHealth = { r = 0.6392, g = 0.6431, b = 1.0 },
        defaultName   = { r = 1.0,    g = 1.0,    b = 1.0 },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack)
            return isSubgroup
        end,
    },
    {
        key = "Raid",
        group = "Friendly",
        label = "Raid (Other Subgroups)",
        defaultHealth = { r = 0.3961, g = 0.3686, b = 1.0 },
        defaultName   = { r = 1.0,    g = 1.0,    b = 1.0 },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack)
            return (not isSubgroup) and isRaidMember
        end,
    },
    {
        key = "FriendlyPlayer",
        group = "Friendly",
        label = "Faction Member",
        defaultHealth = { r = 0.3961, g = 0.3686, b = 1.0 },
        defaultName   = { r = 1.0,    g = 1.0,    b = 1.0 },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack)
            return isUnitPlayer and (not isEnemy)
        end,
    },
    {
        key = "FriendlyMinion",
        group = "Friendly",
        label = "Friendly Minion",
        defaultEnabled  = false,
        defaultHealth   = { r = 0.3961, g = 0.3686, b = 1.0 },
        defaultName     = { r = 0.3961, g = 0.3686, b = 1.0 },
        defaultSubtitle = { r = 0.3961, g = 0.3686, b = 1.0 },
        defaultShowHealthBar = false,
        syncHealthBarWithEnabled = true,
        hasHealthBarOption = true,
        hasSubtitleOption  = true,
        subtitleLabel      = "Show Owner Tag",
        subtitleButtonLabel = "Tag Color",
        subtitleTooltip    = "Toggle displaying the minion's owner tag (e.g. <Player's Minion>) below their name.",
        cvarSync = {
            "nameplateShowFriendlyPlayerMinions",
            "nameplateShowFriendlyPlayerPets",
            "nameplateShowFriendlyPlayerGuardians",
            "nameplateShowFriendlyPlayerTotems",
            "nameplateShowFriendlyMinions",
            "nameplateShowFriendlyPets",
        },
        enableParentCVars = {
            "nameplateShowFriendlyPlayers",
            "nameplateShowFriends",
        },
        subCategories = {
            {
                key = "PersonalMinion",
                label = "Personal Minion",
                tooltip = "Override colors for your own summoned pets, demons, guardians, and totems.\nNote: Blizzard's default client only shows a nameplate for your own pet when targeted or enabled by client nameplate rules.",
                defaultEnabled  = false,
                defaultHealth   = { r = 1.0, g = 0.82, b = 0.0 },
                defaultName     = { r = 1.0, g = 0.82, b = 0.0 },
                defaultSubtitle = { r = 1.0, g = 0.82, b = 0.0 },
            },
            {
                key = "PartyMinion",
                label = "Party Minion (Subgroup)",
                tooltip = "Override colors for pets, demons, guardians, and totems belonging to players in your 5-man party or same raid subgroup.",
                defaultEnabled  = false,
                defaultHealth   = { r = 0.6392, g = 0.6431, b = 1.0 },
                defaultName     = { r = 0.6392, g = 0.6431, b = 1.0 },
                defaultSubtitle = { r = 0.6392, g = 0.6431, b = 1.0 },
            },
            {
                key = "RaidMinion",
                label = "Raid Minion (Other Subgroups)",
                tooltip = "Override colors for pets, demons, guardians, and totems belonging to raid members in other subgroups.",
                defaultEnabled  = false,
                defaultHealth   = { r = 0.3961, g = 0.3686, b = 1.0 },
                defaultName     = { r = 0.3961, g = 0.3686, b = 1.0 },
                defaultSubtitle = { r = 0.3961, g = 0.3686, b = 1.0 },
            },
        },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack)
            return (not canAttack) and (not isUnitPlayer) and (UnitPlayerControlled(unit) or (UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(unit)))
        end,
    },
    {
        key = "Hostile",
        group = "Enemy",
        label = "Hostile Faction",
        defaultHealth = { r = 1.0, g = 0.0, b = 0.0 },
        defaultName   = { r = 1.0, g = 1.0, b = 1.0 },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack)
            return isUnitPlayer and (isEnemy or canAttack)
        end,
    },
    {
        key = "HostileMinion",
        group = "Enemy",
        label = "Hostile Minion",
        defaultEnabled  = false,
        defaultHealth   = { r = 1.0, g = 0.0, b = 0.0 },
        defaultName     = { r = 1.0, g = 0.0, b = 0.0 },
        defaultSubtitle = { r = 1.0, g = 0.0, b = 0.0 },
        defaultShowHealthBar = false,
        syncHealthBarWithEnabled = true,
        hasHealthBarOption = true,
        hasSubtitleOption  = true,
        subtitleLabel      = "Show Owner Tag",
        subtitleButtonLabel = "Tag Color",
        subtitleTooltip    = "Toggle displaying the enemy minion's owner tag (e.g. <Player's Minion>) below their name.",
        cvarSync = {
            "nameplateShowEnemyMinions",
            "nameplateShowEnemyPets",
            "nameplateShowEnemyGuardians",
            "nameplateShowEnemyTotems",
        },
        enableParentCVars = {
            "nameplateShowEnemies",
        },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack)
            return (canAttack or isEnemy) and (not isUnitPlayer) and (UnitPlayerControlled(unit) or (UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(unit)))
        end,
    },
    {
        key = "ActiveQuestUnit",
        group = "Quests",
        label = "Quest NPC / Mob",
        defaultEnabled = true,
        defaultHealth  = { r = 1.0, g = 0.82, b = 0.0 },
        defaultName    = { r = 1.0, g = 0.82, b = 0.0 },
        enabledTooltip = "Enable or disable color overrides for NPCs and mobs tied to your active quest log.\nEvaluated before generic Enemy Mob and NPC rules.\nNote: Friendly Quest NPC nameplates require the NPC category (or Blizzard's Friendly NPC Nameplates) to be enabled.",
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack, uf)
            return (not isUnitPlayer) and FNC:IsActiveQuestUnit(unit, uf)
        end,
    },
    {
        key = "NPC",
        group = "Friendly",
        label = "NPC",
        defaultEnabled  = false,
        defaultHealth   = { r = 0.0, g = 1.0, b = 0.0 },
        defaultName     = { r = 0.0, g = 1.0, b = 0.0 },
        defaultSubtitle = { r = 0.0, g = 1.0, b = 0.0 },
        defaultShowHealthBar = false, -- Headline Mode by default for clean floating text
        hasHealthBarOption = true,
        hasSubtitleOption  = true,
        subtitleLabel      = "Show NPC Title",
        subtitleButtonLabel = "Title Color",
        subtitleTooltip    = "Toggle displaying the NPC's role or job title (e.g. <Innkeeper>, <Flight Master>) below their name.",
        cvarSync = { "nameplateShowFriendlyNPCs" },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack)
            return (not canAttack) and (not isUnitPlayer)
        end,
    },
    {
        key = "Enemy",
        group = "Enemy",
        label = "Enemy Mob",
        defaultHealth = { r = 1.0, g = 0.0, b = 0.0 },
        defaultName   = { r = 1.0, g = 1.0, b = 1.0 },
        match = function(unit, isSubgroup, isRaidMember, isUnitPlayer, isEnemy, canAttack)
            return canAttack and (not isUnitPlayer)
        end,
    },
}

FNC.UI_GROUPS = {
    { key = "Friendly", label = "Friendly" },
    { key = "Enemy",    label = "Enemy" },
    { key = "Quests",   label = "Quests" },
}

-- Migration mapping from legacy flat keys
FNC.LEGACY_KEY_MAP = {
    Party          = { health = "colorParty",          name = "colorPartyName" },
    Raid           = { health = "colorRaid",           name = "colorRaidName" },
    FriendlyPlayer = { health = "colorFriendlyPlayer", name = "colorFriendlyPlayerName" },
    Hostile        = { health = "colorHostile",        name = "colorHostileName" },
    Enemy          = { health = "colorEnemy",          name = "colorEnemyName" },
    NPC            = { health = "colorNPC",            name = "colorNPCName" },
}

function FNC.GetDefaultHealth(cfg)
    if cfg.defaultHealth then
        return { r = cfg.defaultHealth.r, g = cfg.defaultHealth.g, b = cfg.defaultHealth.b }
    end
    local defaultNPCCol = (FACTION_BAR_COLORS and FACTION_BAR_COLORS[5]) or { r = 0.0, g = 1.0, b = 0.0 }
    return { r = defaultNPCCol.r, g = defaultNPCCol.g, b = defaultNPCCol.b }
end

function FNC.GetDefaultSubtitle(cfg)
    local sub = cfg.defaultSubtitle or { r = 1.0, g = 0.82, b = 0.0 }
    return { r = sub.r, g = sub.g, b = sub.b }
end