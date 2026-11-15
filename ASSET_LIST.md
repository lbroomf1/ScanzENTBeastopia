# Beastopia — Asset Checklist

The art, audio and store assets still needed, with the exact file names the game expects.
Game rules and content live in `GAME_DESIGN.md`. This file only tracks deliverables.

**How to add an asset:** drag the PNG into `Beastopia/Assets.xcassets` and name the image set exactly as listed.
Sections 1 and 2 work as soon as you drop the file in, with no code changes. The others need a small code hook first (§7).

**Status key:** `[ ]` to do · `[x]` done

**Totals:** 190 drop-in images · 3 app icons · about 60 more that need a code hook · about 10 music tracks · store materials

---

## 0. Required before App Store submission

- [x] `AppIcon`: light, 1024×1024 PNG, no transparency
- [x] `AppIcon`: dark variant, 1024×1024
- [x] `AppIcon`: tinted variant, 1024×1024, grayscale
- [ ] `AccentColor`: pick the brand color (currently unset, so it uses system blue)
- [ ] App Store screenshots: 6.9" iPhone (required) and 13" iPad if you ship on iPad
- [ ] App Store icon artwork, marketing name, subtitle and description
- [ ] Optional: App preview video (15–30 s)

---

## 1. Beast portraits — 105 images (drop-in)

**Spec:** transparent PNG, the beast centered, facing right or toward the viewer, with a little padding around it.
- Pixel art: 32×32 or 64×64 (anything ≤ 128 px stays crisp)
- Painted or vector: 512×512
- **One image per species.** Color variants (hue shift) and Prismatic shimmer are added in code.
- Shown in: Haven, Beastdex (as a black silhouette until discovered), battles, pickers, the scan reveal.

**Suggested order:** the 8 original rookies → all 32 rookies → story bosses → everything else.

### Ember (13)
- [x] `beast_cindrop` (Cindrop, Rookie)
- [x] `beast_pyrowl` (Pyrowl, Adult)
- [x] `beast_magmaw` (Magmaw, Adult) **story boss, ch 2**
- [x] `beast_infernox` (Infernox, Apex)
- [x] `beast_kindlekit` (Kindlekit, Rookie)
- [x] `beast_blazefang` (Blazefang, Adult)
- [x] `beast_ashveil` (Ashveil, Adult)
- [x] `beast_pyrelord` (Pyrelord, Apex)
- [x] `beast_charbug` (Charbug, Rookie)
- [x] `beast_scorchitin` (Scorchitin, Adult)
- [x] `beast_volcarapace` (Volcarapace, Apex)
- [x] `beast_fizzlet` (Fizzlet, Rookie)
- [x] `beast_pyrotechnix` (Pyrotechnix, Adult)

### Tide (12)
- [x] `beast_ripplet` (Ripplet, Rookie)
- [x] `beast_tidecrest` (Tidecrest, Adult) **story boss, ch 3**
- [x] `beast_leviathorn` (Leviathorn, Apex)
- [x] `beast_puddlepup` (Puddlepup, Rookie)
- [x] `beast_brinehound` (Brinehound, Adult)
- [x] `beast_mistmane` (Mistmane, Adult)
- [x] `beast_abyssalisk` (Abyssalisk, Apex)
- [x] `beast_shellbe` (Shellbe, Rookie)
- [x] `beast_coralisk` (Coralisk, Adult)
- [x] `beast_reefmonarch` (Reefmonarch, Apex)
- [x] `beast_frostfin` (Frostfin, Rookie)
- [x] `beast_glaciaray` (Glaciaray, Adult)

### Verdant (12)
- [x] `beast_sproutle` (Sproutle, Rookie) **story boss, ch 1**
- [x] `beast_thornback` (Thornback, Adult) **story boss, ch 4**
- [x] `beast_elderoot` (Elderoot, Apex)
- [x] `beast_budling` (Budling, Rookie)
- [x] `beast_bloomtail` (Bloomtail, Adult)
- [x] `beast_briarmaw` (Briarmaw, Adult)
- [x] `beast_verdantitan` (Verdantitan, Apex)
- [x] `beast_mossnail` (Mossnail, Rookie)
- [x] `beast_lichenshell` (Lichenshell, Adult)
- [x] `beast_grovekeep` (Grovekeep, Apex)
- [x] `beast_spudsy` (Spudsy, Rookie)
- [x] `beast_rootrumble` (Rootrumble, Adult)

### Gale (12)
- [x] `beast_fluffwing` (Fluffwing, Rookie)
- [x] `beast_zephyrix` (Zephyrix, Adult) **story boss, ch 5**
- [x] `beast_tempestrix` (Tempestrix, Apex)
- [x] `beast_puffwisp` (Puffwisp, Rookie)
- [x] `beast_stormhorn` (Stormhorn, Adult)
- [x] `beast_nimbusoar` (Nimbusoar, Adult)
- [x] `beast_skyshroud` (Skyshroud, Apex)
- [x] `beast_featherling` (Featherling, Rookie)
- [x] `beast_galeharrier` (Galeharrier, Adult)
- [x] `beast_aerozenith` (Aerozenith, Apex)
- [x] `beast_whirlbit` (Whirlbit, Rookie)
- [x] `beast_cyclonyx` (Cyclonyx, Adult)

### Terra (12)
- [x] `beast_pebblit` (Pebblit, Rookie)
- [x] `beast_bouldrake` (Bouldrake, Adult) **story boss, ch 6**
- [x] `beast_gravolith` (Gravolith, Apex)
- [x] `beast_clodlet` (Clodlet, Rookie)
- [x] `beast_quarrox` (Quarrox, Adult)
- [x] `beast_dunebadger` (Dunebadger, Adult)
- [x] `beast_terragnaw` (Terragnaw, Apex)
- [x] `beast_geodite` (Geodite, Rookie)
- [x] `beast_crystalback` (Crystalback, Adult)
- [x] `beast_prismolith` (Prismolith, Apex)
- [x] `beast_burrowmole` (Burrowmole, Rookie)
- [x] `beast_tunnelgrinder` (Tunnelgrinder, Adult)

### Volt (12)
- [x] `beast_sparkit` (Sparkit, Rookie)
- [x] `beast_joltusk` (Joltusk, Adult)
- [x] `beast_thundervex` (Thundervex, Apex) **story boss, ch 7**
- [x] `beast_zaplet` (Zaplet, Rookie)
- [x] `beast_ampereon` (Ampereon, Adult)
- [x] `beast_voltwatt` (Voltwatt, Adult)
- [x] `beast_dynamotor` (Dynamotor, Apex)
- [x] `beast_buzzbee` (Buzzbee, Rookie)
- [x] `beast_stingcoil` (Stingcoil, Adult)
- [x] `beast_tesladon` (Tesladon, Apex)
- [x] `beast_staticat` (Staticat, Rookie)
- [x] `beast_fluxlynx` (Fluxlynx, Adult)

### Lumen (12)
- [x] `beast_glimmet` (Glimmet, Rookie)
- [x] `beast_radiantail` (Radiantail, Adult)
- [x] `beast_solaryx` (Solaryx, Apex)
- [x] `beast_lumoth` (Lumoth, Rookie)
- [x] `beast_halomoth` (Halomoth, Adult)
- [x] `beast_lanternwing` (Lanternwing, Adult)
- [x] `beast_celestimoth` (Celestimoth, Apex)
- [x] `beast_prismpup` (Prismpup, Rookie)
- [x] `beast_starmane` (Starmane, Adult)
- [x] `beast_novaleon` (Novaleon, Apex)
- [x] `beast_dewglow` (Dewglow, Rookie)
- [x] `beast_auroracub` (Auroracub, Adult)

### Umbra (12)
- [x] `beast_shadeling` (Shadeling, Rookie)
- [x] `beast_nocturne` (Nocturne, Adult)
- [x] `beast_eclipsar` (Eclipsar, Apex)
- [x] `beast_gloomkit` (Gloomkit, Rookie)
- [x] `beast_duskstalker` (Duskstalker, Adult)
- [x] `beast_hexhowl` (Hexhowl, Adult)
- [x] `beast_voidfang` (Voidfang, Apex)
- [x] `beast_murkling` (Murkling, Rookie)
- [x] `beast_wraithveil` (Wraithveil, Adult)
- [x] `beast_phantasmire` (Phantasmire, Apex)
- [x] `beast_batling` (Batling, Rookie)
- [x] `beast_nightwing` (Nightwing, Adult)

### Mythic (8)
- [x] `beast_aurorion` (Aurorion)
- [x] `beast_chronodrake` (Chronodrake)
- [x] `beast_maelstryx` (Maelstryx)
- [x] `beast_oblivyrn` (Oblivyrn) **final boss, ch 8**
- [x] `beast_vaporgeist` (Vaporgeist)
- [x] `beast_sylvanwyrm` (Sylvanwyrm)
- [x] `beast_halostorm` (Halostorm)
- [x] `beast_magmarch` (Magmarch)

---

## 2. World map sprites — 85 images (drop-in)

### Terrain tiles (64)
**Spec:** square, opaque, and they must tile seamlessly next to each other. On screen a tile is 48 pt (144 px at @3x), so 16 px art scales 9× cleanly.
Keep tiles at 16×16 to match the generic set.

Name: `tile_<theme>_<terrain>`. A generic `tile_<terrain>` is used for any theme without its own tile, so the
**minimum is 8 generic tiles**. Fill in themed tiles over time.

| Theme (region) | grass | tallGrass | path | flowers | tree | water | fence | building |
|---|---|---|---|---|---|---|---|---|
| `meadow` (Beast Haven) | [x] | [x] | [x] | [x] | [x] | [x] | [x] | [x] |
| `volcano` (Emberfall Caldera) | [x] | [x] | [x] | [x] | [x] rock | [x] lava | [x] | [x] |
| `coast` (Tidewhisper Coast) | [x] sand | [x] dune grass | [x] pier | [x] | [x] palm | [x] sea | [x] | [x] hut |
| `forest` (Greenmantle Wilds) | [x] | [x] | [x] | [x] | [x] | [x] | [x] | [x] ruin |
| `peaks` (Skyreach Peaks) | [x] rock | [x] snowdrift | [x] | [x] | [x] cliff | [x] chasm | [x] | [x] airship dock |
| `quarry` (Gravel Hollow) | [x] gravel | [x] rubble | [x] | [x] | [x] boulder | [x] flooded pit | [x] | [x] cell block |
| `marsh` (Voltmarsh) | [x] bog | [x] charged reeds | [x] | [x] | [x] dead tree | [x] bog water | [x] | [x] hut |
| `spire` (Null Spire) | [x] glyph floor | [x] glyph grass | [x] | [x] | [x] crystal | [x] void | [x] | [x] |
| generic fallback `tile_<terrain>` | [x] | [x] | [x] | [x] | [x] | [x] | [x] | [x] |

Example names: `tile_meadow_grass`, `tile_volcano_water`, `tile_grass`.

### Characters and objects (21)
**Spec:** transparent PNG, about one tile in size, standing on the bottom edge. The game adds the ground shadow.

- [x] `player`: the keeper (faces right; the game flips it for left)
- [x] `chest`: closed treasure chest
- [x] `chest_open`: opened chest
- [x] `player_swim`, `player_fly`: the keeper on water
- [x] `marker_quest`, `marker_exit` (points right), `marker_trail`
- [x] `fx_sparkle`, `fx_sparkle_1`…`fx_sparkle_3`: sparkle burst frames
- [x] `ui_signpost`: exit signpost board (24×16, 4 px border)

NPC and boss sprites, one image set per name. Kade appears four times; use the same image for all four sets.

| Region | Sprites |
|---|---|
| 1 Beast Haven | [x] `npc_ch1-pip` (Pip) · [x] `npc_ch1-boss` (possessed training dummy / Haven Sprout) |
| 2 Emberfall Caldera | [x] `npc_ch2-brasa` (Elder Brasa) · [x] `npc_ch2-boss` (Feral Magmaw) |
| 3 Tidewhisper Coast | [x] `npc_ch3-nell` (Nell) · [x] `npc_ch3-kade` (Kade) · [x] `npc_ch3-boss` (Kade's Tidecrest) |
| 4 Greenmantle Wilds | [x] `npc_ch4-ivy` (Ranger Ivy) · [x] `npc_ch4-boss` (Warden Thornback) |
| 5 Skyreach Peaks | [x] `npc_ch5-wren` (Wren) · [x] `npc_ch5-boss` (Commander Vey's Zephyrix) |
| 6 Gravel Hollow | [x] `npc_ch6-rook` (Rook) · [x] `npc_ch6-kade` (Kade) · [x] `npc_ch6-boss` (Syndicate Bouldrake) |
| 7 Voltmarsh | [x] `npc_ch7-kade` (Kade) · [x] `npc_ch7-boss` (Gatekeeper Thundervex) |
| 8 Null Spire | [x] `npc_ch8-maren` (Maren) · [x] `npc_ch8-kade` (Kade) · [x] `npc_ch8-boss` (Oblivyrn) |

Boss sprites can simply be smaller versions of that species' `beast_` art.

---

## 3. Characters for dialogue — 9 portraits (needs code hook)

Currently each character is an SF Symbol in a colored circle (`NPCAvatar`). These are the bust portraits shown in conversations.
**Spec:** 512×512 transparent PNG, head and shoulders. Optional extra expressions: neutral, happy, worried.

- [x] `portrait_pip`: Pip, Haven Caretaker
- [x] `portrait_brasa`: Elder Brasa, Caldera Village Elder
- [x] `portrait_nell`: Nell, Tidewhisper Fisher
- [x] `portrait_kade`: Kade, Rival Glyphkeeper
- [x] `portrait_ivy`: Ranger Ivy, Warden of the Wilds
- [x] `portrait_wren`: Wren, Skyreach Courier
- [x] `portrait_rook`: Rook, Syndicate Deserter
- [x] `portrait_maren`: Maren, Your Mentor
- [ ] `portrait_vey`: Commander Vey (mentioned in the story; no dialogue yet)
- [ ] `portrait_keeper`: the player, for "You" lines (optional)

---

## 4. Icons — 31 images (needs code hook)

Currently SF Symbols. **Spec:** 128×128 transparent PNG, readable at 24 pt.

### Items (9)
- [x] `item_berry` (Glow Berry)
- [x] `item_potion` (Healing Draught)
- [x] `item_fullElixir` (Full Elixir)
- [x] `item_remedy` (Remedy Herb)
- [x] `item_gutsTonic` (Guts Tonic)
- [x] `item_latticeCandy` (Lattice Candy)
- [x] `item_starCandy` (Star Candy)
- [x] `item_bondTreat` (Bond Treat)
- [x] `item_calmTea` (Calm Tea)

### Elements (8)
- [x] `element_ember` · [x] `element_tide` · [x] `element_verdant` · [x] `element_gale`
- [x] `element_terra` · [x] `element_volt` · [x] `element_lumen` · [x] `element_umbra`

### Status, abilities, currency and stats (14)
- [x] `status_burn` · [x] `status_shock` · [x] `status_blight`
- [x] `ability_swim` · [x] `ability_fly` · [x] `ability_blink`
- [x] `currency_coin` · [x] `currency_shard` (Lattice Shard)
- [x] `stat_life` · [x] `stat_power` · [x] `stat_intellect` · [x] `stat_defense` · [x] `stat_speed` · [x] `stat_skill`

---

## 5. Stations, scenes and UI — about 25 images (needs code hook)

### Map stations (6)
One tile in size and transparent. They currently show as teal boxes with a symbol.
- [x] `station_stable` · [x] `station_feedingTrough` · [x] `station_hotSpring`
- [x] `station_trainingPost` · [x] `station_market` · [x] `station_campfire`

### Battle backgrounds (8)
One per region, replacing the painted gradient. **Spec:** 1290×2796 (iPhone portrait), opaque, with an empty middle
area where beasts stand.
- [x] `battle_bg_meadow` · [x] `battle_bg_volcano` · [x] `battle_bg_coast` · [x] `battle_bg_forest`
- [x] `battle_bg_peaks` · [x] `battle_bg_quarry` · [x] `battle_bg_marsh` · [x] `battle_bg_spire`
- [x] `battle_bg_arena`: Arena practice, raids and online matches

### Screens and branding
- [ ] `worldmap_background`: illustrated map of the 8 regions (currently a gradient). Region pins sit at fixed positions; the coordinates are in `WorldMap.swift`.
- [ ] `logo_beastopia`: title wordmark (transparent PNG, or SVG/PDF)
- [x] `haven_background`: Beast Haven grounds for the Haven tab
- [x] `menu_bg_main`, `menu_bg_beastdex`, `menu_bg_market`, `menu_bg_settings`, `menu_bg_title`: screen backgrounds
- [x] Loading sequence: `loading_scanz`, `loading_beastopia_clean` (plus the `loading_beastopia` mock-up),
  `loading_beast_1`…`_4`, `logo_scanz`. The studio styling (teal "SCANZ" with a small "ent") is still a guess; confirm it.
- [x] `scan_frame`: the Lattice Lens viewfinder overlay
- [x] `summon_burst`: light burst behind a newly summoned beast
- [ ] Launch screen art (logo on the brand background)

### UI kit (optional; the code-drawn style works without it)
- [ ] `ui_panel` (9-slice frame) · [ ] `ui_button` (9-slice, normal and pressed) · [ ] `ui_hp_bar` · [ ] `ui_guts_bar`
- [x] Custom font: `BeastopiaPixel.ttf` (used for map labels; titles and numbers elsewhere still use the system font). Record its license before launch.

---

## 6. Audio (needs code hook)

All 20 sound effects are currently synthesized in code (`SoundFX.swift`). Recorded audio is optional for those, but
**music doesn't exist yet**. **Spec:** `.m4a` (AAC) or `.caf`. Music should loop seamlessly, 1–3 minutes long.

### Music (about 10 tracks)
- [x] `music_title`: title and main menu
- [x] `music_haven`: Beast Haven
- [x] `music_caldera` · [x] `music_coast` · [x] `music_wilds` · [x] `music_skyreach`
- [x] `music_quarry` · [x] `music_voltmarsh` · [x] `music_spire`
- [x] `music_battle`: regular battles
- [x] `music_boss`: chapter bosses and raids
- [x] `music_finale`: Oblivyrn fight (optional)
- [ ] Short stings: `sting_victory`, `sting_defeat`, `sting_evolve`, `sting_summon`

### Sound effects (optional replacements, 20)
UI: `tap`, `train`, `feed`, `rest`, `levelUp`, `evolve`, `purchase`, `denied`, `primary`, `release`, `summon`, `fuse`
Battle: `hit`, `critical`, `miss`, `guardUp`, `heal`, `knockout`, `victory`, `defeat`

---

## 7. Code hooks still needed

These assets need a few lines of code before the game uses them. Ask for whichever group you're ready to deliver:

| Group | Where it would hook in |
|---|---|
| ~~Dialogue portraits (§3)~~ | Done: `NPCAvatar` (`portrait_keeper` and `portrait_vey` are delivered but unused: the keeper is customizable and Vey has no dialogue) |
| ~~Item, element, status and other icons (§4)~~ | Done: `GameIcon` / `GameLabel` in `GameTheme.swift` |
| ~~Station sprites (§5)~~ | Done: `AdventureScene.buildStations()` |
| ~~Battle backgrounds (§5)~~ | Done: `BattleBackdrop(art:)` |
| ~~Beast idle frames and summon effects~~ | Done: `Views/BeastAnimation.swift` |
| World map, logo and scan art (§5) | `WorldMapView`, `ScanView` (Haven and menu backgrounds are done: `.menuBackground`) |
| ~~Music (§6)~~ | Done: `Engine/MusicPlayer.swift` |
| UI kit images, `launch_screen` | In the catalog, not used yet: the code-drawn panels and buttons are still in place |
| Boss sprites reusing `beast_` art | `AdventureScene.buildEntities()`, so the `npc_chX-boss` files become unnecessary |

---

## Art direction: decide first
- [ ] Style: pixel art, hand-painted or vector/chibi. **Use one style for everything.**
- [ ] Sprite size: beasts (32, 64 or 512 px) and tiles (16, 32 or 168 px)
- [ ] Palette: should element colors match the in-game ones (Ember orange, Tide blue, Verdant green, Gale mint, Terra brown, Volt yellow, Lumen pink, Umbra purple)?
- [ ] Source and license for each asset pack or artist, recorded here before launch
