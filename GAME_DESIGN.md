# BEASTOPIA — Game Design & Reference

*A world of monsters. Your world of possibilities.*

This is the single source of truth for what Beastopia is and how it works. Every number here
comes from the code. When you change a system, update its section here too. File paths are
relative to `Beastopia/` (the app target).

**Contents**
1. [Overview](#1-overview)
2. [App structure](#2-app-structure)
3. [Lore and cast](#3-lore-and-cast)
4. [Story campaign](#4-story-campaign)
5. [Exploration](#5-exploration)
6. [Scanning](#6-scanning)
7. [Beasts](#7-beasts)
8. [Elements](#8-elements)
9. [Raising](#9-raising)
10. [Battle](#10-battle)
11. [Arena and multiplayer](#11-arena-and-multiplayer)
12. [Economy and items](#12-economy-and-items)
13. [Beast roster (105)](#13-beast-roster-105)
14. [Art and visual direction](#14-art-and-visual-direction)
15. [Audio](#15-audio)
16. [Code map](#16-code-map)
17. [Save data and stable IDs](#17-save-data-and-stable-ids)
18. [How-to: adding content](#18-how-to-adding-content)
19. [Known gaps](#19-known-gaps)
20. [Roadmap](#20-roadmap)
21. [Before launch: brand checklist](#21-before-launch-brand-checklist)

---

## 1. Overview

**Platform:** iOS (SwiftUI and SpriteKit). Game Center for online play. VisionKit for scanning.

**Core loop:** **Scan → Awaken → Raise → Evolve → Battle → Fuse → Scan again**

**Pillars**
- **Every code is a beast.** Any barcode or QR code in the real world summons a beast, and the same code gives the same beast on every device. This is the Monster Rancher disc mechanic.
- **Raise, don't just catch.** Stats, training, fatigue, bond and branching evolutions reward care.
- **A story worth following.** Eight regions, a mentor's secret and dialogue choices that come back later.
- **Fair multiplayer.** Battles are deterministic lockstep, so there's nothing to spoof or desync.

---

## 2. App structure

Five tabs (`ContentView.swift`):

| Tab | View | What it's for |
|---|---|---|
| Haven | `HavenView` | Keeper profile card, your beasts (30 max, more with Keeper rank), primary beast, training, feeding, evolution, absorb, sell, release, Beast Fusion, Bag |
| Scan | `ScanView` | Live camera scanner (QR and all barcode types), manual code entry, summon reveal, scanning tips |
| Story | `StoryView` → `RegionView` → `AdventureView` | Lattice Archive link (lore codex, §3), world map, region details, the walkable 2D world |
| Arena | `ArenaView` → `ArenaHallView` | Arena entrance; walk into the Arena Hall to start Practice, a Haven Raid or online matches (see §11) |
| Beastdex | `BeastdexView` → `SpeciesDetailView` | All 105 species, shown as silhouettes until discovered. A species is discovered when you own it, evolve into it, or meet it in any battle (wild, story, arena). Discovered species open a detail page: stats, moves, field abilities, and what each evolution before and after it changes. Undiscovered evolutions stay a blacked-out "???" with their requirements shown but their changes hidden |

**Settings** (`Views/SettingsView.swift`): a gear (`.settingsButton()`) at the top left of every tab opens the
`SettingsView` sheet. It replaced the Haven's old mute button.
- **Sound:** a master Sound switch, then Music, Sound Effects and Arena Crowd, each with an on/off switch and a
  volume slider (a multiplier on that channel's normal level). Letting go of the effects or crowd slider plays a sample.
- **Controls:** Map Movement, Tap to Walk or Joystick (the same setting the map uses).
- **Haptics & Motion:** Vibration (all haptics, including SwiftUI `sensoryFeedback`), and Reduce Battle Effects
  (no screen shake or hit jolts; lunges stay so it's clear who's acting).
- **Game Data & Tips:** Show Tips Again (clears the tutorial, fusion tip and collapsed-guide flags), and the app version.
- `GameSettings` holds the keys and readers. `GameSettings.applyAudio()` pushes changes to `MusicPlayer` and `SoundFX`.

Sheets shown from those screens: `BattleView`, `DialogueView`, `FacilitySheet` (stations and Market), `BagView`,
`QuestGuideSheet`, `FusionView`, `PrimaryBeastPicker`, `SummonRevealView`, `KeeperProfileView`,
`ChallengeCardSheet` (Arena, §11).

On every launch `ContentView` first plays `LoadingSequenceView` (about 7 s, tap to skip):
1. **SCANZ ent** studio card (`loading_scanz`), revealed top to bottom behind a teal scan line (1.2 s sweep, shown
   instantly with Reduce Motion), held to 2.5 s.
2. 0.7 s dissolve to the **BEASTOPIA** title (`loading_beastopia_clean`).
3. The `ui_guts_bar` frame fills with `ui_guts_bar_fill` over 2.8 s while Cindrop bounces (`loading_beast_1`…`_4`,
   8 fps). Both are drawn in code at the positions of the `loading_beastopia` mock-up. Then it fades into the game.

The game loads instantly, so the bar is timed rather than tied to real loading.

Then `ContentView` shows `KeeperCreationView` full screen until the player has made a character, on first launch
and for older saves without one (see §3, The Keeper).

**Screen backgrounds** (`.menuBackground(_:)` in `GameTheme.swift`): full-screen pixel art behind each screen.
Screens with a background switch to dark appearance so text stays readable.

| Background | Screen |
|---|---|
| `haven_background` (with a 35% dark scrim) | Haven tab |
| `menu_bg_main` | Scan, Story and Arena tabs |
| `menu_bg_beastdex` | Beastdex tab |
| `menu_bg_market` | Market |
| `menu_bg_settings` | Keeper profile |
| `menu_bg_title` | Keeper creation |

---

## 3. Lore and cast

### "The Silent Lattice"
Long ago, every beast roamed free. Then came the **Shattering**: the **Null**, a hunger from beyond the
world, began erasing beasts from existence. The first **Glyphkeepers** sealed every beast into the
**Codex Lattice**, the patterns hidden in the world's marks and codes. Every barcode and QR glyph is a lock
with a beast sleeping inside.

The player is a new Glyphkeeper. Their mentor, **Old Maren**, has vanished, leaving them her
**Beast Haven** and a **Lattice Lens**. The Lattice is going silent region by region. The **Null
Syndicate**, which Maren secretly founded, is feeding erased codes to **Oblivyrn, the Null Wyrm**. Maren meant
to feed the Null until it slept. Instead she woke it.

### Lattice Archive: in-game lore (`Models/Lore.swift`, `Views/LoreArchiveView.swift`)

The story will also be told as a **YouTube series**, so lore lives in a codex players fill in. It opens from the
top of the Story tab ("Lattice Archive · X of Y pages"). Locked pages show "???" with how to unlock them.
Unlocks are worked out from existing save data (`GameStore.isUnlocked(_:)`), so there's no new save field.

| Category | Pages | Unlocked by |
|---|---|---|
| The World | The Shattering, The Codex Lattice, Glyphkeepers | Start |
| | The Art of Fusion | Quest step `ch1-pip` |
| Maren's Journal | One page per chapter (`journal-1`…`journal-8`) | Completing that chapter |
| Episode Archives | One page per episode (`episode-<n>`) | Claiming that episode's code (§6) |
| Fusion Rumors | One per Mythic (`rumor-<mythicID>`), see §9 | The NPC talk step that tells it, or an episode |

A finished chapter counts all its steps as done, so older saves unlock their rumors too. Rumors show
"Solved: <Mythic>" once that Mythic is in the Beastdex. Lore page IDs are stable. Never rename them.

### The Keeper: the player character (`Models/Keeper.swift`, `Views/KeeperView.swift`)

The player creates a Glyphkeeper before playing: **name** (up to 16 characters), **figure** (Wanderer
`figure.walk`, Hiker `figure.hiking`, Sprinter `figure.run`), **signature color** (8 choices) and **class**.
The figure and color are used for the map sprite, the dialogue bubbles and the `KeeperAvatar` badge. Tap the
Haven's Keeper card to see the profile, swap gear and edit. Name and look are free to change. Changing
class costs **300 coins**.

Keepers never fight. Their **hero stats** boost every beast they send into battle:

| Hero stat | Boosts |
|---|---|
| Might | Power, Life |
| Wits | Intellect, Skill |
| Agility | Speed, Defense |

Each point is +1% to both linked beast stats, capped at **+30%** per stat. Hero stat = class base + (rank − 1) ×
growth ÷ 10 (rounded down) + gear.

| Class | ID | Focus (base 6, +0.6/rank) | Others (base 2, +0.2/rank) | Perk |
|---|---|---|---|---|
| Tamer | `tamer` | Might | Wits, Agility | Double bond from battles |
| Scholar | `scholar` | Wits | Might, Agility | +25% beast battle XP |
| Ranger | `ranger` | Agility | Might, Wits | +25% coins from battles |

**Keeper rank** (1–30). Reaching the next rank takes rank × 100 XP. Keeper XP comes from battle wins (20 + opponent
level × 2), losses (5), each quest step (40) and each chapter (150).

| Rank | Perk |
|---|---|
| 5, 15, 25 | +5 Haven slots each (Haven holds 30 → 45) |
| 10 | 10% off Market **coin** prices (items and gear) |
| 20 | Beasts earn +10% battle XP (stacks with Scholar) |

**How the boost works:** `GameStore.battleReady(_:)` returns a copy of the beast with boosted stats, and every
battle factory call site gets that copy (`AdventureView`, `RegionView`, `ArenaView`). `BattleEngine` doesn't know
about keepers. Online, the boosted beast is what goes in the `hello` message, so both peers simulate the same
fight and determinism holds. Rewards still go to the real beast by ID. Higher-rank keepers therefore have an
edge in online Versus.

**Dialogue:** lines can contain `{keeper}`, which `DialogueView` replaces with the player's name
(`String.personalized(for:)`). Player lines (`you(...)`) and choices show the keeper's name and avatar.

### Characters (`Models/WorldMap.swift`, `NPC`)

| Character | Title | Role |
|---|---|---|
| Pip | Haven Caretaker | Tutorial guide at the Haven |
| Elder Brasa | Caldera Village Elder | Asks for help with the raging fire beasts |
| Nell | Tidewhisper Fisher | Witness to the grey sea |
| Kade | Rival Glyphkeeper | Rival who becomes an ally; captured in ch. 6 |
| Ranger Ivy | Warden of the Wilds | Gatekeeper to the forest node |
| Wren | Skyreach Courier | Gets you aboard the Syndicate flagship |
| Rook | Syndicate Deserter | Leads you to Kade |
| Maren | Your Mentor | Syndicate founder; final confrontation |
| Commander Vey | Syndicate officer | Chapter 5 boss (Zephyrix) |

---

## 4. Story campaign

Defined in `Models/StoryCampaign.swift` (chapters) and `Models/WorldMap.swift` (quest steps and dialogue).
Chapters unlock in order. Each region's steps must be done in order, and beating the boss step completes
the chapter.

| # | Title | Region | Element | Boss (species, level) | Coins |
|---|---|---|---|---|---|
| 1 | The First Glyph | Beast Haven | Verdant | Haven Sprout (Sproutle, 2) | 100 |
| 2 | Embers of the Caldera | Emberfall Caldera | Ember | Feral Magmaw (Magmaw, 6) | 200 |
| 3 | Songs Under the Tide | Tidewhisper Coast | Tide | Kade's Tidecrest (Tidecrest, 10) | 300 |
| 4 | The Thorn Labyrinth | Greenmantle Wilds | Verdant | Warden Thornback (Thornback, 14) | 400 |
| 5 | Storm over Skyreach | Skyreach Peaks | Gale | Commander Vey's Zephyrix (Zephyrix, 18) | 500 |
| 6 | The Iron Quarry | Gravel Hollow | Terra | Syndicate Bouldrake (Bouldrake, 22) | 600 |
| 7 | Thunder at the Spire Gate | Voltmarsh | Volt | Gatekeeper Thundervex (Thundervex, 28) | 800 |
| 8 | The Silent Lattice | Null Spire | Umbra | Oblivyrn, the Null Wyrm (Oblivyrn, 35) | 2000 |

### Region elements (`Models/RegionElements.swift`)

Every story region is built around its element: a map mechanic in that element's style (§5, Element mechanics),
an **Element Glyph** holding a beast strong against the boss (§5), and a briefing that explains it all.

| # | Region | Element | What the element means here | Mechanic | Boss element → bring |
|---|---|---|---|---|---|
| 1 | Beast Haven | Verdant | Plants and growth: tough physical hitters that can Blight | Bramble Gate (tutorial) | Verdant → Ember, Gale |
| 2 | Emberfall Caldera | Ember | Fire and heat: hard special hitters that can Burn | Lava Geysers | Ember → Tide, Terra |
| 3 | Tidewhisper Coast | Tide | Water and sea: steady, and every one can Swim | The Tide | Tide → Verdant, Volt |
| 4 | Greenmantle Wilds | Verdant | Plants and growth | Thorn Labyrinth | Verdant → Ember, Gale |
| 5 | Skyreach Peaks | Gale | Wind and sky: fast, and every one can Fly | Mountain Winds | Gale → Ember, Volt |
| 6 | Gravel Hollow | Terra | Stone and earth: huge Defense, physical hitters | Quarry Boulders | Terra → Tide, Verdant |
| 7 | Voltmarsh | Volt | Lightning: quick special hitters that can Shock | Lightning Fence | Volt → Gale, Terra |
| 8 | Null Spire | Umbra | Shadow: Blink, physical, can Blight | The Silent Dark | Umbra → Lumen |

The text lives in `Element.blurb` and `Region.briefing` (`RegionBriefing`). "Bring" is `Element.weakTo` of the boss's
species element. Players see the briefing in two places:
- **Region screen:** `ElementBriefingCard` under the intro: strong vs, weak to, boss and what to bring, the mechanic,
  and the Element Glyph (or "awakened" once claimed).
- **First visit:** a one-time tutorial (`region.<id>` in `adventure.tutorialsSeen`) titled with the mechanic, covering
  the element, the mechanic, the boss's weakness and the glyph.

### Quest steps per region

| Region | Steps (objective ID: summary) |
|---|---|
| 1 Haven | `ch1-pip` talk to Pip → `ch1-pebblit` Stray Pebblit (Lv 1) → `ch1-boss` |
| 2 Caldera | `ch2-brasa` → `ch2-cindrop` Rampaging Cindrop (Lv 4) → `ch2-boss` |
| 3 Coast | `ch3-nell` → `ch3-ripplet` Grey-tide Ripplet (Lv 8) → `ch3-kade` → `ch3-boss` |
| 4 Wilds | `ch4-ivy` → `ch4-sproutle` Wild Sproutle (Lv 12) → `ch4-boss` |
| 5 Skyreach | `ch5-wren` → `ch5-fluffwing` Drained Fluffwing (Lv 15) → `ch5-boss` |
| 6 Quarry | `ch6-rook` → `ch6-pebblit` Quarry Guard Pebblit (Lv 19) → `ch6-kade` → `ch6-boss` |
| 7 Voltmarsh | `ch7-kade` → `ch7-sparkit` Overcharged Sparkit (Lv 24) → `ch7-boss` |
| 8 Null Spire | `ch8-maren` → `ch8-kade` → `ch8-nocturne` Null-touched Nocturne (Lv 32) → `ch8-boss` |

**Fusion in dialogue:** Pip's `ch1-pip` talk teaches Fusion (how to open it, the three kinds and that rumors get
written to the Archive). Every later region NPC's first talk includes one Fusion Rumor line (see §9).

Each step has a written clue in `Models/QuestGuide.swift`. The Quest Guide sheet also gives battle prep
advice: matchups, level gap warnings and fatigue warnings. **Show Me the Way** draws a breadcrumb trail to the target.

### Dialogue choices and story flags
Choices set flags (`GameStore.storyFlags`) that later lines check with `requires:` and `excludes:`.

| Flag | Set in | Read later |
|---|---|---|
| `asked.maren` | Ch 1, Pip (+50 coins) | not yet |
| `caldera.gentle` / `caldera.bold` | Ch 2, Brasa | not yet |
| `kade.friendly` / `kade.rival` | Ch 3, Kade | Ch 6 Kade, Ch 7 Kade, Ch 8 Kade |
| `sky.stealth` / `sky.direct` | Ch 5, Wren | `sky.stealth`: Ch 8 Maren |
| `rook.trusted` / `rook.doubted` | Ch 6, Rook | `rook.trusted`: Ch 7 Kade |
| `maren.forgiven` / `maren.blamed` | Ch 8, Maren | `maren.forgiven`: Ch 8 Kade |

---

## 5. Exploration

`Engine/AdventureScene.swift` (SpriteKit), `Views/AdventureView.swift`, `Models/AdventureMap.swift`.

### Controls
- **Tap to Walk:** tap a tile and the player pathfinds there (breadth-first search). Taps on walls snap to the nearest walkable tile.
- **Joystick:** hold a direction. It slides along walls and gets pulled into doorways. The **A** button talks to or uses whatever is in front of you.
- Tapping an NPC, boss or station walks over and interacts, in either mode.
- Moves are tile-by-tile, 0.2 s per step, with a small hop.
- Your position in each region is saved when you leave. On return you spawn there, **unless** you couldn't walk
  from it back to the region's start with your current beasts (for example, you saved on a water chest and then
  sold your only Tide beast). In that case you spawn at the start (`AdventureView.spawnTile()`).

### HUD and hints
- **Quest banner** (top): the current step in up to two lines, ability chips, the region name and a compass. Tap it
  for the Quest Guide. The chevron folds it down to just the compass (remembered in `adventure.guideCollapsed`).
- **Toasts** appear low on the screen, above the controls, so they don't cover the map. They use `PixelTextBox`
  (pixel font, typed out letter by letter) so messages feel part of the 2D world.
- **Region title card:** `PixelTitleCard` shows "~ REGION NAME ~" for 2.2 s whenever you enter a region.
- **Tutorials:** one-time `PixelTextBox` pop-ups over a dimmed map; tap to continue. The map ignores input while
  one is showing. Each is shown once ever (IDs stored in `adventure.tutorialsSeen`):
  - `unlock.swim` / `unlock.fly` / `unlock.teleport`: the first time you have a beast that lends the ability, it
    explains how to use it (walk onto water for Swim/Fly; tap past a wall, or the Blink button, for Blink) and that
    any Haven beast lends it, not just the primary.
  - `chest.<ability>.ready` / `chest.<ability>.locked`: the first time you come within 6 tiles of an unopened chest
    that needs Swim, Fly or Blink, it explains how to reach it, or which element of beast you need. Later visits show a
    short toast instead, once per chest per visit.
- The "Tap to walk" reminder fades after 5 seconds.
- **Blink** is only needed for the walled-in chests (`t4-hollow`, `t5-ledge`, `t6-cell`). Tapping a spot you can't
  walk to explains Blink, or says you're out of range (5 tiles) if you have it.

### Terrain
Maps are written as text grids (about 20×16 tiles, 48 pt per tile on screen).

| Char | Terrain | Walkable | Notes |
|---|---|---|---|
| `.` | grass | yes | |
| `,` | tall grass | yes | Wild encounters |
| `=` | path | yes | Exits are carved as path tiles |
| `F` | flowers | yes | |
| `T` | tree / rock | no | Casts a shadow on the tile below |
| `~` | water / lava / chasm / void | ability | See field abilities |
| `#` | fence | no | |
| `H` | building | no | |

Each **map theme** dresses the same terrain differently (`MapTheme.look(for:)`): meadow, volcano, coast,
forest, peaks, quarry, marsh and spire, plus `interior` for inside buildings (it never falls back to the outdoor
`tile_<terrain>` art). On volcano, peaks and spire, "water" is lava, a chasm or the void, and needs **Fly**.

### Field abilities
Lent by any beast in your Haven. The primary beast is preferred, otherwise the highest-level beast that has the ability.

| Ability | Who has it | Effect |
|---|---|---|
| Swim | Every Tide beast | Cross real water (meadow, coast, forest, quarry, marsh) |
| Fly | Every Gale beast, plus Pyrowl, Solaryx, Aurorion | Cross any water, lava, chasm or void |
| Blink | Every Lumen and Umbra beast, plus Chronodrake | Teleport up to 5 tiles past obstacles (tap beyond a wall, or press Blink) |

### Wild encounters (tall grass)
- While a **defeat** quest step is active: **30%** chance per tall-grass step that the quest's beast appears.
- Otherwise: **8%** chance per step for a random beast from the region's wild list, at the chapter boss's level − 1.
- You can run from wild and quest battles. You can't run from bosses.

### Regions

| ID | Region | Theme | Stations | Treasure (ability needed: loot) | Wild species | Exits to |
|---|---|---|---|---|---|---|
| 1 | Beast Haven | meadow | Stable, Feeding Trough, Hot Spring, Training Post, Market | `t1-orchard` (none: 3 Glow Berry, 30 coins); `t1-pond` (Swim: 2 Healing Draught, Remedy Herb, 1 shard) | Pebblit, Sproutle, Glimmet | 2 |
| 2 | Emberfall Caldera | volcano | (Inn and Market indoors) | `t2-lava` (Fly: 2 Guts Tonic, Lattice Candy, 1 shard) | Cindrop, Pebblit | 1, 3 |
| 3 | Tidewhisper Coast | coast | (Inn and Market indoors) | `t3-sea` (Swim: 2 Healing Draught, Bond Treat, 80 coins) | Ripplet, Glimmet | 2, 4 |
| 4 | Greenmantle Wilds | forest | Campfire | `t4-hollow` (Blink: Star Candy, 2 Remedy Herb, 1 shard) | Sproutle, Shadeling | 3, 5 |
| 5 | Skyreach Peaks | peaks | Campfire | `t5-nest` (Fly: 2 Healing Draught, 2 Calm Tea, 120 coins); `t5-ledge` (Blink: Full Elixir, 2 shards) | Fluffwing, Sparkit | 4, 6 |
| 6 | Gravel Hollow | quarry | Campfire | `t6-pit` (Swim: 2 Lattice Candy, 150 coins); `t6-cell` (Blink: Full Elixir, Guts Tonic, 2 shards) | Pebblit, Cindrop | 5, 7 |
| 7 | Voltmarsh | marsh | Campfire | `t7-bog` (Swim: 3 Healing Draught, 2 Remedy Herb, 2 shards) | Sparkit, Ripplet | 6, 8 |
| 8 | Null Spire | spire | Campfire | `t8-void` (Fly: 2 Full Elixir, Star Candy, 3 shards) | Shadeling, Glimmet | 7 |

### Buildings (`Doorway`, `AdventureMap.doors`, `AdventureMap.interior(_:regionID:)`)

Some buildings can be entered. The door is the middle tile of the building's front wall (where the door art is
drawn). Walking onto it goes inside. Inside is a small 12×9 room (theme `.interior`: plank floor, rugs, plants,
counters) with the region's music. Walking out the bottom door returns you to the tile just outside. While inside,
the quest banner says so, the compass hides, and your saved position is the tile outside the door.

| Region | Door tile | Building | Kind |
|---|---|---|---|
| Beast Haven | (15, 3) | Maren's Barn | Inn |
| Emberfall Caldera | (2, 11) | Cinder Inn | Inn |
| Emberfall Caldera | (17, 11) | Glassblowers' Market | Market |
| Tidewhisper Coast | (4, 11) | Fisher's Rest | Inn |
| Tidewhisper Coast | (14, 12) | Sea-Glass Shop | Market |
| Voltmarsh | (3, 13) | Stormwatch Post | Market |

- **Inn:** an Innkeeper desk (`.inn`, rests the whole team) and a Hot Spring bath.
- **Market:** a shop counter (`.market`, the normal Market list including Keeper Gear).
- The Caldera and Coast Markets moved indoors (their outdoor stalls are gone). Pip moved to (13, 4) and Nell to
  (6, 12) so they don't stand in front of doors. The Wilds, Skyreach, Quarry and Spire have no enterable buildings.

### Element mechanics (`ElementFeatures`, `FieldState`, `FieldTiming` in `Models/FieldFeatures.swift`)

Each region's element shapes its map. `AdventureMap.features` holds the static layout; `FieldState` is what changes
during a visit (boulders, filled water, lit blooms, brambles, tide). `canEnter`/`path` take a state, and
`AdventureScene` keeps the live one. Everything except solved brambles resets when you leave the region.

| Region | Mechanic | How it works |
|---|---|---|
| Haven | **Bramble Gate** | Brambles at (12, 10–11) seal the training yard. Step on the bloom at (3, 7) to open them. Opening is saved (`p1-brambles`) |
| Caldera | **Lava Geysers** | Six geysers across the lava-river gap (row 7, cols 7–12). Each erupts 1.1 s of every 3 s, offset so they go off in a rolling wave. Walking into an erupting geyser stuns you (0.6 s); one erupting under you knocks you back a tile |
| Coast | **The Tide** | Every 14 s the tide is high for 6 s. The sandbar (15, 3–4) out to a little island floods. Without Swim (or Fly) you're washed back to the nearest dry tile |
| Wilds | **Thorn Labyrinth** | Brambles at (9–10, 6) seal the path to the node and boss. Light both blooms, (1, 1) and (18, 1), to open them. Saved (`p4-brambles`) |
| Skyreach | **Mountain Winds** | Gust tiles carry you one tile in their direction, chained and even over the chasm. An updraft at (15, 4)→(15, 3)→(15, 2) lands on a sky island; a downdraft at (16, 3)→(16, 4) brings you back. You can't walk against a gust |
| Quarry | **Quarry Boulders** | Walk into a boulder (or tap it) to push it one tile. Boulders can't go onto doors, exits, chests, the glyph or hazards. Pushed into water, a boulder fills it and it becomes ground. One at (15, 11) blocks the glyph's cell; two more at (6, 12) and (13, 3) |
| Voltmarsh | **Lightning Fence** | Arcs across the whole marsh on row 9 (cols 1–18), each live 0.9 s of every 2 s in a west-to-east wave, plus two guarding the glyph at (17, 5) and (18, 6). Same stun and knockback as geysers |
| Spire | **The Silent Dark** | Darkness covers the map except a soft circle around you: radius 2.6 tiles, or 4.5 with any Lumen beast in the Haven. The Element Glyph glows through the dark |

Pathfinding understands gusts (from a gust tile you can only go where it blows), treats boulders and closed
brambles as walls, and plans through geysers and arcs, so a walk can be interrupted by an eruption. The scene
reports `AdventureScene.FieldEvent`s, and `AdventureView` turns them into toasts and sounds. Hazard toasts appear at
most every 3 s. The Quest Guide clues for `ch1-boss`, `ch2-boss`, `ch4-boss` and `ch7-boss` mention the mechanic.

### Element Glyphs (`ElementGlyph`, `GameStore.claim(_:)`, `BeastGenerator.generate(glyph:)`)

Each story region hides one glyph stone, usually reached by mastering the region's mechanic. Stepping on it plays
the summon cutscene and awakens a **Rare** beast whose element is strong against the region's boss. Its stats
are scaled to its level like a story opponent (total 260 + 25 × level), and its origin tag is "Element Glyph".
Each glyph can be claimed once per save. If the Haven is full, the glyph waits.

| Region | Glyph ID | Tile | Beast (Lv) | Why it helps | Reached by |
|---|---|---|---|---|---|
| Haven | `g1-haven` | (14, 9) | Charbug (1) | Ember vs Sproutle ×1.35 | Opening the Bramble Gate |
| Caldera | `g2-caldera` | (5, 3) | Shellbe (2) | Tide vs Magmaw ×1.73 | Crossing the geysers |
| Coast | `g3-coast` | (16, 2) | Zaplet (6) | Volt vs Tidecrest ×1.5 | The sandbar at low tide |
| Wilds | `g4-wilds` | (7, 1) | Galeharrier (10) | Gale vs Thornback ×1.5 | Lighting both blooms |
| Skyreach | `g5-skyreach` | (17, 1) | Blazefang (14) | Ember vs Zephyrix ×1.5 | Riding the updraft |
| Quarry | `g6-quarry` | (15, 10) | Glaciaray (18) | Tide vs Bouldrake ×1.73 | Pushing the boulder aside |
| Voltmarsh | `g7-voltmarsh` | (18, 5) | Crystalback (24) | Terra vs Thundervex ×1.5 | Timing the guarding arcs |
| Spire | `g8-spire` | (2, 9) | Starmane (31) | Lumen vs Oblivyrn ×1.04 (Lumen and Umbra are strong against each other) | Finding it in the dark |

The Haven glyph is Ember rather than Gale (×1.5) on purpose: every Gale beast lends Fly, which would let new keepers
fly over the Caldera's lava and skip its geysers. The reveal shows a banner: "Element Glyph of <region>: <element>
is strong against <boss>."

### Stations (`Facility`, `Views/FacilityView.swift`)

| Station | Effect |
|---|---|
| Stable | Rest: fatigue −40, bond +1 |
| Feeding Trough | Feed: fatigue −10, bond +5 (+8 for Gentle beasts) |
| Hot Spring | 30 coins: clears all fatigue, bond +2 |
| Training Post | Beast Training drills |
| Market | Buy items (see §12) |
| Campfire | Same as the Stable: fatigue −40, bond +1 |
| Innkeeper (inside Inns) | 20 coins (`GameStore.innCost`): every beast's fatigue to 0, bond +1. Refused if nobody is tired |

---

## 6. Scanning

`Engine/BeastGenerator.swift`, `Views/ScanView.swift` (VisionKit `DataScannerViewController`, all barcode
types, torch toggle, manual entry as a fallback).

The code payload is trimmed and hashed with **SHA-256**. Specific bytes decide the beast:

| Byte(s) | Decides |
|---|---|
| 0–3 | Origin tag shown on the beast, e.g. `#A1B2C3D4` |
| 8 | Rarity |
| 9 | Element (non-mythic) or which Mythic |
| 19 | Which rookie family within that element |
| 10 | Trait |
| 11 | Hue shift (−30° to +30°) |
| 12 | Prismatic variant if `== 0` (1 in 256) |
| 13–18 | ±15% variance on each of the six stats |

**Rarity** (byte 8):

| Rarity | Byte range | Chance | Stat boost |
|---|---|---|---|
| Common | 0–139 | 54.7% | ×1.00 |
| Uncommon | 140–199 | 23.4% | ×1.08 |
| Rare | 200–235 | 14.1% | ×1.16 |
| Epic | 236–251 | 6.3% | ×1.25 |
| Mythic | 252–255 | 1.6% | ×1.40 (rolls from the 8 Mythics) |

### Episode codes (`EpisodeCatalog` in `Models/Lore.swift`)
Each YouTube episode shows a code on screen. Viewers can scan it from another screen or **type it** on the Scan tab.
This matters because many people watch on the same phone they play on. Matching ignores case, spaces, dashes and
underscores (`EpisodeCatalog.canonical`). An episode code skips the hash roll and always gives that episode's
**species and rarity**. Trait, hue and stat variance still come from the code's hash, and it's never Prismatic.
The origin tag is "Episode N". The summon reveal shows an episode banner and the archive page it unlocked. A code
is claimed once per save, by the fingerprint of its canonical form.

| # | Title (draft) | Code (draft) | Beast | Rarity | Also unlocks |
|---|---|---|---|---|---|
| 1 | Maren's Last Lesson | `EP01-GLYPH-7KQ2` | Prismpup | Rare | `rumor-halostorm` |
| 2 | The Boy Who Hated Tides | `EP02-TIDE-4MZ8` | Puddlepup | Rare | — |
| 3 | The First Glyphkeepers | `EP03-NULL-9RX5` | Gloomkit | Epic | — |

These are placeholders. Change titles and codes to match the real episodes **before they air**, and never change
a code afterwards. To add an episode, add an `Episode` to `EpisodeCatalog.episodes` and an `episode-<n>` page
to `LoreArchive`. The codes are plain strings in the app, so dataminers can find them.

### Challenge Cards
A code starting with `BEASTOPIA-DUEL:` is a Challenge Card (§11), not a summon. The Scan tab asks
"<keeper> challenges you: <species>, Lv N. Fight with <primary beast>?" and starts the ghost battle. A damaged card
is refused.

Rules:
- Every code can be claimed **once per save**. Only a one-way fingerprint is stored, never the raw payload.
- The Haven holds **30** beasts. Scans are refused when it's full.
- Your first beast comes with a starter kit: 3 Glow Berries and 1 Remedy Herb.
- Non-mythic scans pick the element first, then one of that element's four rookie families.

---

## 7. Beasts

`Models/Beast.swift`, `Models/Element.swift`, `Models/Species.swift`, `Models/SpeciesExpansion.swift`.

### Stages
Rookie (from scans) → Adult (Lv 10–12) → Apex (Lv 25, Bond 50). Mythics are their own stage.
Base stat totals are roughly: rookie ~288, adult ~585 (final-form adults ~680), apex ~1020, mythic ~900.

### Stats (cap 999)

| Stat | Short | Used for |
|---|---|---|
| Life | LIF | Max HP = 40 + LIF×2 + level×4 |
| Power | POW | Physical attack |
| Intellect | INT | Special attack, and half of special defense |
| Defense | DEF | Physical defense, and half of special defense |
| Speed | SPD | Turn order, dodging |
| Skill | SKI | Accuracy, critical chance |

### Traits (byte 10)

| Trait | Favored stat (×1.5 training) | Notes |
|---|---|---|
| Brave | POW | |
| Clever | INT | |
| Sturdy | DEF | |
| Swift | SPD | |
| Precise | SKI | |
| Hardy | LIF | Training fatigue +8 instead of +12 |
| Wild | POW | Training fatigue +18 |
| Gentle | LIF | Feeding gives +8 bond instead of +5 |

### Condition
- **Bond (0–100):** starts at 10. At **30** the hidden element is revealed. Apex evolutions need **50**.
- **Fatigue (0–100):** reduces training gains (see §9). Battles add +15.
- **Level:** 1–99. XP to the next level = level × 50. Each level adds max(1, base÷25) + 0–2 to every stat.
- **Primary beast:** leads in adventures, is the default fighter, and is first choice to lend field abilities.

---

## 8. Elements

Eight elements. Every species has a visible element and a **hidden** one.

| Attacker | Strong against (×1.5) |
|---|---|
| Ember | Verdant, Gale |
| Tide | Ember, Terra |
| Verdant | Tide, Terra |
| Gale | Verdant, Volt |
| Terra | Volt, Ember |
| Volt | Tide, Gale |
| Lumen | Umbra |
| Umbra | Lumen |

- If the defender's element is strong against the attacker's: **×0.67**.
- Hidden element: ×1.15 if the attacker is strong against it, ×0.9 if it resists the attacker.
- Using a move of your own element (same-type bonus): **×1.2**.
- Status ailments: Ember → **Burn**, Volt → **Shock**, Verdant and Umbra → **Blight**.

---

## 9. Raising

`Engine/RanchEngine.swift`, `Views/HavenView.swift`.

| Action | Effect |
|---|---|
| Train a stat | Gain = (3–7) × 1.5 if it's the trait's favored stat × fatigue factor max(0.2, 1 − fatigue/120). Fatigue +12 (Wild +18, Hardy +8), bond +1, +20 XP |
| Rest | Fatigue −40, bond +1 |
| Feed | Fatigue −10, bond +5 (Gentle +8) |
| Hot Springs (30 coins) | Clears all fatigue, bond +2 |
| Royal Feast (50 coins) | Bond +15, fatigue −20 |
| Growth Elixir (20 + level×10 coins) | Instantly gain a level |
| Evolve | When the requirements are met: stats gain the base-stat difference between stages, bond +10 |
| Absorb | Merge a donor into a beast: +(40 + donor level×25) XP. Same evolution line: ×2 XP, +10% of the donor's stats, bond +5. Prismatic carries over |
| Sell | 10 + level×4 + (rarity+1)×15 + stage×20 coins (+200 if Prismatic) |
| Release | The beast returns to the Lattice |

**Branching evolution:** some rookies have two adult forms. The first path whose requirements are met
wins, and a path can require a **dominant stat** (the beast's highest stat). Example: Cindrop becomes
Pyrowl if INT is its highest stat, otherwise Magmaw.

**What evolving changes** (`RanchEngine.evolutionChanges(from:to:)`, shown by `EvolutionChangesView`):
- **Stat upgrades:** each stat gains the positive base-stat difference between the two forms. Stats never drop.
- **Moves:** the new form's signature move replaces the old one. If the element changes, the elemental move is replaced too.
- **Field abilities:** gained or lost with the new species (e.g. Cindrop → Pyrowl gains Fly).
- **Bond:** +10.

Where players see this:
- **Beastdex detail:** a "Before" section (what it evolves from, and what that evolution changed) and an "After" section (each evolution and its changes). Undiscovered forms show as a silhouette named "???" with only the requirements.
- **Haven beast page:** each evolution path shows a portrait (silhouette if undiscovered), its requirements and what's still missing (e.g. "Needs 3 more levels · Bond 12/40"), and can be expanded to preview the changes using the beast's own current stats (hidden for undiscovered forms). When a beast is ready, the Evolution section moves to the top with a big Evolve button ("Evolve!" if the form is still unknown).

How players learn a beast is ready to evolve:
- A numbered **badge on the Haven tab** (`GameStore.readyToEvolve`).
- A gold **"Ready to Evolve!" banner** per beast at the top of the Haven, which opens its page.
- The **battle results** panel says "<name> is ready to evolve! Visit the Haven."
- The sparkles icon on its `BeastCard`.
- **After evolving:** `EvolutionResultSheet` shows the before → after forms and exactly what changed.

### Beast Fusion
How players learn it: Pip explains it in Chapter 1. A one-time **"You can fuse beasts!"** tip card shows in the
Haven once you have 2 beasts (`@AppStorage("haven.fusionTipSeen")`, cleared by Try Fusion, Got It or opening
Fusion). `FusionView` has a "How Fusion works" panel, a preview of the result for every pairing (Mythic,
Bloodline or new rookie, via `RanchEngine.freshFusionSpecies`), and the **Fusion Rumors** you've heard.

| Mythic | Recipe | Rumor told by |
|---|---|---|
| Magmarch | Ember + Terra | Elder Brasa (`ch2-brasa`) |
| Vaporgeist | Ember + Tide | Nell (`ch3-nell`) |
| Sylvanwyrm | Verdant + Gale | Ranger Ivy (`ch4-ivy`) |
| Aurorion | Lumen + Gale | Wren (`ch5-wren`) |
| Chronodrake | Terra + Umbra | Rook (`ch6-rook`) |
| Maelstryx | Tide + Volt | Kade (`ch7-kade`) |
| Halostorm | Volt + Lumen | Episode 1 code only |
| Oblivyrn | Umbra + Umbra | Maren (`ch8-maren`) |

- **Mythic reveal** (`Views/MythicSummon.swift`, `MythicSummonCutscene`): any Mythic, whether scanned, fused or from
  a glyph, gets its own cutscene instead of the normal one (about 6 s). The screen goes black, a golden glyph rises inside a
  ring of runes, the two fusion parents (when there are any) spiral into it, then it charges and shakes, lightning
  strikes three times, a pillar of light flashes white, and the Mythic bursts out with shockwave rings, a halo in both its elements'
  colors, rising embers and a "MYTHIC" title slam. Sounds: `guardUp`, `fuse`, `levelUp`, `hit`/`critical`, the
  `sting_evolve` sting (or `evolve`) and `roar`, with heavy haptics. The reveal screen is black and gold: the name,
  its epithet (`Species.mythicEpithet`, e.g. Halostorm "Crown of Living Thunder"), both element badges, its rarity
  power (×1.40), stat total and signature move. Reduce Motion skips straight to the reveal.
- **Mythic recipe:** both parents Lv **15+** and their elements match a Mythic's element pair (see §13). The child is that Mythic with Mythic rarity.
- **Bloodline fusion** (same evolution line, no recipe): keeps the more evolved form and the higher level. Each stat = best + worst÷5. 50% chance of a rarity upgrade (up to Epic). 1/64 Prismatic chance. The weaker parent's absorb XP is added.
- **Different lines:** a new rookie of the stronger parent's element, base stats + 15% of the parents' average. Rarity = higher parent, with a 25% chance of an upgrade (up to Epic). 1/128 Prismatic chance. Bond 20.

---

## 10. Battle

`Engine/BattleEngine.swift`, `Engine/BattleSession.swift`, `Views/BattleView.swift`.

### Moves (every beast has four)

| Move | Type | Power | Accuracy | Guts |
|---|---|---|---|---|
| Strike | physical, no element | 40 | 95 | 10 |
| Elemental move (e.g. Flare Burst) | element's default kind | 60 | 90 | 25 |
| Signature move | per species (§13) | 50–110 | 85 | 18–50 |
| Guard | — | — | — | 0, restores +15 Guts and halves damage taken |

Physical elemental moves: Terra, Verdant and Umbra. Everything else is special.

### Guts
Start at 50, max 100, +12 regenerated per turn. If you choose a move you can't afford, it becomes Guard.

### Turn order
1. Every action is locked in first.
2. Items resolve before anyone attacks.
3. Faster beasts (SPD) act first, with a seeded tiebreak.
4. Ailments tick at the end of the turn, then Guts regenerate.

### Formulas
- **Hit chance** = clamp(accuracy + (attacker SKI − defender SPD) ÷ 10, 50, 100)
- **Damage** = power × ATK ÷ (DEF + 40) × 0.9 + 3, then × same-type bonus × element multiplier × random 0.85–1.0
  - Physical: ATK = POW, DEF = DEF. Special: ATK = INT, DEF = (DEF + INT) ÷ 2
- **Critical** chance = min(SKI, 250) ÷ 1000 (25% at most), ×1.5 damage
- **Guarding** defender: ×0.5 damage
- **Ailments:** elemental moves (not Strike) have a 20% chance to inflict one on a target that has none. Lasts 3 turns.
  - Burn: −6% max HP per turn. Blight: −8% max HP per turn. Shock: 30% chance to lose the turn.

### AI
Chooses the affordable non-Guard move with the best expected damage, picks a random affordable move 20% of the time,
and Guards when it can't afford anything.

### Rewards (`GameStore.recordBattle`)
- XP = (40 for a win, 15 for a loss) + opponent level × 6, then +25% for a Scholar and +10% at Keeper rank 20.
  Bond +3 for a win, +1 for a loss (doubled for a Tamer). Fatigue +15.
- Wins also give 25 + opponent level × 5 coins (+25% for a Ranger), plus a drop roll: 35% Glow Berry, 15% one of Remedy Herb / Guts Tonic / Calm Tea, 8% Healing Draught, 4% 1 shard.
- **Bosses** always drop 1 + level÷10 shards, a Healing Draught and a Lattice Candy.
- The keeper earns Keeper XP: 20 + opponent level × 2 for a win, 5 for a loss.
- Running away earns nothing and costs nothing.

### Battle types (`BattleSession.Kind`)

| Kind | Setup | Items | Run |
|---|---|---|---|
| Story boss | 1v1 vs. the chapter boss | yes | no |
| Encounter | 1v1 vs. a quest or wild beast | yes | yes |
| Practice | 1v1 vs. an AI rival at your level −1 to +2 | yes | no |
| Raid | You + ally vs. a "Corrupted" apex at party level +3 with 3× HP | yes | no |
| Online | Versus or Co-op Raid over Game Center or Nearby | **no** | no |
| Challenge | 1v1 vs. the AI ghost of a Challenge Card's beast (kind `.practice`) | yes | no |

---

## 11. Arena and multiplayer

`Multiplayer/MultiplayerManager.swift`, `Views/ArenaView.swift`.

**Arena Hall** (`ArenaHallView`, map `AdventureMap.arena`): the Arena tab is an entrance screen (`battle_bg_arena`)
with an **Enter the Arena** button. The hall is a walkable map (quarry tiles, region ID 0, not part of the story):
- The arena building (`building_arena`, 3×3 art centered on a 4×3 footprint at cols 8–11, rows 1–3, set via
  `AdventureMap.buildingArt`) at the top, and a fenced sand ring in the middle.
- **Hosts:** talking to one opens its desk (`ArenaDeskSheet`), where you pick a fighter (and an ally for raids).
  The battle starts when the desk closes.
  - **Practice** (Kade's sprite, in the ring): Practice vs. Rival.
  - **Haven Raid** (Rook's sprite): co-op raid with an AI ally.
  - **Online** (Wren's sprite): Game Center Versus and Co-op Raid. A found match closes the desk and opens the battle.
- **Stations:** a Hot Spring and a Market by the door.
- Walking out of the bottom exit, or tapping Leave, returns to the tab.
- Host IDs are `AdventureMap.ArenaHost` (`arena-practice`, `arena-raid`, `arena-online`). They reuse story sprites
  through `AdventureScene.EntityStyle.art`.
- **Atmosphere** (`AdventureScene.addArenaAmbience()`, `Engine/ArenaHallAmbience.swift`), Arena Hall only:
  - **Crowd:** two spectators per seat tile of the arena building (building tiles above the front wall, skipping any
    that would fall off the art), in mixed colors, swaying out of step. Walking past the building (row ≤ 4,
    cols 5–14) makes fans within 3 columns jump and wave.
    Stepping onto the ring's sand (cols 3–16, rows 6–8) gets the whole crowd cheering. Every 1–13 s a random section
    cheers on its own (visual only).
  - **Sound:** crowd murmur loop the whole time. `cheer` plays when you walk past the stands (at most every 4 s)
    and every time you enter the ring.
  - **Banners** on the arena building's front wall either side of the door (cols 8 and 11 of row 3), swaying.
  - **Torches** with flame particles and a flickering glow on the ring's four fence corners.
  - **Spotlights:** two soft spots sweeping across the ring in opposite directions (4.5 s each way).
  - **Dust** motes drifting over the whole hall.
  - The building has final art. Crowd, banners and torches are still placeholders (SF Symbols and shapes).

**Arena match presentation** (`BattleView` when the session kind is `.practice`, `.raid` or `.online`; never story):
- **Announcer intro** (`ArenaIntroCard`): both sides' beasts slide in, a VS slam, and an announcer line for the
  match type (Practice, Raid, online Versus or online Co-op). `roar` plays. It closes after 3.2 s or on tap, and is
  read aloud by VoiceOver. It only shows for a fresh match (no events yet).
- **Crowd** (`ArenaCrowdStrip`): silhouettes along the top of the battle, plus the crowd murmur loop. Critical or
  super-effective hits (either side) play `cheer`; knockouts play `roar`. Each one makes the crowd ripple-jump
  and camera flashes pop.
- **Victory celebration:** on an Arena win, confetti (`ConfettiBurst`) and `roar` alongside the victory sting.

- **Offline:** Practice vs. Rival, and Co-op Raid with an AI-controlled beast from your Haven.
- **Online (Game Center):** **Versus** (1v1) and **Co-op Raid** (2 players vs. a raid boss). They use separate matchmaking pools.
- **Nearby (Wi-Fi & Bluetooth, MultipeerConnectivity):** Versus and Co-op Raid with a keeper in the same room, no
  internet or Game Center account needed. Both pick the same match type at Wren's desk and connect automatically:
  each device advertises and browses service `bstopia-arena` with `mode`, `build` (version and build number) and
  a random `token`. Only matching mode and build pair up (lockstep needs identical battle math). The lower token
  sends the invite. The session is encrypted (`.required`). The same `hello`/`action`/`forfeit` messages are sent;
  with no Game Center IDs, turn order comes from comparing nonces (`MultiplayerManager.isLocalFirst`). A disconnect
  counts as a win, as online. Needs `NSLocalNetworkUsageDescription` and `NSBonjourServices`
  (`_bstopia-arena._tcp`, `_bstopia-arena._udp`).
- **Challenge Cards** (`Multiplayer/ChallengeCard.swift`): play against keepers who aren't online at the same time.
  "Show My Challenge Card" at Wren's desk packs your boosted fighter (keeper name, species, nickname, level, six
  stats, trait, rarity) as compact JSON in URL-safe base64 after `BEASTOPIA-DUEL:` (about 150 bytes). It's shown as
  a QR code you can share as an image. A friend scans it in the Scan tab and fights an AI ghost named
  "<keeper>'s <beast>". The ghost goes through `MultiplayerManager.sanitized`. Cards are a snapshot of the beast.
- **NFC Challenge Cards** (`Multiplayer/ChallengeCardNFC.swift`): write a card to an NFC sticker (NTAG215 or larger)
  and tap one to fight it. iPhones can't do phone-to-phone NFC, so the tag carries the challenge. **Off for now:**
  NFC Tag Reading needs a paid Developer Program team, and the current personal team can't sign the
  `com.apple.developer.nfc.readersession.formats` entitlement. To turn it on, add that entitlement (`TAG`) and set
  `ChallengeCardNFC.isEntitled = true`. `NFCReaderUsageDescription` is already in the Info.plist.
- **Lockstep netcode:**
  1. Peers exchange `hello(beast, nonce)`.
  2. Both sort by player ID to agree on combatant order, and XOR the nonces into a shared seed.
  3. From then on, only `action(turn, move)` messages are sent. Each device runs the same `BattleEngine` and gets the same result.
  4. Leaving mid-match sends `forfeit`. A disconnect counts as a win in Versus.
- **Validation:** messages over 16 KB are dropped. A remote beast is sanitized (unknown species falls back to a default rookie, stats clamped to 1–999, level 1–99, nickname ≤ 20 characters). Remote moves are only accepted for the current or next turn and indices 0–3.

---

## 12. Economy and items

**Currencies**
- **Coins:** earned from battle wins, chapter rewards, chests, selling beasts and some dialogue choices. Spent on items, Haven upgrades and Hot Springs.
- **Lattice Shards:** rare. Earned from bosses, chests and occasional drops. Spent on the strongest items.

### Items (`Models/Item.swift`)

| Item | ID | Use | Effect | Price |
|---|---|---|---|---|
| Glow Berry | `berry` | Battle | Restore 30% HP | 15 coins |
| Healing Draught | `potion` | Battle | Restore 60% HP | 40 coins |
| Full Elixir | `fullElixir` | Battle | Full HP and cure | 3 shards |
| Remedy Herb | `remedy` | Battle | Cure burn, shock and blight | 20 coins |
| Guts Tonic | `gutsTonic` | Battle | +50 Guts | 30 coins |
| Lattice Candy | `latticeCandy` | Haven | +120 XP | 60 coins |
| Star Candy | `starCandy` | Haven | +600 XP | 2 shards |
| Bond Treat | `bondTreat` | Haven | Bond +12 | 35 coins |
| Calm Tea | `calmTea` | Haven | Fatigue −50 | 25 coins |

Using a battle item spends your turn, and items resolve before attacks.

### Keeper gear (`GearKind` in `Models/Keeper.swift`)
Sold in the Haven Market's Keeper Gear section. Buying a piece equips it. Three slots, one piece each.
Swap gear from the Keeper profile. Coin prices get the rank 10 discount.

| Gear | ID | Slot | Bonus | Price | Rank |
|---|---|---|---|---|---|
| Lattice Charm | `latticeCharm` | Charm | +2 Wits | 300 coins | 1 |
| Sage's Pendant | `sagesPendant` | Charm | +4 Wits | 900 coins | 8 |
| Glyph Sigil | `glyphSigil` | Charm | +3 Wits, +3 Might | 6 shards | 15 |
| Leather Gloves | `leatherGloves` | Gloves | +2 Might | 300 coins | 1 |
| Ironbark Gauntlets | `ironbarkGauntlets` | Gloves | +4 Might | 900 coins | 8 |
| Emberforged Grips | `emberforgedGrips` | Gloves | +3 Might, +3 Agility | 6 shards | 15 |
| Traveler's Cloak | `travelersCloak` | Cloak | +2 Agility | 300 coins | 1 |
| Galeweave Cloak | `galeweaveCloak` | Cloak | +4 Agility | 900 coins | 8 |
| Nullward Mantle | `nullwardMantle` | Cloak | +3 Agility, +3 Wits | 6 shards | 15 |

---

## 13. Beast roster (105)

32 rookies, 41 adults, 24 apex forms, 8 Mythics. The original 29 are in `Species.swift`; the 76 expansion species
are in `SpeciesExpansion.swift`. Each element has the original line plus three expansion families:
a **branching** line, a **three-stage** line, and a **two-stage** line with a stronger final adult.

Apex evolutions always need **Bond 50**. "Top stat" means that stat must be the beast's highest.

### Ember

| Beast | ID | Stage | Hidden | Base total | Signature move | Evolves into |
|---|---|---|---|---|---|---|
| Cindrop | `cindrop` | Rookie | Volt | 287 | Ember Pounce (physical, PWR 55, 20 Guts) | Pyrowl (Lv 10, top stat INT) / Magmaw (Lv 10) |
| Pyrowl | `pyrowl` | Adult | Gale | 570 | Scorch Wing (special, PWR 75, 30 Guts) | Infernox (Lv 25, Bond 50) |
| Infernox | `infernox` | Apex | Umbra | 1010 | Cataclysm (special, PWR 100, 45 Guts) | — |
| Magmaw | `magmaw` | Adult | Terra | 545 | Lava Jaw (physical, PWR 80, 32 Guts) | Infernox (Lv 25, Bond 50) |
| Kindlekit | `kindlekit` | Rookie | Terra | 288 | Spark Nip (physical, PWR 52, 18 Guts) | Blazefang (Lv 10, top stat POW) / Ashveil (Lv 10) |
| Blazefang | `blazefang` | Adult | Terra | 585 | Inferno Bite (physical, PWR 80, 32 Guts) | Pyrelord (Lv 25, Bond 50) |
| Pyrelord | `pyrelord` | Apex | Umbra | 1020 | Sovereign Blaze (special, PWR 102, 46 Guts) | — |
| Ashveil | `ashveil` | Adult | Umbra | 585 | Cinder Shroud (special, PWR 76, 30 Guts) | Pyrelord (Lv 25, Bond 50) |
| Charbug | `charbug` | Rookie | Verdant | 288 | Hot Mandible (physical, PWR 52, 18 Guts) | Scorchitin (Lv 10) |
| Scorchitin | `scorchitin` | Adult | Verdant | 585 | Furnace Shell (physical, PWR 76, 30 Guts) | Volcarapace (Lv 25, Bond 50) |
| Volcarapace | `volcarapace` | Apex | Terra | 1020 | Eruption Ram (physical, PWR 104, 48 Guts) | — |
| Fizzlet | `fizzlet` | Rookie | Volt | 290 | Pop Spark (special, PWR 52, 18 Guts) | Pyrotechnix (Lv 12) |
| Pyrotechnix | `pyrotechnix` | Adult | Volt | 680 | Grand Finale (special, PWR 88, 36 Guts) | — |

### Tide

| Beast | ID | Stage | Hidden | Base total | Signature move | Evolves into |
|---|---|---|---|---|---|---|
| Ripplet | `ripplet` | Rookie | Lumen | 290 | Bubble Volley (special, PWR 50, 18 Guts) | Tidecrest (Lv 10) |
| Tidecrest | `tidecrest` | Adult | Lumen | 565 | Crashing Wave (special, PWR 75, 30 Guts) | Leviathorn (Lv 25, Bond 50) |
| Leviathorn | `leviathorn` | Apex | Umbra | 1000 | Abyssal Surge (special, PWR 100, 45 Guts) | — |
| Puddlepup | `puddlepup` | Rookie | Verdant | 288 | Splash Tackle (physical, PWR 50, 18 Guts) | Brinehound (Lv 10, top stat DEF) / Mistmane (Lv 10) |
| Brinehound | `brinehound` | Adult | Terra | 585 | Saltwater Maul (physical, PWR 78, 30 Guts) | Abyssalisk (Lv 25, Bond 50) |
| Abyssalisk | `abyssalisk` | Apex | Umbra | 1020 | Pressure Crush (special, PWR 102, 46 Guts) | — |
| Mistmane | `mistmane` | Adult | Lumen | 585 | Fogbank (special, PWR 76, 30 Guts) | Abyssalisk (Lv 25, Bond 50) |
| Shellbe | `shellbe` | Rookie | Terra | 288 | Clam Clamp (physical, PWR 50, 18 Guts) | Coralisk (Lv 10) |
| Coralisk | `coralisk` | Adult | Terra | 585 | Reef Spikes (physical, PWR 76, 30 Guts) | Reefmonarch (Lv 25, Bond 50) |
| Reefmonarch | `reefmonarch` | Apex | Lumen | 1020 | Coral Crown (special, PWR 102, 46 Guts) | — |
| Frostfin | `frostfin` | Rookie | Lumen | 288 | Chill Fin (special, PWR 52, 18 Guts) | Glaciaray (Lv 12) |
| Glaciaray | `glaciaray` | Adult | Lumen | 680 | Glacier Glide (special, PWR 88, 36 Guts) | — |

### Verdant

| Beast | ID | Stage | Hidden | Base total | Signature move | Evolves into |
|---|---|---|---|---|---|---|
| Sproutle | `sproutle` | Rookie | Terra | 280 | Seed Barrage (physical, PWR 50, 18 Guts) | Thornback (Lv 10) |
| Thornback | `thornback` | Adult | Terra | 545 | Thorn Volley (physical, PWR 75, 30 Guts) | Elderoot (Lv 25, Bond 50) |
| Elderoot | `elderoot` | Apex | Lumen | 970 | World Tree Crash (physical, PWR 100, 45 Guts) | — |
| Budling | `budling` | Rookie | Lumen | 288 | Petal Puff (special, PWR 50, 18 Guts) | Bloomtail (Lv 10, top stat INT) / Briarmaw (Lv 10) |
| Bloomtail | `bloomtail` | Adult | Lumen | 585 | Blossom Storm (special, PWR 78, 30 Guts) | Verdantitan (Lv 25, Bond 50) |
| Verdantitan | `verdantitan` | Apex | Terra | 1020 | Overgrowth (physical, PWR 102, 46 Guts) | — |
| Briarmaw | `briarmaw` | Adult | Umbra | 585 | Bramble Bite (physical, PWR 80, 32 Guts) | Verdantitan (Lv 25, Bond 50) |
| Mossnail | `mossnail` | Rookie | Tide | 288 | Moss Slime (special, PWR 50, 18 Guts) | Lichenshell (Lv 10) |
| Lichenshell | `lichenshell` | Adult | Tide | 585 | Spore Cloud (special, PWR 76, 30 Guts) | Grovekeep (Lv 25, Bond 50) |
| Grovekeep | `grovekeep` | Apex | Lumen | 1020 | Ancient Canopy (special, PWR 100, 46 Guts) | — |
| Spudsy | `spudsy` | Rookie | Terra | 288 | Root Slam (physical, PWR 52, 18 Guts) | Rootrumble (Lv 12) |
| Rootrumble | `rootrumble` | Adult | Terra | 680 | Tuber Quake (physical, PWR 88, 36 Guts) | — |

### Gale

| Beast | ID | Stage | Hidden | Base total | Signature move | Evolves into |
|---|---|---|---|---|---|---|
| Fluffwing | `fluffwing` | Rookie | Lumen | 290 | Gust Dive (physical, PWR 52, 18 Guts) | Zephyrix (Lv 10) |
| Zephyrix | `zephyrix` | Adult | Volt | 585 | Slipstream (physical, PWR 75, 30 Guts) | Tempestrix (Lv 25, Bond 50) |
| Tempestrix | `tempestrix` | Apex | Volt | 1040 | Eye of the Storm (special, PWR 100, 45 Guts) | — |
| Puffwisp | `puffwisp` | Rookie | Lumen | 288 | Cloud Puff (special, PWR 50, 18 Guts) | Stormhorn (Lv 10, top stat POW) / Nimbusoar (Lv 10) |
| Stormhorn | `stormhorn` | Adult | Volt | 585 | Squall Horn (physical, PWR 80, 32 Guts) | Skyshroud (Lv 25, Bond 50) |
| Skyshroud | `skyshroud` | Apex | Volt | 1020 | Stratosphere (special, PWR 102, 46 Guts) | — |
| Nimbusoar | `nimbusoar` | Adult | Lumen | 585 | Cumulus Cannon (special, PWR 76, 30 Guts) | Skyshroud (Lv 25, Bond 50) |
| Featherling | `featherling` | Rookie | Umbra | 288 | Quill Flick (physical, PWR 52, 18 Guts) | Galeharrier (Lv 10) |
| Galeharrier | `galeharrier` | Adult | Umbra | 585 | Talon Dive (physical, PWR 78, 30 Guts) | Aerozenith (Lv 25, Bond 50) |
| Aerozenith | `aerozenith` | Apex | Lumen | 1020 | Zenith Strike (physical, PWR 104, 48 Guts) | — |
| Whirlbit | `whirlbit` | Rookie | Volt | 288 | Spin Gust (special, PWR 50, 18 Guts) | Cyclonyx (Lv 12) |
| Cyclonyx | `cyclonyx` | Adult | Volt | 680 | Vortex Lash (special, PWR 88, 36 Guts) | — |

### Terra

| Beast | ID | Stage | Hidden | Base total | Signature move | Evolves into |
|---|---|---|---|---|---|---|
| Pebblit | `pebblit` | Rookie | Ember | 279 | Rock Roll (physical, PWR 55, 20 Guts) | Bouldrake (Lv 10) |
| Bouldrake | `bouldrake` | Adult | Ember | 560 | Landslide (physical, PWR 80, 32 Guts) | Gravolith (Lv 25, Bond 50) |
| Gravolith | `gravolith` | Apex | Umbra | 990 | Tectonic Fall (physical, PWR 105, 48 Guts) | — |
| Clodlet | `clodlet` | Rookie | Verdant | 288 | Mud Toss (physical, PWR 50, 18 Guts) | Quarrox (Lv 10, top stat DEF) / Dunebadger (Lv 10) |
| Quarrox | `quarrox` | Adult | Ember | 585 | Granite Wall (physical, PWR 76, 30 Guts) | Terragnaw (Lv 25, Bond 50) |
| Terragnaw | `terragnaw` | Apex | Umbra | 1020 | Continental Bite (physical, PWR 104, 48 Guts) | — |
| Dunebadger | `dunebadger` | Adult | Gale | 585 | Sand Burrow (physical, PWR 78, 30 Guts) | Terragnaw (Lv 25, Bond 50) |
| Geodite | `geodite` | Rookie | Lumen | 288 | Gem Glint (special, PWR 50, 18 Guts) | Crystalback (Lv 10) |
| Crystalback | `crystalback` | Adult | Lumen | 585 | Shard Spray (special, PWR 76, 30 Guts) | Prismolith (Lv 25, Bond 50) |
| Prismolith | `prismolith` | Apex | Lumen | 1020 | Refraction Quake (special, PWR 102, 46 Guts) | — |
| Burrowmole | `burrowmole` | Rookie | Umbra | 288 | Dig Strike (physical, PWR 52, 18 Guts) | Tunnelgrinder (Lv 12) |
| Tunnelgrinder | `tunnelgrinder` | Adult | Umbra | 680 | Drill Breaker (physical, PWR 88, 36 Guts) | — |

### Volt

| Beast | ID | Stage | Hidden | Base total | Signature move | Evolves into |
|---|---|---|---|---|---|---|
| Sparkit | `sparkit` | Rookie | Gale | 292 | Static Hop (special, PWR 52, 18 Guts) | Joltusk (Lv 10) |
| Joltusk | `joltusk` | Adult | Terra | 590 | Tusk Thunder (physical, PWR 78, 30 Guts) | Thundervex (Lv 25, Bond 50) |
| Thundervex | `thundervex` | Apex | Gale | 1050 | Heaven's Arc (special, PWR 100, 45 Guts) | — |
| Zaplet | `zaplet` | Rookie | Tide | 288 | Zap Plug (special, PWR 50, 18 Guts) | Ampereon (Lv 10, top stat SPD) / Voltwatt (Lv 10) |
| Ampereon | `ampereon` | Adult | Gale | 585 | Overclock (special, PWR 78, 30 Guts) | Dynamotor (Lv 25, Bond 50) |
| Dynamotor | `dynamotor` | Apex | Terra | 1020 | Megawatt Burst (special, PWR 102, 46 Guts) | — |
| Voltwatt | `voltwatt` | Adult | Terra | 585 | Capacitor Slam (physical, PWR 78, 30 Guts) | Dynamotor (Lv 25, Bond 50) |
| Buzzbee | `buzzbee` | Rookie | Gale | 288 | Buzz Sting (physical, PWR 52, 18 Guts) | Stingcoil (Lv 10) |
| Stingcoil | `stingcoil` | Adult | Gale | 585 | Coil Lance (physical, PWR 78, 30 Guts) | Tesladon (Lv 25, Bond 50) |
| Tesladon | `tesladon` | Apex | Lumen | 1020 | Tesla Storm (special, PWR 102, 46 Guts) | — |
| Staticat | `staticat` | Rookie | Umbra | 288 | Fuzz Shock (special, PWR 52, 18 Guts) | Fluxlynx (Lv 12) |
| Fluxlynx | `fluxlynx` | Adult | Umbra | 680 | Flux Pounce (physical, PWR 88, 36 Guts) | — |

### Lumen

| Beast | ID | Stage | Hidden | Base total | Signature move | Evolves into |
|---|---|---|---|---|---|---|
| Glimmet | `glimmet` | Rookie | Tide | 294 | Twinkle Beam (special, PWR 52, 18 Guts) | Radiantail (Lv 10) |
| Radiantail | `radiantail` | Adult | Gale | 590 | Dawnflare (special, PWR 78, 30 Guts) | Solaryx (Lv 25, Bond 50) |
| Solaryx | `solaryx` | Apex | Ember | 1050 | Solar Crown (special, PWR 100, 45 Guts) | — |
| Lumoth | `lumoth` | Rookie | Gale | 288 | Glow Dust (special, PWR 50, 18 Guts) | Halomoth (Lv 10, top stat INT) / Lanternwing (Lv 10) |
| Halomoth | `halomoth` | Adult | Gale | 585 | Halo Pulse (special, PWR 78, 30 Guts) | Celestimoth (Lv 25, Bond 50) |
| Celestimoth | `celestimoth` | Apex | Umbra | 1020 | Starfall Wings (special, PWR 102, 46 Guts) | — |
| Lanternwing | `lanternwing` | Adult | Ember | 585 | Lantern Flash (special, PWR 76, 30 Guts) | Celestimoth (Lv 25, Bond 50) |
| Prismpup | `prismpup` | Rookie | Ember | 288 | Shine Tackle (physical, PWR 50, 18 Guts) | Starmane (Lv 10) |
| Starmane | `starmane` | Adult | Ember | 585 | Meteor Mane (physical, PWR 78, 30 Guts) | Novaleon (Lv 25, Bond 50) |
| Novaleon | `novaleon` | Apex | Ember | 1020 | Supernova Roar (special, PWR 104, 48 Guts) | — |
| Dewglow | `dewglow` | Rookie | Tide | 288 | Morning Dew (special, PWR 50, 18 Guts) | Auroracub (Lv 12) |
| Auroracub | `auroracub` | Adult | Tide | 680 | First Light (special, PWR 88, 36 Guts) | — |

### Umbra

| Beast | ID | Stage | Hidden | Base total | Signature move | Evolves into |
|---|---|---|---|---|---|---|
| Shadeling | `shadeling` | Rookie | Verdant | 294 | Night Swipe (physical, PWR 52, 18 Guts) | Nocturne (Lv 10) |
| Nocturne | `nocturne` | Adult | Volt | 600 | Eclipse Claw (physical, PWR 78, 30 Guts) | Eclipsar (Lv 25, Bond 50) |
| Eclipsar | `eclipsar` | Apex | Lumen | 1060 | Total Eclipse (special, PWR 100, 45 Guts) | — |
| Gloomkit | `gloomkit` | Rookie | Ember | 288 | Gloom Scratch (physical, PWR 52, 18 Guts) | Duskstalker (Lv 10, top stat SPD) / Hexhowl (Lv 10) |
| Duskstalker | `duskstalker` | Adult | Gale | 585 | Twilight Ambush (physical, PWR 80, 32 Guts) | Voidfang (Lv 25, Bond 50) |
| Voidfang | `voidfang` | Apex | Ember | 1020 | Abyss Rend (physical, PWR 104, 48 Guts) | — |
| Hexhowl | `hexhowl` | Adult | Lumen | 585 | Hex Howl (special, PWR 76, 30 Guts) | Voidfang (Lv 25, Bond 50) |
| Murkling | `murkling` | Rookie | Lumen | 288 | Spook (special, PWR 50, 18 Guts) | Wraithveil (Lv 10) |
| Wraithveil | `wraithveil` | Adult | Lumen | 585 | Phantom Veil (special, PWR 76, 30 Guts) | Phantasmire (Lv 25, Bond 50) |
| Phantasmire | `phantasmire` | Apex | Tide | 1020 | Nightmare Tide (special, PWR 102, 46 Guts) | — |
| Batling | `batling` | Rookie | Gale | 288 | Echo Bite (physical, PWR 52, 18 Guts) | Nightwing (Lv 12) |
| Nightwing | `nightwing` | Adult | Gale | 680 | Moonless Dive (physical, PWR 88, 36 Guts) | — |

### Mythic Beasts
You get these from ultra-rare scans (1.6%) or from Fusion recipes (both parents Lv 15+, parent elements match the pair below).

| Beast | ID | Elements (fusion recipe) | Base total | Signature move |
|---|---|---|---|---|
| Aurorion | `aurorion` | Lumen + Gale | 890 | Aurora Veil (special, PWR 95, 40 Guts) |
| Chronodrake | `chronodrake` | Terra + Umbra | 880 | Time Fracture (special, PWR 95, 40 Guts) |
| Maelstryx | `maelstryx` | Tide + Volt | 900 | Maelstrom (special, PWR 95, 40 Guts) |
| Oblivyrn | `oblivyrn` | Umbra + Umbra | 1050 | Null Devour (special, PWR 110, 50 Guts) |
| Vaporgeist | `vaporgeist` | Ember + Tide | 920 | Scalding Geyser (special, PWR 95, 40 Guts) |
| Sylvanwyrm | `sylvanwyrm` | Verdant + Gale | 920 | Verdant Gale (special, PWR 95, 40 Guts) |
| Halostorm | `halostorm` | Volt + Lumen | 920 | Radiant Thunder (special, PWR 95, 40 Guts) |
| Magmarch | `magmarch` | Ember + Terra | 920 | Magma Monolith (physical, PWR 95, 40 Guts) |

---

## 14. Art and visual direction

**Current state:** pixel art for all 105 beast portraits (32 px), every map tile in all 8 themes, the player, NPCs,
bosses, stations and chests (16 px), and the item, element, stat, status, ability and currency icons (32 px, via
`GameIcon`), idle animation frames for every beast, the summon effects, dialogue portraits, battle backgrounds,
the scan frame and music. Still not hooked up: the UI kit images (`ui_panel`, `ui_button`, bars), `launch_screen`,
`portrait_keeper` and `portrait_vey` (see `ASSET_LIST.md` §7). Anything without art falls back to its procedural
placeholder or SF Symbol.

**Beast animation** (`Views/BeastAnimation.swift`): `beast_<id>_1`…`_4` are idle frames played at 6 fps, and
`beast_<id>_blink` shows for one tick about every 4 s (`AnimatedBeastArt`). `BeastPortrait(…, isAnimated: true)` plays
them, falling back to the still `beast_<id>`. Reduce Motion holds frame 1. **Only the summon reveal animates**
(new beasts from scans and fusion). Everywhere else shows the still portrait, by the user's choice (2026-11-13).

**Summon cutscene** (`SummonCutscene`, used by `SummonRevealView` for scans and fusions, about 2 s, longer for
Epic+ and Prismatic): `summon_glyph_1` pops in → `_2` and `_3` crack it with a shake and light haptics → white flash,
eight `summon_shard_1`…`_3` fly outward, heavy haptic → the animated beast appears over a slowly turning
`summon_burst_<element>` (`summon_burst_mythic` for Mythic rarity, `summon_burst_prismatic` for Prismatic, else the
generic `summon_burst`). The sheet can't be swiped away until the beast is revealed. Reduce Motion skips straight
to the reveal.

**Other hooks:** `NPCAvatar` shows `portrait_<last name>` (`NPC.portraitArt`, e.g. Elder Brasa → `portrait_brasa`).
`BattleBackdrop(art:)` shows `battle_bg_<theme>` for story battles and `battle_bg_arena` for practice, raids and
online, falling back to the painted gradient. `ScanViewfinder` stretches `scan_frame` over the scan window.

**UI kit** (`Views/GameTheme.swift`):
- `GameTheme` colors: `ink`, `gold`, `panelTop`, `panelBottom`.
- `GameButtonStyle`: a chunky button that presses down onto a darker lip.
- `.gamePanel(tint:cornerRadius:)`: a dark framed panel. Use it instead of `.regularMaterial`.
- `BattleBackdrop`, `BattlePlatform`, `IdleBob`: pieces of the battle stage. `IdleBob` only moves the beast up
  3 pt, rounded to whole points. It must never scale: the portrait is flattened by its shadow and color filters, so
  scaling resamples the pixel art and makes it look stretched and blurry.
- `BeastArtImage`: draws beast art in a box. Pixel art (≤ 128 px) is drawn at a whole number of screen pixels per art
  pixel (32 px art in a 104 pt box at 3× draws at 96 pt), so every pixel is the same size. `BeastPortrait` and
  `AnimatedBeastArt` use it.
- `PixelTextBox(text:title:showsContinue:tint:)`: a retro RPG text box: pixel font, square double border, hard drop
  shadow, typewriter text (instant with Reduce Motion) and a blinking ▼ when tapping continues. `PixelTitleCard`: a
  "~ TITLE ~" banner. `GameFont.pixel(size:relativeTo:)` gives the pixel font for SwiftUI, scaling with Dynamic Type.
- `.pixelToast($message)`: shows a `PixelTextBox` along the bottom of a screen for 2.5 s, then clears the message.
  Used for menu feedback on the Haven beast page, care stations, Market and Bag.
- The whole app uses the rounded system font (`BeastopiaApp.swift`).
- Applied so far: the battle screen. Still stock iOS: Haven, Beastdex, Story, Arena, Scan.

The full checklist of art, audio and store assets still needed is in **`ASSET_LIST.md`**.

**Dropping in final art:** add an image set to `Assets.xcassets` with the matching name. It replaces the
placeholder automatically, with no code changes. Images ≤ 128 px are treated as pixel art and scaled without smoothing.

| Asset name | Replaces |
|---|---|
| `beast_<speciesID>` (e.g. `beast_kindlekit`) | Beast portrait, everywhere |
| `tile_<theme>_<terrain>` (e.g. `tile_meadow_grass`) or `tile_<terrain>` | Map tile |
| `tile_<theme>_buildingWall`, `tile_<theme>_buildingDoor` (or generic) | Front wall of a building (see below) |
| `tile_<theme>_fenceV`, `tile_<theme>_fenceNE`/`NW`/`SE`/`SW` (or generic) | Vertical fence and fence corners. Picked from neighboring fence tiles; corner names list the two sides they join (`fenceNE` joins north and east). `tile_<theme>_fence` is the horizontal run |
| `AdventureMap.buildingArt` (e.g. `building_arena`) | All of a map's building tiles drawn as one image, centered, keeping its shape (Arena Hall only) |
| `station_<facility>` (e.g. `station_hotSpring`) | Care station on the map |
| `player_swim`, `player_fly` | Player on water (swimming with a Tide beast, or flying) |
| `marker_quest` | Bobbing marker over the active quest NPC or boss |
| `marker_exit` | Exit arrow (drawn pointing right; rotated for each edge) |
| `marker_trail` | Guide-trail breadcrumb (drawn at 16 pt) |
| `fx_sparkle_1`…`fx_sparkle_3` (or `fx_sparkle`) | Sparkle burst when a chest opens or the player blinks (Blink tints it purple) |
| `ui_signpost` | Exit signpost board, stretched to fit the region name (4 px border kept) |
| `item_<kind>`, `element_<element>`, `stat_<stat>`, `status_<status>` | Icons, via `GameIcon` / `GameLabel` |
| `ability_swim`, `ability_fly`, `ability_blink`, `currency_coin`, `currency_shard` | Icons, via `GameIcon` / `GameLabel` |
| `player` | Player sprite on the map |
| `npc_<objectiveID>` (e.g. `npc_ch1-pip`) | NPC or boss sprite on the map |
| `chest`, `chest_open` | Treasure chests |
| `tile_interior_<terrain>` | Inside buildings (floor, rug, plant, counter, wall). No generic fallback |
| `feature_geyser`, `feature_arc`, `feature_gust`, `feature_boulder`, `feature_bramble`, `feature_bloom`, `feature_bloom_lit` | Element mechanics (placeholders: SF Symbols and shapes) |
| `glyph_stone` | Element Glyph (placeholder: a turning hexagon in the beast's element color) |

Themes: `meadow`, `volcano`, `coast`, `forest`, `peaks`, `quarry`, `marsh`, `spire`.
Terrains: `grass`, `tallGrass`, `path`, `flowers`, `tree`, `water`, `fence`, `building`.

**Buildings** are built from three pieces. In each column of `H` tiles the lowest tile is the front wall and the
tiles above it are roof (`building`). The middle tile of each wall run gets the door. Wall and door pieces come
from the same set as the roof (themed or generic), so a building never mixes styles. Themes with a roof but no
wall or door pieces (`forest`, `quarry`, `spire`) use the roof tile throughout.

**Art direction:** pixel art. Beast portraits are 32×32 and map tiles are 16×16. `AdventureScene.tileSize` is 48 pt so
16 px tiles scale by whole pixels. The player, NPCs and stations are drawn exactly one tile in size.
Map labels (NPC, station and signpost names) use the bundled pixel font `Beastopia Pixel` (`Fonts/BeastopiaPixel.ttf`,
registered at launch by `GameFont.register()`), with a 1 pt dark shadow. The adventure screen's toasts, tutorials and
region title cards use it too, as do menu feedback messages (`.pixelToast`) and the Scan screen's "Fit the code
inside the frame" prompt. Other text still uses the system font.
Colored variants (hue shift) and Prismatic effects are applied in code, so you only need **one image per species**.

---

## 15. Audio

`Engine/SoundFX.swift`: procedurally synthesized sound effects (sine, square, triangle, noise and low-passed
"murmur" noise). There are no audio files.

| Group | Cues |
|---|---|
| UI and Haven | `tap`, `train`, `feed`, `rest`, `levelUp`, `evolve`, `purchase`, `denied`, `primary`, `release`, `summon`, `fuse` |
| Battle | `hit`, `critical`, `miss`, `guardUp`, `heal`, `knockout`, `victory`, `defeat` |
| Arena crowd | `cheer` (1.4 s), `roar` (2.6 s); no haptics |

**Crowd ambience:** `.crowdAmbience()` loops a 6 s crowd murmur (50% volume) under the music while the view is
on screen. Holds nest (`startCrowd` / `stopCrowd`), so the Arena Hall and an Arena battle above it share one loop.
The murmur, `cheer` and `roar` take seconds to synthesize, so they render on a background task when the crowd first
starts; a crowd cue played before that finishes is skipped.

Stings play over the music when their file exists, otherwise the synthesized cue: `sting_summon` (summon
cutscene), `sting_victory` / `sting_defeat` (battle result), `sting_evolve` (Evolve button).

### Music (`Engine/MusicPlayer.swift`, files in `Audio/`)
Looping `.m4a` tracks with a 0.8 s crossfade, at 55% volume. They follow the Music setting and the master Sound switch, scaled by the Music volume (§2, Settings). Stings follow Music too; when Music is off, the synthesized cue plays instead.
A screen asks for a track with `.music("…")`. Requests stack: the newest visible screen wins, and closing it (a
battle sheet, a tab switch) brings back the one below. Stings duck the music to 25% while they play.

| Where | Track |
|---|---|
| Loading sequence, keeper creation, Scan, Story, Arena and Beastdex tabs, Arena Hall | `music_title` |
| Haven tab | `music_haven` |
| Adventure map (by theme) | meadow `music_haven`, volcano `music_caldera`, coast `music_coast`, forest `music_wilds`, peaks `music_skyreach`, quarry `music_quarry`, marsh `music_voltmarsh`, spire `music_spire` |
| Battles | `music_battle`; story bosses and raids `music_boss`; the Chapter 8 boss `music_finale` |

---

## 16. Code map

| Area | File | Responsibility |
|---|---|---|
| App | `BeastopiaApp.swift`, `ContentView.swift` | Entry point, environment objects, tabs |
| Save | `Models/GameStore.swift` | All player state, persistence, rewards, quest progress |
| Keeper | `Models/Keeper.swift`, `Views/KeeperView.swift` | Player character: classes, hero stats, rank, gear; creation, profile, gear shop |
| Beasts | `Models/Beast.swift` | An owned beast, HP formula, evolution check |
| Species | `Models/Species.swift`, `Models/SpeciesExpansion.swift` | Species database, moves, evolution paths |
| Elements | `Models/Element.swift` | Elements, matchups, stats, rarity, traits |
| Items | `Models/Item.swift` | Items, prices, loot, field abilities |
| Story | `Models/StoryCampaign.swift`, `Models/WorldMap.swift` | Chapters, NPCs, dialogue, objectives, regions |
| Maps | `Models/AdventureMap.swift` | Terrain, layouts, stations, treasures, doors, interiors, pathfinding |
| Element world | `Models/FieldFeatures.swift`, `Models/RegionElements.swift` | Buildings, element mechanics and their timing, Element Glyphs; region briefings |
| Quest help | `Models/QuestGuide.swift` | Clues and battle prep advice |
| Lore | `Models/Lore.swift`, `Views/LoreArchiveView.swift` | Lattice Archive pages, Fusion Rumors, YouTube episode codes |
| Scanning | `Engine/BeastGenerator.swift` | SHA-256 → beast; seeded RNG |
| Raising | `Engine/RanchEngine.swift` | Training, upgrades, absorb, sell, evolve, fusion |
| Battle | `Engine/BattleEngine.swift`, `Engine/BattleSession.swift` | Deterministic simulation; UI session and battle factories |
| World | `Engine/AdventureScene.swift` | SpriteKit map, movement, rendering, art hooks |
| Settings | `Views/SettingsView.swift` | `GameSettings` keys, Settings sheet, `.settingsButton()` gear |
| Audio | `Engine/SoundFX.swift`, `Engine/MusicPlayer.swift` | Synthesized sound effects and crowd ambience; music and stings |
| Arena dressing | `Engine/ArenaHallAmbience.swift`, `Views/ArenaBattleEffects.swift` | Arena Hall crowd, banners, torches, spotlights, dust; Arena battle intro card, crowd strip, confetti |
| Animation | `Views/BeastAnimation.swift` | Beast idle frames, summon cutscene |
| Online | `Multiplayer/MultiplayerManager.swift` | Game Center and Nearby (MultipeerConnectivity) matchmaking, lockstep messages |
| Challenge Cards | `Multiplayer/ChallengeCard.swift`, `Multiplayer/ChallengeCardNFC.swift` | Ghost-battle cards as QR codes and NFC tags |
| Mythic reveal | `Views/MythicSummon.swift` | Mythic cutscene and epithets |
| UI kit | `Views/GameTheme.swift`, `Views/Components.swift` | Theme, buttons, panels, portraits, badges, pickers |
| Screens | `Views/*.swift` | One file per screen (see §2) |

---

## 17. Save data and stable IDs

Saved as JSON at `Documents/beastopia-save.json` after every change. It holds: beasts, discovered species,
completed chapters and objectives, story flags, adventure positions per region, coins, shards, inventory,
opened chests (which also holds claimed Element Glyphs and solved element puzzles, so no new field was needed), the keeper (name, look, class, rank, XP, owned and equipped gear), primary beast and claimed code fingerprints. Fields added after launch must be
**optional** so older saves still load (see `SaveFile`).

- **Version:** `SaveFile.version` (currently 1; missing means 1). Bump `SaveFile.currentVersion` only for changes
  older builds can't read.
- **Unreadable saves are never overwritten.** If the file won't decode, or its version is newer than the build,
  `load()` copies it to `beastopia-save.unreadable-<unix time>.json` (`SaveStorage.setAside`) and starts fresh.
  If that copy fails, saving is turned off for the session. Errors go to `Logger` (subsystem `Beastopia`,
  category `Save`). The player isn't told yet.

Settings in `UserDefaults` (`@AppStorage`), not the save file: `adventure.controlMode`, `adventure.guideCollapsed`,
`adventure.tutorialsSeen` (comma-separated tutorial IDs already read), `haven.fusionTipSeen`, `soundEnabled` (the
master Sound switch; key kept from before Settings), `settings.musicOn`, `settings.musicVolume`, `settings.effectsOn`,
`settings.effectsVolume`, `settings.crowdOn`, `settings.crowdVolume`, `settings.haptics`,
`settings.reduceBattleEffects`. Switches default to on (Reduce Battle Effects to off) and volumes to 1.

**Never rename these.** They're stored in saves.

| What | Where |
|---|---|
| Species IDs | `Species.swift`, `SpeciesExpansion.swift` |
| Item raw values | `ItemKind` |
| Objective IDs (`ch3-kade`, …) | `WorldMap.swift` |
| Treasure IDs (`t5-ledge`, …) | `AdventureMap.swift` |
| Element Glyph IDs (`g1-haven`…`g8-spire`) and puzzle IDs (`p1-brambles`, `p4-brambles`) | `AdventureMap.swift`; saved in `openedChests` |
| Challenge Card prefix `BEASTOPIA-DUEL:` and field names | `ChallengeCard` (cards already printed or shared must keep decoding) |
| Story flag strings | `WorldMap.swift` dialogue choices |
| Lore page IDs, episode codes (once aired) | `Models/Lore.swift` |
| Keeper class, color, figure and gear raw values | `KeeperClass`, `KeeperColor`, `KeeperStyle`, `GearKind` |

**Determinism rules** (multiplayer and scanning depend on these):
- Battles use only `SeededRandom`, never `Double.random` or `Int.random` inside `BattleEngine`.
- Changing the order or size of `SpeciesDatabase.rookiePool` or `mythicPool`, or the byte layout in `BeastGenerator`, changes what codes summon.
- Online players must run the same app version. Battle math changes make devices desync.

---

## 18. How-to: adding content

**A species**
1. Add a `Species(...)` entry to `SpeciesExpansion.swift` with a unique lowercase `id`.
2. Keep base totals near the stage norms in §7, and use a real SF Symbol name.
3. Point the previous stage's `evolutions` at the new species.
4. Rookies automatically join the scan pool for their element. Mythics join the mythic pool, so give them an unused element pair for fusion.
5. Update §13. You can regenerate the tables with the snippet approach used to build this doc.

**An item:** add a case to `ItemKind` and fill in `name`, `symbol`, `color`, `summary`, `price`, and either `battleEffects` or `applyInField`.

**A quest step:** add an `Objective` in `WorldMap.swift` using `talk` or `defeat`, place its NPC tile in that region's
`AdventureMap.placements`, and add a clue in `QuestGuide.swift`.

**A region:** add a `Chapter`, a `Region` and an `AdventureMap` (text layout, start tile, placements, wild species,
exits on both sides, stations, treasures), then add it to `AdventureMap.all`.

---

## 19. Known gaps

- **The 76 expansion species only come from scanning, raids and fusion.** They aren't in any region's wild list or quest steps yet.
- Several story flags are recorded but never read: `asked.maren`, `caldera.*`, `sky.direct`, `rook.doubted`, `maren.blamed`.
- The Beastdex is a plain list. At 105 species it needs a grid and filters.
- Fusion between different lines always makes the *original* rookie of the stronger parent's element, never an expansion rookie.
- Most screens still use stock iOS styling (see §14).
- **Difficulty spikes** (simulated on 2026-11-11 with 300 players doing only the required battles, no training):
  nobody gets permanently stuck, because losses still give XP. But the first fight (Stray Pebblit) is won first
  try only 47% of the time. Feral Magmaw (ch 2) is 19%, Syndicate Bouldrake (ch 6) is 12%, and the ch 8 Nocturne
  and Oblivyrn are 6–8%. By the end, players are about 15 levels below story foes unless they grind.
- Placeholder art only. No music.
- **Keeper class isn't reflected in dialogue yet**, and there's no keeper art beyond the SF Symbol figure.
- **Online Versus doesn't sanity-check peer stats** beyond the 1–999 clamp (`MultiplayerManager.sanitized`), so a
  modified client could send an over-boosted beast. A per-species/level ceiling wouldn't help: the peer reports its
  own level, and at level ~10+ training alone can legitimately take a stat to 999 (fusion and absorbing can at lower
  levels). Real protection needs a design change, such as level-normalized Versus stats.
- Keeper gear only comes from the Market, not from bosses or chests.
- **Element mechanics and buildings use placeholder art** (SF Symbols and shapes). See the `feature_*`, `glyph_stone`
  and `tile_interior_*` hooks in §14.
- **Fly skips some puzzles.** Fly crosses lava and chasms, so a Gale beast lets you skip the Caldera geysers and
  the Skyreach updraft. Swim beats the Coast tide by design.
- **Nearby and NFC are untested on hardware.** Nearby needs two devices on the same build; NFC is switched off until the team
  supports the entitlement.
- **Challenge Card ghosts aren't verified.** Like online Versus, a card's stats are only clamped to 1–999.
- **Episode codes are drafts** and are stored as plain text in the app. Episodes 2 and 3 don't unlock a rumor yet.

---

## 20. Roadmap

- Final creature art and animations; music per region
- Spread the expansion species across wild lists and side quests
- Beastdex grid with element and stage filters
- Persistent shared world / MMO hub, Beast Clans, Beast Market (needs a backend such as CloudKit or a custom server)
- Server-validated ranked ladder, leaderboards, achievements
- Seasonal "Lattice Events" (special codes that summon limited beasts)
- Turn-based async battles (GKTurnBasedMatch) for players who can't play at the same time

---

## 21. Before launch: brand checklist

- [ ] Trademark search for "Beastopia" in classes 9, 28 and 41 (games/entertainment). Existing products may use the name.
- [ ] App Store name availability
- [ ] Domain availability (beastopia.com and alternatives)
- [ ] Enable Game Center for the App ID in App Store Connect
