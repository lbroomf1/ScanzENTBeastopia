//
//  AdventureView.swift
//  Beastopia
//

import SpriteKit
import SwiftUI

/// Explore a story region on foot. Walk up to NPCs to talk, wander through tall grass to find
/// wild beasts, and challenge the region's boss once the earlier quest steps are done.
struct AdventureView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("adventure.controlMode") private var controlMode: AdventureScene.ControlMode = .tap
    /// Whether the quest banner is folded down to just the compass.
    @AppStorage("adventure.guideCollapsed") private var guideCollapsed = false
    @State private var showTapHint = true

    /// The region currently being explored. Changes when the player walks through an exit.
    @State private var region: Region
    @State private var map: AdventureMap
    @State private var scene: AdventureScene?
    @State private var conversation: Objective?
    @State private var battle: BattleSession?
    @State private var battleObjective: Objective?
    @State private var toast: String?
    @State private var toastDuration = 2.5
    @State private var facility: Facility?
    @State private var showGuide = false
    /// Mirrors the scene's player position, for the quest compass.
    @State private var playerTile: Tile?
    @State private var lastBlockedHint = Date.distantPast
    /// Ability chests already pointed out this visit, so each hint shows once.
    @State private var chestHintsShown: Set<String> = []
    /// The region's name card, shown briefly on arrival.
    @State private var titleCard: String?
    /// One-time tutorials waiting to be read. The first one is on screen.
    @State private var tutorials: [Tutorial] = []
    /// IDs of tutorials the player has already read, comma separated.
    @AppStorage("adventure.tutorialsSeen") private var tutorialsSeen = ""
    /// The building the keeper is inside, if any.
    @State private var visit: BuildingVisit?
    /// A beast just awakened from the region's Element Glyph.
    @State private var glyphBeast: Beast?
    /// When an element puzzle message last showed, so geysers and arcs don't spam toasts.
    @State private var lastFieldHint = Date.distantPast

    /// Being inside a building: which door it was, so leaving puts the keeper back outside it.
    private struct BuildingVisit {
        let door: Tile
        let doorway: Doorway
    }

    /// A one-time explainer shown in a pixel text box, e.g. how to use a new field ability.
    private struct Tutorial: Identifiable, Equatable {
        let id: String
        let title: String
        let text: String
    }

    /// How close (in tiles) the keeper must get to an ability chest before it's pointed out.
    private static let chestHintRange = 6

    init(region: Region, map: AdventureMap) {
        _region = State(initialValue: region)
        _map = State(initialValue: map)
    }

    private var chapter: Chapter { region.chapter }
    private var activeObjective: Objective? { store.activeObjective(in: region) }
    private var isBusy: Bool {
        conversation != nil || battle != nil || facility != nil || showGuide || !tutorials.isEmpty || glyphBeast != nil
    }

    /// The region's outdoor map, even while the keeper is inside a building.
    private var outdoorMap: AdventureMap { AdventureMap.map(for: region) ?? map }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let scene {
                SpriteView(scene: scene)
                    .ignoresSafeArea()
                    // A new identity per scene, so SpriteView presents the new region after travel.
                    .id(ObjectIdentifier(scene))
                    .transition(.opacity)
                    .mapAccessibility(label: visit.map { "Inside \($0.doorway.name)" } ?? "Map of \(chapter.region)",
                                      value: mapDescription, actions: mapActions)
            }
        }
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) { bottomControls }
        .overlay(alignment: .bottom) {
            // Messages sit low, above the controls, instead of covering the middle of the map.
            if let toast {
                PixelTextBox(text: toast, tint: chapter.element.color)
                    .frame(maxWidth: 360)
                    .padding(.horizontal, 24)
                    .padding(.bottom, controlMode == .joystick ? 170 : 56)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if let titleCard {
                PixelTitleCard(title: titleCard, tint: chapter.element.color)
                    .padding(.top, 72)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .allowsHitTesting(false)
            }
        }
        .overlay { tutorialOverlay }
        .onAppear {
            if scene == nil { presentScene(at: spawnTile()) }
        }
        .onDisappear(perform: savePosition)
        .music(outdoorMap.theme.musicTrack)
        .onChange(of: controlMode, initial: true) { scene?.controlMode = controlMode }
        .onChange(of: isBusy) { scene?.isInputEnabled = !isBusy }
        .onChange(of: activeObjective?.id, initial: true) { refreshQuestState() }
        .onChange(of: store.completedChapters) {
            refreshQuestState()
            if store.completedChapters.contains(chapter.id) {
                showToast("Region complete! \(chapter.outro)", seconds: 5)
            }
        }
        .task(id: toast) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(toastDuration))
            withAnimation { toast = nil }
        }
        .task(id: titleCard) {
            guard titleCard != nil else { return }
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.easeOut(duration: 0.6)) { titleCard = nil }
        }
        .onChange(of: store.fieldAbilities, initial: true) {
            scene?.abilities = store.fieldAbilities
            queueAbilityTutorials()
        }
        .onChange(of: hasLumenBeast) { scene?.lightRadius = lightRadius }
        .sheet(item: $glyphBeast) { beast in
            SummonRevealView(beast: beast, note: glyphNote(for: beast))
        }
        .sheet(item: $facility) { FacilitySheet(facility: $0) }
        .sheet(isPresented: $showGuide) {
            QuestGuideSheet(region: region, map: map, objective: activeObjective) {
                showGuide = false
                showPath()
            }
        }
        .sheet(item: $conversation) { objective in
            if case let .talk(npc, dialogue) = objective.kind {
                DialogueView(npc: npc, dialogue: dialogue) {
                    store.completeObjective(objective, in: region)
                }
            }
        }
        .fullScreenCover(item: $battle) { session in
            BattleView(session: session) { won in
                if won, let objective = battleObjective {
                    store.completeObjective(objective, in: region)
                }
                battleObjective = nil
            }
        }
    }

    // MARK: - Tutorials

    /// The current tutorial over a dimmed map. Tap anywhere to continue.
    @ViewBuilder
    private var tutorialOverlay: some View {
        if let tutorial = tutorials.first {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.4).ignoresSafeArea()
                PixelTextBox(text: tutorial.text, title: tutorial.title, showsContinue: true,
                             tint: chapter.element.color)
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 16)
                    .padding(.bottom, controlMode == .joystick ? 170 : 40)
            }
            .contentShape(.rect)
            .onTapGesture(perform: dismissTutorial)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Double-tap to continue")
            .accessibilityAction { dismissTutorial() }
            .id(tutorial.id)
            .transition(.opacity)
        }
    }

    private var seenTutorials: Set<String> {
        Set(tutorialsSeen.split(separator: ",").map(String.init))
    }

    /// Queues a tutorial unless the player has already read it.
    private func queueTutorial(id: String, title: String, text: String) {
        guard !seenTutorials.contains(id), !tutorials.contains(where: { $0.id == id }) else { return }
        withAnimation { tutorials.append(Tutorial(id: id, title: title, text: text)) }
        AccessibilityNotification.Announcement("\(title). \(text)").post()
    }

    private func dismissTutorial() {
        guard let current = tutorials.first else { return }
        SoundFX.play(.tap)
        tutorialsSeen = seenTutorials.union([current.id]).sorted().joined(separator: ",")
        withAnimation { _ = tutorials.removeFirst() }
    }

    /// The first visit to each story region explains its element, its mechanic and its glyph.
    private func queueRegionTutorial() {
        let briefing = region.briefing
        var text = "\(briefing.element.displayName) region. \(briefing.element.blurb) "
        text += "\(briefing.mechanicText) "
        text += "\(briefing.bossName) is \(briefing.bossElement.displayName): \(briefing.countersText) beasts hit it hardest."
        if let glyph = briefing.glyphText {
            text += " Somewhere here an Element Glyph holds \(glyph). Find it!"
        }
        queueTutorial(id: "region.\(region.id)", title: briefing.mechanicTitle, text: text)
    }

    /// The first time the keeper has a beast that lends Swim, Fly or Blink, explain how to use it.
    private func queueAbilityTutorials() {
        for ability in TraversalAbility.allCases where store.fieldAbilities.contains(ability) {
            let helper = store.helper(for: ability)?.displayName ?? "One of your beasts"
            let how: String = switch ability {
            case .swim:
                "\(helper) can swim you across water! Just walk or tap onto the water and you'll swim. Look for treasure chests out on the waves."
            case .fly:
                "\(helper) can fly you over water, lava and chasms! Just walk or tap across them and you'll fly."
            case .teleport:
                controlMode == .tap
                    ? "\(helper) can Blink! Tap a spot up to \(AdventureScene.blinkRange) tiles away on the other side of a wall and you'll teleport there. Walled-in chests need this."
                    : "\(helper) can Blink! Face a wall and press the purple Blink button to teleport up to \(AdventureScene.blinkRange) tiles past it. Walled-in chests need this."
            }
            queueTutorial(id: "unlock.\(ability.rawValue)", title: "New ability: \(ability.displayName)",
                          text: how + " Any beast in your Haven lends its ability. It doesn't have to be your primary.")
        }
    }

    // MARK: - HUD

    private var topBar: some View {
        HStack(alignment: .top, spacing: 10) {
            Button("Leave", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.headline)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: .circle)

            if guideCollapsed {
                Spacer(minLength: 0)
                // Collapsed: just the compass, so the map stays clear.
                Button {
                    withAnimation(.snappy) { guideCollapsed = false }
                } label: {
                    HStack(spacing: 6) {
                        compass
                        Image(systemName: "chevron.down").font(.caption.bold())
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .background(.regularMaterial, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show quest")
            } else {
                HStack(alignment: .top, spacing: 6) {
                    Button {
                        SoundFX.play(.tap)
                        showGuide = true
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(questText)
                                    .font(.footnote.bold())
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                abilityChips
                            }
                            Spacer(minLength: 0)
                            compass
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows clues for the current quest")

                    Button {
                        withAnimation(.snappy) { guideCollapsed = true }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.caption.bold())
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hide quest")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: .rect(cornerRadius: 14))
                .transition(.opacity)
            }

            Menu {
                Picker("Controls", selection: $controlMode) {
                    ForEach(AdventureScene.ControlMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            } label: {
                Image(systemName: controlMode == .tap ? "hand.tap.fill" : "gamecontroller.fill")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: .circle)
            }
            .accessibilityLabel("Controls: \(controlMode.displayName)")
        }
        .padding(.horizontal)
    }

    private var questText: String {
        if let visit { return "Inside \(visit.doorway.name). Walk out the door to leave." }
        guard let objective = activeObjective else { return "Explore freely — this region is at peace." }
        if case .defeat = objective.kind {
            return "\(objective.summary) (search the tall grass)"
        }
        return objective.summary
    }

    /// Which field abilities the keeper's beasts lend, lit up when available.
    private var abilityChips: some View {
        HStack(spacing: 6) {
            ForEach(TraversalAbility.allCases) { ability in
                let has = store.fieldAbilities.contains(ability)
                GameIcon(art: ability.iconArt, symbol: ability.symbol, size: 16)
                    .font(.caption2.bold())
                    .foregroundStyle(has ? Color.accentColor : Color.secondary.opacity(0.4))
                    // Greys out the art version when locked; the symbol is already dimmed by its color.
                    .saturation(has ? 1 : 0)
                    .opacity(has || UIImage(named: ability.iconArt) == nil ? 1 : 0.45)
                    .accessibilityLabel("\(ability.displayName): \(has ? "available" : "locked")")
            }
            Text("\(chapter.region) · Tap for clues").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    /// Points from the player toward the current quest target.
    @ViewBuilder
    private var compass: some View {
        if let from = playerTile, let target = questTarget(from: from) {
            let dx = Double(target.col - from.col), dy = Double(target.row - from.row)
            let distance = abs(target.col - from.col) + abs(target.row - from.row)
            VStack(spacing: 2) {
                Image(systemName: "location.north.fill")
                    .font(.title3)
                    .foregroundStyle(chapter.element.color)
                    .rotationEffect(.radians(atan2(dx, -dy)))
                    .animation(.spring(duration: 0.3), value: atan2(dx, -dy))
                Text(distance <= 1 ? "Here" : "\(distance)").font(.caption2.bold().monospacedDigit())
            }
            .frame(width: 40)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Quest target \(distance) steps away")
        }
    }

    /// Where the active quest step is: its NPC or boss, or the nearest tall grass for a wild beast.
    private func questTarget(from tile: Tile) -> Tile? {
        guard visit == nil, let objective = activeObjective else { return nil }
        if let placed = map.placements[objective.id] { return placed }
        guard case .defeat = objective.kind else { return nil }
        return nearestTallGrass(to: tile)
    }

    private func nearestTallGrass(to tile: Tile) -> Tile? {
        var best: (tile: Tile, distance: Int)?
        for row in 0..<map.height {
            for col in 0..<map.width {
                let candidate = Tile(col: col, row: row)
                guard map.terrain(at: candidate) == .tallGrass else { continue }
                let distance = abs(col - tile.col) + abs(row - tile.row)
                if distance < (best?.distance ?? .max) { best = (candidate, distance) }
            }
        }
        return best?.tile
    }

    /// Lights a breadcrumb trail to the current quest target.
    private func showPath() {
        if visit != nil {
            showToast("Step back outside to follow the quest.")
            return
        }
        guard let scene, let objective = activeObjective else {
            showToast("Nothing left to do here. Explore freely!")
            return
        }
        let shown: Bool
        if let placed = map.placements[objective.id] {
            shown = scene.showTrail(toNeighborOf: placed)
        } else {
            let grass = (0..<map.height).flatMap { row in (0..<map.width).map { Tile(col: $0, row: row) } }
                .filter { map.terrain(at: $0) == .tallGrass }
            shown = scene.showTrail(toNeighborOf: nil, orAnyOf: Set(grass))
        }
        if !shown { showToast("Can't find a way there from here.") }
    }

    @ViewBuilder
    private var bottomControls: some View {
        switch controlMode {
        case .tap:
            if showTapHint {
                Text(store.fieldAbilities.contains(.teleport)
                     ? "Tap to walk · Tap past a wall to blink"
                     : "Tap anywhere to walk · Tap a character to talk")
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: .capsule)
                    .padding(.bottom)
                    .transition(.opacity)
                    // A reminder, not a fixture: it fades once the player has had time to read it.
                    .task {
                        try? await Task.sleep(for: .seconds(5))
                        withAnimation { showTapHint = false }
                    }
            }
        case .joystick:
            HStack(alignment: .bottom) {
                Joystick(onChange: { primary, secondary in
                    scene?.secondaryDirection = secondary
                    scene?.heldDirection = primary
                }, onStep: { scene?.step($0) })
                Spacer()
                if store.fieldAbilities.contains(.teleport) {
                    Button {
                        if scene?.blinkForward() != true { showToast("Nowhere to blink to that way.") }
                    } label: {
                        GameIcon(art: TraversalAbility.teleport.iconArt, symbol: TraversalAbility.teleport.symbol, size: 32)
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.purple.gradient, in: .circle)
                            .shadow(radius: 4)
                    }
                    .accessibilityLabel("Blink forward")
                    .padding(.bottom, 40)
                }
                Button {
                    scene?.interactWithNearby()
                } label: {
                    Text("A")
                        .font(.title.bold())
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(Color.accentColor.gradient, in: .circle)
                        .shadow(radius: 4)
                }
                .accessibilityLabel("Talk or interact")
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Scene events

    private func presentScene(at start: Tile) {
        var styles: [String: AdventureScene.EntityStyle] = [:]
        let tint = UIColor(chapter.element.color)
        for objective in region.objectives where map.placements[objective.id] != nil {
            switch objective.kind {
            case let .talk(npc, _):
                styles[objective.id] = .init(name: npc.name, symbol: npc.symbol, color: tint)
            case .boss:
                let species = SpeciesDatabase.species(chapter.opponentSpeciesID)
                styles[objective.id] = .init(name: chapter.opponentName, symbol: species?.symbol ?? "questionmark",
                                             color: .systemPurple)
            case .defeat:
                break
            }
        }
        var exitNames: [Int: String] = [:]
        for destination in Set(map.exits.values) {
            if visit != nil {
                exitNames[destination] = "Outside"
            } else if let target = WorldMap.regions.first(where: { $0.id == destination }) {
                exitNames[destination] = target.chapter.region
            }
        }

        let newScene = AdventureScene(map: map, start: start, entityStyles: styles, exitNames: exitNames)
        newScene.controlMode = controlMode
        if let keeper = store.keeper {
            newScene.playerColor = UIColor(keeper.color.color)
            newScene.playerSymbol = keeper.style.symbol
        }
        newScene.abilities = store.fieldAbilities
        newScene.isInputEnabled = !isBusy
        newScene.onInteract = { interact(with: $0) }
        newScene.onFacility = { facility in
            SoundFX.play(.tap)
            scene?.isInputEnabled = false
            self.facility = facility
        }
        newScene.onStep = { tile, terrain in stepped(onto: tile, terrain: terrain) }
        newScene.onBlocked = { blocked(by: $0) }
        newScene.onBlink = { SoundFX.play(.summon) }
        newScene.onFieldEvent = { handle($0) }
        newScene.updateTreasures(opened: store.openedChests)
        if let id = map.features.bramblePuzzleID, store.isSolved(id) { newScene.restoreOpenBrambles() }
        if let glyph = map.glyph { newScene.isGlyphClaimed = store.hasClaimed(glyph) }
        newScene.lightRadius = lightRadius
        playerTile = newScene.playerTile
        withAnimation(.easeInOut(duration: 0.35)) { scene = newScene }
        let title = visit?.doorway.name ?? chapter.region
        withAnimation(.spring(duration: 0.4)) { titleCard = title }
        AccessibilityNotification.Announcement(title).post()
        refreshQuestState()
        if visit == nil { queueRegionTutorial() }
    }

    private var hasLumenBeast: Bool { store.beasts.contains { $0.species.element == .lumen } }

    /// How far the keeper sees in a dark region: a Lumen beast in the Haven lights the way.
    private var lightRadius: CGFloat { hasLumenBeast ? 4.5 : 2.6 }

    /// The saved position, unless the keeper could no longer walk out of it. For example, they
    /// left while standing on a chest in the water, then sold the Tide beast that swam them there.
    private func spawnTile() -> Tile {
        guard let saved = store.adventurePositions[region.id],
              map.path(from: saved, toAnyOf: [map.start], abilities: store.fieldAbilities) != nil else { return map.start }
        return saved
    }

    private func savePosition() {
        // Inside a building, the keeper is saved standing just outside its door.
        if let visit {
            store.setAdventurePosition(AdventureMap.outside(visit.door), regionID: region.id)
            return
        }
        guard let tile = scene?.playerTile, map.exits[tile] == nil, map.doors[tile] == nil else { return }
        store.setAdventurePosition(tile, regionID: region.id)
    }

    private func stepped(onto tile: Tile, terrain: Terrain) {
        playerTile = tile
        if let destination = map.exits[tile] {
            if visit != nil { leaveBuilding() } else { travel(to: destination) }
        } else if let doorway = map.doors[tile] {
            enter(doorway, through: tile)
        } else if let glyph = map.glyph, glyph.tile == tile {
            touch(glyph)
        } else if let treasure = map.treasure(at: tile), store.open(treasure) {
            scene?.playTreasureOpened(treasure.id)
            SoundFX.play(.purchase)
            showToast("Treasure! \(treasure.loot.summary)", seconds: 3.5)
        } else {
            enteredTerrain(terrain)
            hintNearbyAbilityChest(from: tile)
        }
    }

    /// Explains which kind of beast would get the player across, at most every few seconds.
    private func blocked(by ability: TraversalAbility) {
        guard Date.now.timeIntervalSince(lastBlockedHint) > 4, !isBusy else { return }
        lastBlockedHint = .now
        let water = map.theme.waterName
        switch ability {
        case .swim:
            showToast("Deep \(water). A Tide beast like Ripplet could swim you across.", seconds: 3)
        case .fly:
            showToast("You can't cross the \(water) on foot. A flying beast like Fluffwing could carry you.", seconds: 3)
        case .teleport:
            if store.fieldAbilities.contains(.teleport) {
                showToast("Too far to blink. Get within \(AdventureScene.blinkRange) tiles, then tap the spot.", seconds: 3)
            } else {
                showToast("Walled in! A Lumen or Umbra beast (like Glimmet or Shadeling) can Blink you past walls.", seconds: 3.5)
            }
        }
    }

    /// The first time the player walks near a chest that needs Swim, Fly or Blink, explain how to reach it:
    /// a full tutorial the first time ever, then a short reminder once per visit.
    private func hintNearbyAbilityChest(from tile: Tile) {
        guard !isBusy,
              let chest = map.treasures.first(where: { treasure in
                  treasure.requires != nil && !store.openedChests.contains(treasure.id)
                      && !chestHintsShown.contains(treasure.id)
                      && max(abs(treasure.tile.col - tile.col), abs(treasure.tile.row - tile.row)) <= Self.chestHintRange
              }),
              let ability = chest.requires else { return }
        chestHintsShown.insert(chest.id)
        let has = store.fieldAbilities.contains(ability)
        let tutorialID = "chest.\(ability.rawValue).\(has ? "ready" : "locked")"
        if !seenTutorials.contains(tutorialID) {
            queueTutorial(id: tutorialID, title: "Treasure nearby!", text: chestTutorialText(ability, has: has))
        } else {
            showToast(chestReminderText(ability, has: has), seconds: 3.5)
        }
    }

    private func chestTutorialText(_ ability: TraversalAbility, has: Bool) -> String {
        let water = map.theme.waterName
        let helper = store.helper(for: ability)?.displayName ?? "your beast"
        switch (ability, has) {
        case (.swim, true):
            return "A chest is floating out in the \(water)! \(helper) can swim: tap the chest, or walk into the \(water), and you'll swim right to it."
        case (.swim, false):
            return "A chest is floating out in the \(water), but you can't swim yet. Any Tide beast (like Ripplet) lends you Swim. Scan codes to find one, then come back!"
        case (.fly, true):
            return "A chest sits out over the \(water)! \(helper) can fly: tap the chest, or walk onto the \(water), and you'll fly to it."
        case (.fly, false):
            return "A chest sits out over the \(water), but you can't cross it on foot. Any Gale beast (like Fluffwing) lends you Fly. Scan codes to find one, then come back!"
        case (.teleport, true):
            return controlMode == .tap
                ? "A chest is walled in nearby! \(helper) can Blink: get within \(AdventureScene.blinkRange) tiles, then tap the chest to teleport past the wall."
                : "A chest is walled in nearby! \(helper) can Blink: face the wall and press the purple Blink button to teleport up to \(AdventureScene.blinkRange) tiles."
        case (.teleport, false):
            return "A chest is walled in nearby. Only Blink can reach it. Any Lumen or Umbra beast (like Glimmet or Shadeling) lends you Blink."
        }
    }

    private func chestReminderText(_ ability: TraversalAbility, has: Bool) -> String {
        let water = map.theme.waterName
        switch (ability, has) {
        case (.swim, true): return "A chest is out in the \(water). Tap it to swim there!"
        case (.swim, false): return "A chest is out in the \(water). You'll need a Tide beast to swim."
        case (.fly, true): return "A chest is over the \(water). Tap it to fly there!"
        case (.fly, false): return "A chest is over the \(water). You'll need a Gale beast to fly."
        case (.teleport, true): return "A chest is walled in nearby. Tap it to Blink there!"
        case (.teleport, false): return "A chest is walled in nearby. Only Blink can reach it: bring a Lumen or Umbra beast."
        }
    }

    /// Walks in through a building's door.
    private func enter(_ doorway: Doorway, through door: Tile) {
        guard !isBusy else { return }
        savePosition()
        SoundFX.play(.tap)
        visit = BuildingVisit(door: door, doorway: doorway)
        let inside = AdventureMap.interior(doorway, regionID: region.id)
        map = inside
        presentScene(at: inside.start)
    }

    /// Walks back out of the building, onto the tile in front of its door.
    private func leaveBuilding() {
        guard let visit else { return }
        SoundFX.play(.tap)
        self.visit = nil
        map = outdoorMap
        presentScene(at: AdventureMap.outside(visit.door))
    }

    /// Stepping on the region's Element Glyph awakens the beast inside, once.
    private func touch(_ glyph: ElementGlyph) {
        guard !isBusy else { return }
        switch store.claim(glyph) {
        case .awakened(let beast):
            scene?.playGlyphAwakened()
            scene?.isInputEnabled = false
            glyphBeast = beast
        case .alreadyClaimed:
            showToast("The glyph is quiet. Its beast already answered your call.")
        case .havenFull:
            SoundFX.play(.denied)
            showToast("The glyph hums, but your Haven is full (\(store.havenCapacity)). Make room, then come back.", seconds: 3.5)
        }
    }

    /// The banner on the glyph beast's reveal: why this beast will help here.
    private func glyphNote(for beast: Beast) -> String {
        let briefing = region.briefing
        return "Element Glyph of \(chapter.region): \(beast.species.element.displayName) is strong against \(briefing.bossName)."
    }

    /// Explains element puzzle events with a toast and a sound, at most every few seconds for hazards.
    private func handle(_ event: AdventureScene.FieldEvent) {
        let isHazard = [.scorched, .zapped, .boulderStuck, .brambleBlocked].contains(event)
        if isHazard {
            guard Date.now.timeIntervalSince(lastFieldHint) > 3 else { return }
            lastFieldHint = .now
        }
        switch event {
        case .scorched:
            SoundFX.play(.hit)
            showToast("Scorched! Wait for the geyser to die down, then dash past.")
        case .zapped:
            SoundFX.play(.critical)
            showToast("Zapped! Watch the arcs flicker and cross while they're dark.")
        case .washedAshore:
            SoundFX.play(.miss)
            showToast("The tide rolled in and washed you ashore! Cross at low tide, or bring a Tide beast to swim.", seconds: 3.5)
        case .gust:
            SoundFX.play(.miss)
        case .boulderPushed:
            SoundFX.play(.guardUp)
        case .boulderSank:
            SoundFX.play(.knockout)
            showToast("The boulder fills the water. You can walk across now!")
        case .boulderStuck:
            SoundFX.play(.denied)
            showToast("It won't budge. Push it from another side.")
        case .bloomLit(let remaining):
            SoundFX.play(.heal)
            showToast("The bloom glows! \(remaining) more to go.")
        case .bramblesOpened:
            SoundFX.play(.evolve)
            if let id = map.features.bramblePuzzleID { store.markSolved(id) }
            showToast("The brambles wither away. The path is open!", seconds: 3)
        case .brambleBlocked:
            SoundFX.play(.denied)
            let blooms = map.features.blooms.count
            showToast(blooms > 1
                      ? "Thorny brambles block the way. Light all \(blooms) glowing blooms to open them."
                      : "Thorny brambles block the way. Step on the glowing bloom to open them.", seconds: 3)
        }
    }

    /// Walk through an exit into the neighboring region, if the story has opened it.
    private func travel(to destinationID: Int) {
        guard !isBusy, visit == nil,
              let destination = WorldMap.regions.first(where: { $0.id == destinationID }),
              let destinationMap = AdventureMap.map(for: destination) else { return }
        guard store.isUnlocked(destination.chapter) else {
            showToast("The way to \(destination.chapter.region) is sealed. Defeat \(chapter.opponentName) first!")
            return
        }
        let origin = region.id
        savePosition()
        region = destination
        map = destinationMap
        presentScene(at: destinationMap.arrivalTile(from: origin))
    }

    private func refreshQuestState() {
        let completed = Set(region.objectives.filter { store.isComplete($0, in: region) }.map(\.id))
        scene?.updateQuestState(activeObjectiveID: activeObjective?.id, completed: completed)
    }

    private func interact(with objectiveID: String) {
        guard let objective = region.objectives.first(where: { $0.id == objectiveID }) else { return }

        if store.isComplete(objective, in: region) {
            switch objective.kind {
            case let .talk(npc, _): showToast("\(npc.name) waves. \"Thanks for your help, \(store.keeper?.name ?? "Glyphkeeper")!\"")
            case .boss, .defeat: showToast("All is calm here now.")
            }
            return
        }
        guard let active = activeObjective, active.id == objective.id else {
            showToast("Not yet. First: \(activeObjective?.summary ?? "explore the region").")
            return
        }

        switch objective.kind {
        case .talk:
            scene?.isInputEnabled = false
            conversation = objective
        case .boss:
            startBattle(for: objective) { .story(chapter, beast: $0) }
        case .defeat:
            break
        }
    }

    /// Tall grass hides beasts: the quest's wild beast while that step is active, otherwise
    /// the occasional random wild beast for extra experience.
    private func enteredTerrain(_ terrain: Terrain) {
        guard terrain == .tallGrass, !isBusy else { return }

        if let objective = activeObjective, case let .defeat(encounter) = objective.kind {
            guard Double.random(in: 0..<1) < 0.3 else { return }
            showToast("\(encounter.name) leaps out of the grass!")
            startBattle(for: objective) { .encounter(encounter, chapterID: chapter.id, beast: $0) }
        } else if Double.random(in: 0..<1) < 0.08,
                  let speciesID = map.wildSpecies.randomElement(),
                  let species = SpeciesDatabase.species(speciesID) {
            let wild = Encounter(seed: "wild-\(UUID().uuidString)", name: "Wild \(species.name)",
                                 speciesID: speciesID, level: max(1, chapter.opponentLevel - 1))
            showToast("A wild \(species.name) appears!")
            startBattle(for: nil) { .encounter(wild, chapterID: chapter.id, beast: $0) }
        }
    }

    private func startBattle(for objective: Objective?, _ makeSession: (Beast) -> BattleSession) {
        guard let beast = store.partner else {
            showToast("You need a beast to battle. Scan a code to awaken one!")
            return
        }
        scene?.isInputEnabled = false
        battleObjective = objective
        battle = makeSession(store.battleReady(beast))
    }

    private func showToast(_ message: String, seconds: Double = 2.5) {
        toastDuration = seconds
        withAnimation { toast = message }
        AccessibilityNotification.Announcement(message).post()
    }

    // MARK: - VoiceOver

    /// Where the player is relative to the current quest target, read as the map's value.
    private var mapDescription: String {
        guard let from = playerTile ?? scene?.playerTile else { return questText }
        guard let target = questTarget(from: from) else { return questText }
        return "\(questText). Quest target is \(spokenOffset(from: from, to: target))."
    }

    /// Everywhere the player can walk to from VoiceOver: people, stations, chests, exits and the quest path.
    private var mapActions: [MapAccessibilityAction] {
        var actions: [MapAccessibilityAction] = [
            MapAccessibilityAction(name: "Show the way to the quest") { showPath() },
        ]
        for objective in region.objectives where map.placements[objective.id] != nil {
            let name: String = switch objective.kind {
            case let .talk(npc, _): "Talk to \(npc.name)"
            case .boss: "Challenge \(chapter.opponentName)"
            case .defeat: "Go to \(objective.summary)"
            }
            actions.append(MapAccessibilityAction(name: name) {
                if scene?.walkToInteract(objectiveID: objective.id) != true { showToast("Can't find a way there from here.") }
            })
        }
        for (tile, facility) in map.stations.sorted(by: { $0.value.name < $1.value.name }) {
            actions.append(MapAccessibilityAction(name: "Use \(facility.name)") {
                if scene?.walkToStation(at: tile) != true { showToast("Can't find a way there from here.") }
            })
        }
        for (tile, doorway) in map.doors.sorted(by: { $0.value.name < $1.value.name }) {
            actions.append(MapAccessibilityAction(name: "Enter \(doorway.name)") {
                if scene?.walk(to: tile) != true { showToast("Can't find a way there from here.") }
            })
        }
        if let glyph = map.glyph, !store.hasClaimed(glyph) {
            actions.append(MapAccessibilityAction(name: "Go to the Element Glyph") {
                if scene?.walk(to: glyph.tile) != true { showToast("Can't find a way there yet. Solve the region's puzzle first.") }
            })
        }
        for treasure in map.treasures where !store.openedChests.contains(treasure.id) {
            actions.append(MapAccessibilityAction(name: "Go to treasure chest") {
                if scene?.walk(to: treasure.tile) != true {
                    blocked(by: treasure.requires ?? .teleport)
                }
            })
        }
        let exits = Dictionary(grouping: map.exits.keys, by: { map.exits[$0] ?? 0 })
        for (destination, tiles) in exits.sorted(by: { $0.key < $1.key }) {
            guard let tile = tiles.min(by: { ($0.row, $0.col) < ($1.row, $1.col) }),
                  let name = visit != nil ? "outside" : WorldMap.regions.first(where: { $0.id == destination })?.chapter.region
            else { continue }
            actions.append(MapAccessibilityAction(name: visit != nil ? "Go outside" : "Travel to \(name)") {
                if scene?.walk(to: tile) != true { showToast("Can't find a way there from here.") }
            })
        }
        return actions
    }
}

/// A VoiceOver action on the map, e.g. "Go to Pip" or "Use Market".
struct MapAccessibilityAction: Identifiable {
    let id = UUID()
    let name: String
    let perform: () -> Void
}

extension View {
    /// Makes a SpriteKit map usable with VoiceOver: one element that describes where the player is,
    /// with a custom action for every place they can walk to (chosen by swiping up or down).
    func mapAccessibility(label: String, value: String, actions: [MapAccessibilityAction]) -> some View {
        accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityHint("Swipe up or down to choose a place to walk to, then double-tap.")
            .accessibilityActions {
                ForEach(actions) { action in
                    Button(action.name, action: action.perform)
                }
            }
    }
}

extension StepDirection {
    var spokenName: String {
        switch self {
        case .up: "up"
        case .down: "down"
        case .left: "left"
        case .right: "right"
        }
    }
}

/// Describes where `target` is from `from` in words, e.g. "4 steps up and 2 steps right".
func spokenOffset(from: Tile, to target: Tile) -> String {
    let dx = target.col - from.col, dy = target.row - from.row
    var parts: [String] = []
    if dy != 0 { parts.append("\(abs(dy)) step\(abs(dy) == 1 ? "" : "s") \(dy < 0 ? "up" : "down")") }
    if dx != 0 { parts.append("\(abs(dx)) step\(abs(dx) == 1 ? "" : "s") \(dx < 0 ? "left" : "right")") }
    return parts.isEmpty ? "right here" : parts.joined(separator: " and ")
}

/// A four-way virtual joystick. Reports the main held direction (or `nil` when released),
/// plus the weaker axis when held diagonally so the player can slide along walls.
struct Joystick: View {
    let onChange: (StepDirection?, StepDirection?) -> Void
    /// A single step, for VoiceOver users (who can't drag the stick).
    var onStep: ((StepDirection) -> Void)?

    @State private var knob: CGSize = .zero
    @State private var current: Reading?
    private let radius: CGFloat = 60

    private struct Reading: Equatable {
        let primary: StepDirection
        let secondary: StepDirection?
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
                .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 2))
            Circle()
                .fill(.white.opacity(0.9))
                .frame(width: 52, height: 52)
                .shadow(radius: 3)
                .offset(knob)
        }
        .frame(width: radius * 2, height: radius * 2)
        .contentShape(.circle)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let offset = CGSize(width: value.location.x - radius, height: value.location.y - radius)
                    let length = hypot(offset.width, offset.height)
                    let scale = length > radius ? radius / length : 1
                    knob = CGSize(width: offset.width * scale, height: offset.height * scale)
                    update(reading(for: offset))
                }
                .onEnded { _ in
                    withAnimation(.spring(duration: 0.2)) { knob = .zero }
                    update(nil)
                }
        )
        .accessibilityLabel("Movement joystick")
        .accessibilityHint("Swipe up or down to choose a direction, then double-tap to take a step.")
        .accessibilityActions {
            ForEach(StepDirection.allCases, id: \.self) { direction in
                Button("Step \(direction.spokenName)") { onStep?(direction) }
            }
        }
    }

    private func update(_ reading: Reading?) {
        guard reading != current else { return }
        current = reading
        onChange(reading?.primary, reading?.secondary)
    }

    private func reading(for offset: CGSize) -> Reading? {
        guard hypot(offset.width, offset.height) > 14 else { return nil }
        let horizontal: StepDirection = offset.width > 0 ? .right : .left
        let vertical: StepDirection = offset.height > 0 ? .down : .up
        let (major, minor) = abs(offset.width) > abs(offset.height)
            ? (abs(offset.width), abs(offset.height)) : (abs(offset.height), abs(offset.width))
        let primary = abs(offset.width) > abs(offset.height) ? horizontal : vertical
        let other = primary == horizontal ? vertical : horizontal
        // Only count the weaker axis when the stick is clearly leaning diagonally.
        return Reading(primary: primary, secondary: minor > major * 0.4 ? other : nil)
    }
}
