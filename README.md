# ForeverNamePlateColors

**ForeverNamePlateColors** is a lightweight, high-performance, and fully customizable nameplate and health bar color utility built specifically for **World of Warcraft Classic Era / Forever**. 

If you've ever lost track of your group members or wanted clearer visibility on friendly players and enemies during chaotic dungeon pulls, raid encounters, or busy World PvP skirmishes, this add-on is designed for you. By applying distinct, custom color coding to default nameplates, **ForeverNamePlateColors** makes every category of unit instantly recognizable at a glance.

---

## ✨ Features

* **Categorized Color Control:** Individually customize health bar and name text colors for:
  * **Party Members** (Your subgroup)
  * **Raid Members** (Other raid subgroups)
  * **Faction Members** (Same faction, non-party/raid)
  * **Hostile Faction** (Opposite faction players)
  * **Enemy Mobs**
  * **Quest NPCs & Neutrals**
* **Per-Category Master Toggles:** Completely disable overrides for any category with one click — untouched categories run 100% on Blizzard defaults.
* **Granular Channel Toggles:** Independently disable health color or name color for any category, allowing one channel to fall back to Blizzard defaults while the other stays custom.
* **One-Click Name & Health Matching:** Click "Match Name to Health Colors" in the global controls to quickly sync all name text colors to their respective health bar colors, while still keeping the freedom to customize individual names afterward.
* **Global Controls:** Bulk enable or disable all categories with dedicated global buttons, or toggle the entire addon.
* **Blizzard Options Integration:** Access a clean, organized two-tier configuration panel right from the standard WoW interface options (`/fnc`).
* **Zero Performance Impact:** Completely event-driven architecture. **No heavy `OnUpdate` polling loops**, ensuring your FPS stays buttery smooth even in crowded raids or capital cities.
* **Taint-Free Design:** Respects Blizzard's compact unit frames and updates cleanly via secure hooks.

---

## 📂 Installation

1. Download or clone the repository.
2. Ensure the folder name is exactly `ForeverNamePlateColors`.
3. Move the folder into your World of Warcraft AddOns directory:
   * **Classic Era / Forever:** `_forever_\Interface\AddOns\` or `_classic_era_\Interface\AddOns\`
4. Launch the game and ensure the add-on is enabled in your character selection screen.

---

## 🎮 Commands

Type any of the following commands in your chat window:

* **/fnc** — Opens the add-on options panel.
* **/fnc toggle** — Quickly enables or disables the add-on.

---

## ⚙️ Default Color Palette

* **Party (Subgroup):** `#A3A4FF` (`r = 0.6392, g = 0.6431, b = 1.0`)
* **Raid (Other Subgroups):** `#655EFF` (`r = 0.3961, g = 0.3686, b = 1.0`)
* **Faction Member:** `#655EFF` (`r = 0.3961, g = 0.3686, b = 1.0`)
* **Hostile Faction:** Pure Red (`#FF0000`)
* **Enemy Mob:** Pure Red (`#FF0000`)
* **Quest NPC:** Blizzard Neutral Green
* **Name Text:** Crisp White (`#FFFFFF`) — *can be independently customized, toggled off, or matched to health bar colors.*

---

## 🛠️ Author
* **Valerius Tombkeeper**
