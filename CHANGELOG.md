# Changelog v1.4.0
This is a big one!

### Added
* **Quest NPC & Mobs**
  * Highlights active enemy quest targets and friendly quest turn-in NPCs in bright quest gold/yellow so important quest units stand out immediately.
  * Automatically falls back to Blizzard's standard grey color when an enemy quest mob is tagged by another player.
  * Relies on Questie addon
* **Friendly Minions / Pets**
  * **Personal Minions / Pets:** Custom colors for your own summoned pets and demons.
  * **Party Minions / Pets:** Separate colors for pets belonging to members of your party or raid subgroup.
  * **Raid Minions / Pets:** Distinct colors for pets belonging to players in other raid subgroups.
  * **Owner Tags:** Option to display the owner's name beneath friendly pet nameplates.
* **Neutral Mobs**
  * Custom settings for Neutral Mob colors
* **Friendly NPCs & Hostile Minions**
  * Custom health bar and name colors for friendly/neutral NPCs and hostile player pets/minions.
  * **NPC Titles:** Restores NPC role subtitles (such as `<Innkeeper>` or `<Flight Master>`) underneath unit names.
* **Nameplate Visibility Controls**
  * Dedicated toggles in the settings menu to show or hide nameplates for friendly NPCs, friendly pets/minions, and enemy pets/minions.
* **Headline Mode (Name-Only Display)**
  * Option to hide health bars and level text on non-combatant categories (such as friendly NPCs and quest givers) to keep a clean floating-text look while using custom colors.

### Improved
* **Reorganized Settings Page**
  * **Friendly Section:** Groups Party, Raid, Faction Members, Friendly Minions, and NPCs into one dedicated section.
  * **Hostile Section:** Groups Hostile Faction, Hostile Minions, and Enemy Mobs into a separate section.
  * **Quests Section:** Groups Quest NPC's and Mobs in one
  * **Neutral Section:** Groups Quest NPC's and Mobs in one
  * Cleaner visual layout, per-category reset buttons, and smoother color customization.

# v1.4.1
* **Error Visibility**
  * Added `/fnc errors` and `/fnc clearerrors` to easily display and clear error log
* **Added Rainbow Griadient to title**
  * Added rainbow graident to the title (ForeverNamePlateColors) whenever it is displayed in chat (on load, toggle, errors)

### Future Planned Development
I don't know how much of this is possible, just listing ideas incase people read this lol
  * **Advanced Quest NPC & Mobs Settings** - Allow users to assign colors to NPCs, Neutral mobs, and Hostile mobs
  * **Nameplate View Distance Settings** - Easily change view distance for nameplates
  * **Assign minimap colors for party members** - Assign a color to each party member and easily distiguish who is who on the minimap
  * **Tagged Mob color** - Assign a color for mobs you or your party have tagged
