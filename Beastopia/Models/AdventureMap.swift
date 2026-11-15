//
//  AdventureMap.swift
//  Beastopia
//

import Foundation

/// A grid position in an adventure map. Row 0 is the top of the map.
nonisolated struct Tile: Hashable, Codable, Sendable {
    var col: Int
    var row: Int

    func moved(_ direction: StepDirection) -> Tile {
        Tile(col: col + direction.dx, row: row + direction.dy)
    }

    var neighbors: [Tile] { StepDirection.allCases.map(moved) }
}

enum StepDirection: CaseIterable, Sendable {
    case up, down, left, right

    var dx: Int {
        switch self {
        case .left: -1
        case .right: 1
        case .up, .down: 0
        }
    }

    /// Positive is down the map (towards higher rows).
    var dy: Int {
        switch self {
        case .up: -1
        case .down: 1
        case .left, .right: 0
        }
    }

    static func between(_ from: Tile, _ to: Tile) -> StepDirection? {
        allCases.first { from.moved($0) == to }
    }

    /// The two directions at right angles to this one.
    var perpendicular: [StepDirection] {
        switch self {
        case .up, .down: [.left, .right]
        case .left, .right: [.up, .down]
        }
    }
}

/// The look of a region. Terrain keeps its meaning (walls block, tall grass hides beasts),
/// but each theme dresses it differently: trees become rocks, water becomes lava, and so on.
enum MapTheme: Sendable {
    case meadow, volcano, coast, forest, peaks, quarry, marsh, spire
    /// The inside of a building: wooden floor, walls and counters.
    case interior

    /// Whether "water" tiles are real water a swimmer can cross. Lava, chasms and the void need wings.
    var hasLiquidWater: Bool {
        switch self {
        case .meadow, .coast, .forest, .quarry, .marsh, .interior: true
        case .volcano, .peaks, .spire: false
        }
    }

    /// What water tiles are called in this region, for hints.
    var waterName: String {
        switch self {
        case .volcano: "lava"
        case .peaks: "chasm"
        case .spire: "void"
        default: "water"
        }
    }
}

/// A place on the map where the keeper can look after their beasts, like the Haven's
/// barn and feeding trough. Stations block movement and are used by walking up to them.
enum Facility: String, Identifiable, Sendable {
    case stable, feedingTrough, hotSpring, trainingPost, market, campfire
    /// The innkeeper's desk: rests every beast at once.
    case inn

    var id: String { rawValue }

    var name: String {
        switch self {
        case .stable: "Stable"
        case .feedingTrough: "Feeding Trough"
        case .hotSpring: "Hot Spring"
        case .trainingPost: "Training Post"
        case .market: "Market"
        case .campfire: "Campfire"
        case .inn: "Innkeeper"
        }
    }

    var symbol: String {
        switch self {
        case .stable: "bed.double.fill"
        case .feedingTrough: "carrot.fill"
        case .hotSpring: "drop.circle.fill"
        case .trainingPost: "figure.strengthtraining.traditional"
        case .market: "storefront.fill"
        case .campfire: "flame.fill"
        case .inn: "moon.zzz.fill"
        }
    }

    var summary: String {
        switch self {
        case .stable: "Rest here to clear fatigue."
        case .feedingTrough: "A hearty meal: bond up, fatigue down."
        case .hotSpring: "A long soak clears all fatigue (30 coins)."
        case .trainingPost: "Drill a stat with Beast Training."
        case .market: "Buy healing, cures, candies and more."
        case .campfire: "Rest by the fire before pressing on."
        case .inn: "Stay the night: every beast wakes up with no fatigue (\(GameStore.innCost) coins)."
        }
    }
}

/// A treasure chest. Chests don't block movement; stepping onto one opens it.
/// Some sit on water, lava or behind walls and need a beast's field ability to reach.
struct Treasure: Identifiable, Sendable {
    /// Stable and persisted, so never rename.
    let id: String
    let tile: Tile
    let loot: Loot
    var requires: TraversalAbility? = nil
}

/// Ground types. The raw value is the character used when drawing maps as text.
enum Terrain: Character, Sendable {
    case grass = "."
    case tallGrass = ","
    case path = "="
    case flowers = "F"
    case tree = "T"
    case water = "~"
    case fence = "#"
    case building = "H"

    var isWalkable: Bool {
        switch self {
        case .grass, .tallGrass, .path, .flowers: true
        case .tree, .water, .fence, .building: false
        }
    }
}

/// A walkable 2D layout for a story region. Quest NPCs and bosses are placed on tiles by
/// objective ID; "defeat" objectives are found by walking through tall grass.
struct AdventureMap: Sendable {
    let regionID: Int
    let theme: MapTheme
    let terrain: [[Terrain]]
    let start: Tile
    /// Objective ID → the tile where that objective's NPC or boss stands.
    let placements: [String: Tile]
    /// Species that can appear as random wild encounters in tall grass.
    let wildSpecies: [String]
    /// Edge tiles that lead to a neighboring region, keyed by tile → destination region ID.
    let exits: [Tile: Int]
    /// Care stations such as the Haven's stable and market.
    let stations: [Tile: Facility]
    let treasures: [Treasure]
    /// When set, the map's building tiles form one structure drawn with this single piece of art
    /// (centered on them, keeping its shape) instead of roof and wall tiles.
    let buildingArt: String?
    /// Building doors the keeper can walk through, keyed by the door tile (the middle of the front wall).
    let doors: [Tile: Doorway]
    /// The region's element mechanic: geysers, tides, brambles, gusts, boulders, arcs or darkness.
    let features: ElementFeatures
    /// The region's Element Glyph, which awakens a beast strong against the boss.
    let glyph: ElementGlyph?
    /// How the puzzle starts on every visit (boulders in place, brambles closed).
    let initialState: FieldState

    init(regionID: Int, theme: MapTheme, layout: [String], start: Tile,
         placements: [String: Tile], wildSpecies: [String], exits: [Int: [Tile]] = [:],
         stations: [Tile: Facility] = [:], treasures: [Treasure] = [], buildingArt: String? = nil,
         doors: [Tile: Doorway] = [:], features: ElementFeatures = ElementFeatures(), glyph: ElementGlyph? = nil) {
        self.regionID = regionID
        self.theme = theme
        var terrain = layout.map { row in row.map { Terrain(rawValue: $0) ?? .grass } }
        var exitTiles: [Tile: Int] = [:]
        // Exits are carved out of the map's border as path tiles, so layouts stay simple.
        for (destination, tiles) in exits {
            for tile in tiles where terrain.indices.contains(tile.row) && terrain[tile.row].indices.contains(tile.col) {
                terrain[tile.row][tile.col] = .path
                exitTiles[tile] = destination
            }
        }
        self.terrain = terrain
        self.start = start
        self.placements = placements
        self.wildSpecies = wildSpecies
        self.exits = exitTiles
        self.stations = stations
        self.treasures = treasures
        self.buildingArt = buildingArt
        self.doors = doors
        self.features = features
        self.glyph = glyph
        self.initialState = FieldState(boulders: features.boulders, bramblesOpen: features.brambles.isEmpty)
    }

    /// The puzzle with every part solved: brambles open, boulders out of the way. Used to check
    /// that everything on the map can be reached once the keeper has figured the region out.
    var solvedState: FieldState {
        FieldState(boulders: [], litBlooms: features.blooms, bramblesOpen: true)
    }

    /// Where the player appears when arriving from `regionID`: just inside the exit that leads back there.
    func arrivalTile(from regionID: Int) -> Tile {
        let doorway = exits.filter { $0.value == regionID }.keys.sorted { ($0.row, $0.col) < ($1.row, $1.col) }
        for tile in doorway {
            if let inside = tile.neighbors.first(where: { isWalkable($0) && exits[$0] == nil }) { return inside }
        }
        return start
    }

    var height: Int { terrain.count }
    var width: Int { terrain.first?.count ?? 0 }

    func terrain(at tile: Tile) -> Terrain? {
        guard terrain.indices.contains(tile.row), terrain[tile.row].indices.contains(tile.col) else { return nil }
        return terrain[tile.row][tile.col]
    }

    /// Whether the player can stand on `tile` on foot. Tiles occupied by NPCs, bosses or stations are blocked.
    func isWalkable(_ tile: Tile) -> Bool {
        canEnter(tile, with: [])
    }

    /// Whether the player can move onto `tile` with help from their beasts' field abilities.
    /// `state` is the region's puzzle as it stands (where the boulders are, whether the tide is in);
    /// `nil` means how it starts.
    func canEnter(_ tile: Tile, with abilities: Set<TraversalAbility>, in state: FieldState? = nil) -> Bool {
        let state = state ?? initialState
        guard let terrain = terrain(at: tile), !isOccupied(tile), !state.boulders.contains(tile) else { return false }
        if features.brambles.contains(tile) && !state.bramblesOpen { return false }
        // Doors lead inside; gusts carry the keeper even over a chasm; filled water is solid ground.
        if doors[tile] != nil || features.gusts[tile] != nil || state.filled.contains(tile) { return true }
        if isFlooded(tile, in: state) { return abilities.contains(.swim) || abilities.contains(.fly) }
        if terrain.isWalkable { return true }
        guard terrain == .water else { return false }
        return abilities.contains(.fly) || (abilities.contains(.swim) && theme.hasLiquidWater)
    }

    /// Whether `tile` is tidal sand that's under water right now.
    func isFlooded(_ tile: Tile, in state: FieldState) -> Bool {
        state.highTide && features.tideFlats.contains(tile)
    }

    /// The ability needed to cross this tile, if it's water-like terrain the player can't walk on.
    func abilityNeeded(for tile: Tile, in state: FieldState? = nil) -> TraversalAbility? {
        if let state, isFlooded(tile, in: state) { return .swim }
        guard terrain(at: tile) == .water, features.gusts[tile] == nil,
              !(state?.filled.contains(tile) ?? false) else { return nil }
        return theme.hasLiquidWater ? .swim : .fly
    }

    /// Where the keeper can go from `tile`. A gust only lets you go where it blows (when it can).
    func moves(from tile: Tile, abilities: Set<TraversalAbility>, in state: FieldState) -> [Tile] {
        if let direction = features.gusts[tile], canEnter(tile.moved(direction), with: abilities, in: state) {
            return [tile.moved(direction)]
        }
        return tile.neighbors
    }

    func isOccupied(_ tile: Tile) -> Bool {
        placements.values.contains(tile) || stations[tile] != nil
    }

    func objectiveID(at tile: Tile) -> String? {
        placements.first { $0.value == tile }?.key
    }

    func treasure(at tile: Tile) -> Treasure? {
        treasures.first { $0.tile == tile }
    }

    /// Shortest walk from `start` to any tile in `goals` (breadth-first search).
    /// Returns the steps to take, not including `start`; empty if already at a goal; `nil` if unreachable.
    func path(from start: Tile, toAnyOf goals: Set<Tile>, abilities: Set<TraversalAbility> = [],
              in state: FieldState? = nil) -> [Tile]? {
        let state = state ?? initialState
        if goals.contains(start) { return [] }
        var cameFrom: [Tile: Tile] = [:]
        var visited: Set<Tile> = [start]
        var queue = [start]
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            for next in moves(from: current, abilities: abilities, in: state)
            where !visited.contains(next) && canEnter(next, with: abilities, in: state) {
                visited.insert(next)
                cameFrom[next] = current
                if goals.contains(next) {
                    var steps = [next]
                    var tile = next
                    while let previous = cameFrom[tile], previous != start {
                        steps.append(previous)
                        tile = previous
                    }
                    return steps.reversed()
                }
                queue.append(next)
            }
        }
        return nil
    }

    /// Path to stand next to `target` (for talking to an NPC or challenging a boss).
    func path(from start: Tile, toNeighborOf target: Tile, abilities: Set<TraversalAbility> = [],
              in state: FieldState? = nil) -> [Tile]? {
        let goals = target.neighbors.filter { canEnter($0, with: abilities, in: state) && doors[$0] == nil }
        return path(from: start, toAnyOf: Set(goals), abilities: abilities, in: state)
    }

    static func map(for region: Region) -> AdventureMap? {
        all.first { $0.regionID == region.id }
    }

    static let all: [AdventureMap] = [haven, caldera, coast, wilds, skyreach, quarry, voltmarsh, spire]

    // MARK: - Maps
    // Legend: T tree/rock · ~ water/lava/void · # fence · H building · . ground · , tall grass · = path · F flowers
    // Doorways and corridors are kept at least two tiles wide so they're easy to walk through.

    /// The inside of a building, entered through `doorway` in region `regionID`. Walking out the
    /// bottom door returns to the region, just outside the building.
    static func interior(_ doorway: Doorway, regionID: Int) -> AdventureMap {
        switch doorway.kind {
        case .inn:
            AdventureMap(
                regionID: regionID,
                theme: .interior,
                layout: [
                    "TTTTTTTTTTTT",
                    "T..........T",
                    "T.####.###.T",
                    "T..........T",
                    "T.==....==.T",
                    "T.==....==.T",
                    "T..........T",
                    "T.F......F.T",
                    "TTTTTTTTTTTT",
                ],
                start: Tile(col: 5, row: 7),
                placements: [:],
                wildSpecies: [],
                exits: [regionID: [Tile(col: 5, row: 8), Tile(col: 6, row: 8)]],
                stations: [Tile(col: 6, row: 2): .inn, Tile(col: 10, row: 6): .hotSpring]
            )
        case .market:
            AdventureMap(
                regionID: regionID,
                theme: .interior,
                layout: [
                    "TTTTTTTTTTTT",
                    "T..........T",
                    "T.####.###.T",
                    "T..........T",
                    "T.#......#.T",
                    "T.#..==..#.T",
                    "T....==....T",
                    "T.F......F.T",
                    "TTTTTTTTTTTT",
                ],
                start: Tile(col: 5, row: 7),
                placements: [:],
                wildSpecies: [],
                exits: [regionID: [Tile(col: 5, row: 8), Tile(col: 6, row: 8)]],
                stations: [Tile(col: 6, row: 2): .market]
            )
        }
    }

    /// The tile just outside a door, where the keeper appears when leaving the building.
    static func outside(_ door: Tile) -> Tile { door.moved(.down) }

    /// Objective-style IDs for the Arena Hall's hosts. Each opens one kind of match.
    enum ArenaHost: String, CaseIterable {
        case practice = "arena-practice"
        case raid = "arena-raid"
        case online = "arena-online"
    }

    /// The Arena Hall, entered from the Arena tab. Not a story region (ID 0, not in `all`): the arena
    /// building (`building_arena`, 3×3 art centered on a 4×3 footprint) at the top, a fenced sand ring in the middle where the practice rival waits, the raid and online
    /// hosts on either side, and a hot spring and market near the door. The exit at the bottom leaves.
    static let arena = AdventureMap(
        regionID: 0,
        theme: .quarry,
        layout: [
            "TTTTTTTTTTTTTTTTTTTT",
            "T.......HHHH.......T",
            "T.......HHHH.......T",
            "T.......HHHH.......T",
            "T..................T",
            "T.#######==#######.T",
            "T.#==============#.T",
            "T.#==============#.T",
            "T.#==============#.T",
            "T.#######==#######.T",
            "T..................T",
            "T..F............F..T",
            "T..................T",
            "T........==........T",
            "T........==........T",
            "TTTTTTTTTTTTTTTTTTTT",
        ],
        start: Tile(col: 9, row: 13),
        placements: [
            ArenaHost.practice.rawValue: Tile(col: 9, row: 7),
            ArenaHost.raid.rawValue: Tile(col: 4, row: 11),
            ArenaHost.online.rawValue: Tile(col: 15, row: 11),
        ],
        wildSpecies: [],
        exits: [0: [Tile(col: 9, row: 15), Tile(col: 10, row: 15)]],
        stations: [Tile(col: 3, row: 13): .hotSpring, Tile(col: 16, row: 13): .market],
        buildingArt: "building_arena"
    )

    /// Beast Haven: an orchard (tall grass) top-left, Maren's barn top-right,
    /// a pond, and the fenced training yard where the possessed dummy waits.
    static let haven = AdventureMap(
        regionID: 1,
        theme: .meadow,
        layout: [
            "TTTTTTTTTTTTTTTTTTTT",
            "T,,T,,,T.....HHHHH.T",
            "T,,,,T,,.....HHHHH.T",
            "T,T,,,,T.....HHHHH.T",
            "T,,,,T,,..F.....=..T",
            "TT,,,,,,=========..T",
            "T.......=.......F..T",
            "T..F....=..........T",
            "T~~~....=...#######T",
            "T~~~~...=...#.....#T",
            "T~~~~...=====.....#T",
            "T.~~....=.........#T",
            "T.......=...#######T",
            "T..F....=......F...T",
            "T.......=..........T",
            "TTTTTTTTTTTTTTTTTTTT",
        ],
        start: Tile(col: 8, row: 14),
        placements: [
            "ch1-pip": Tile(col: 13, row: 4),
            "ch1-boss": Tile(col: 16, row: 10),
        ],
        wildSpecies: ["pebblit", "sproutle", "glimmet"],
        exits: [2: [Tile(col: 19, row: 6), Tile(col: 19, row: 7)]],
        stations: [Tile(col: 12, row: 2): .stable, Tile(col: 10, row: 6): .feedingTrough, Tile(col: 5, row: 10): .hotSpring,
                   Tile(col: 14, row: 13): .trainingPost, Tile(col: 5, row: 13): .market],
        treasures: [
            Treasure(id: "t1-orchard", tile: Tile(col: 1, row: 1), loot: Loot(items: [.berry: 3], coins: 30)),
            Treasure(id: "t1-pond", tile: Tile(col: 2, row: 9), loot: Loot(items: [.potion: 2, .remedy: 1], shards: 1), requires: .swim),
        ],
        doors: [Tile(col: 15, row: 3): Doorway(kind: .inn, name: "Maren's Barn")],
        // Verdant (tutorial): brambles seal the training yard until the bloom by the pond is stepped on.
        features: ElementFeatures(brambles: [Tile(col: 12, row: 10), Tile(col: 12, row: 11)],
                                  blooms: [Tile(col: 3, row: 7)], bramblePuzzleID: "p1-brambles"),
        glyph: ElementGlyph(id: "g1-haven", tile: Tile(col: 14, row: 9), speciesID: "charbug", level: 1)
    )

    /// Emberfall Caldera: a glassblowers' village at the foot of the volcano, ember fields
    /// on either side of a lava river, and the crater where the feral Magmaw rages.
    static let caldera = AdventureMap(
        regionID: 2,
        theme: .volcano,
        layout: [
            "TTTTTTTTTTTTTTTTTTTT",
            "TTTTTT~~~~~~~~TTTTTT",
            "TTTT~~~......~~~TTTT",
            "TTT~~....==....~~TTT",
            "TT~~.....==.....~~TT",
            "T,,,,....==....,,,,T",
            "T,,,,,...==...,,,,,T",
            "T~~~~~~..==..~~~~~~T",
            "T,,,,....==....,,,,T",
            "T,,,,....==....,,,,T",
            "THHH.....==.....HHHT",
            "THHH..F..==..F..HHHT",
            "T........==........T",
            "T..HHH...==...HHH..T",
            "T........==........T",
            "TTTTTTTTTTTTTTTTTTTT",
        ],
        start: Tile(col: 9, row: 14),
        placements: [
            "ch2-brasa": Tile(col: 5, row: 12),
            "ch2-boss": Tile(col: 9, row: 2),
        ],
        wildSpecies: ["cindrop", "pebblit"],
        exits: [1: [Tile(col: 9, row: 15), Tile(col: 10, row: 15)],
                3: [Tile(col: 19, row: 12), Tile(col: 19, row: 13)]],
        treasures: [
            Treasure(id: "t2-lava", tile: Tile(col: 1, row: 7), loot: Loot(items: [.gutsTonic: 2, .latticeCandy: 1], shards: 1), requires: .fly),
        ],
        doors: [Tile(col: 2, row: 11): Doorway(kind: .inn, name: "Cinder Inn"),
                Tile(col: 17, row: 11): Doorway(kind: .market, name: "Glassblowers' Market")],
        // Ember: a line of geysers across the only gap in the lava river. They erupt in a rolling wave.
        features: ElementFeatures(geysers: Dictionary(uniqueKeysWithValues: (7...12).map {
            (Tile(col: $0, row: 7), Double($0 - 7) / 6)
        })),
        glyph: ElementGlyph(id: "g2-caldera", tile: Tile(col: 5, row: 3), speciesID: "shellbe", level: 2)
    )

    /// Tidewhisper Coast: fishing huts, dune grass, and a long pier out over the grey sea.
    static let coast = AdventureMap(
        regionID: 3,
        theme: .coast,
        layout: [
            "TTTTTTTTTTTTTTTTTTTT",
            "T~~~~~~~~~~~~~~~~~~T",
            "T~~~~~~~~==~~~~..~~T",
            "T~~~~~~~~==~~~~.~~~T",
            "T~~~~~~~~==~~~~.~~~T",
            "T~~~,,,..==..,,,~~~T",
            "T~,,,,.......,,,,,~T",
            "T,,,,..........,,,,T",
            "T.....T....T.......T",
            "T..................T",
            "T..HHH....=====....T",
            "T..HHH....=..HHH...T",
            "T..F......=..HHH...T",
            "T.........=........T",
            "T.....F...=....F...T",
            "TTTTTTTTTTTTTTTTTTTT",
        ],
        start: Tile(col: 10, row: 14),
        placements: [
            "ch3-nell": Tile(col: 6, row: 12),
            "ch3-kade": Tile(col: 11, row: 5),
            "ch3-boss": Tile(col: 9, row: 2),
        ],
        wildSpecies: ["ripplet", "glimmet"],
        exits: [2: [Tile(col: 9, row: 15), Tile(col: 10, row: 15)],
                4: [Tile(col: 19, row: 12), Tile(col: 19, row: 13)]],
        treasures: [
            Treasure(id: "t3-sea", tile: Tile(col: 4, row: 3), loot: Loot(items: [.potion: 2, .bondTreat: 1], coins: 80), requires: .swim),
        ],
        doors: [Tile(col: 4, row: 11): Doorway(kind: .inn, name: "Fisher's Rest"),
                Tile(col: 14, row: 12): Doorway(kind: .market, name: "Sea-Glass Shop")],
        // Tide: a sandbar out to a little island. It floods at high tide and washes non-swimmers back.
        features: ElementFeatures(tideFlats: [Tile(col: 15, row: 3), Tile(col: 15, row: 4)]),
        glyph: ElementGlyph(id: "g3-coast", tile: Tile(col: 16, row: 2), speciesID: "zaplet", level: 6)
    )

    /// Greenmantle Wilds: a labyrinth of ancient trees around an overgrown Lattice node.
    static let wilds = AdventureMap(
        regionID: 4,
        theme: .forest,
        layout: [
            "TTTTTTTTTTTTTTTTTTTT",
            "T,,,,TT......TT,,,,T",
            "T,,,,TT......TT,,,,T",
            "T,,..TT..HH..TT..,,T",
            "T....TT..HH..TT....T",
            "T..TT.T......TTTT..T",
            "T..TTTTTT==TTTTTT..T",
            "T........==........T",
            "TTTTTT,,,==,,,TTTTTT",
            "T,,,,,,,,==,,,,,,,,T",
            "T,,TTTTTT==TTTTTT,,T",
            "T,,T.....==.....T,,T",
            "T..T..F..==..F..T..T",
            "T........==........T",
            "T........==........T",
            "TTTTTTTTTTTTTTTTTTTT",
        ],
        start: Tile(col: 9, row: 14),
        placements: [
            "ch4-ivy": Tile(col: 4, row: 13),
            "ch4-boss": Tile(col: 9, row: 5),
        ],
        wildSpecies: ["sproutle", "shadeling"],
        exits: [3: [Tile(col: 9, row: 15), Tile(col: 10, row: 15)],
                5: [Tile(col: 19, row: 12), Tile(col: 19, row: 13)]],
        stations: [Tile(col: 14, row: 13): .campfire],
        treasures: [
            Treasure(id: "t4-hollow", tile: Tile(col: 5, row: 5), loot: Loot(items: [.starCandy: 1, .remedy: 2], shards: 1), requires: .teleport),
        ],
        // Verdant: the Thorn Labyrinth. Brambles seal the node until both corner blooms are lit.
        features: ElementFeatures(brambles: [Tile(col: 9, row: 6), Tile(col: 10, row: 6)],
                                  blooms: [Tile(col: 1, row: 1), Tile(col: 18, row: 1)], bramblePuzzleID: "p4-brambles"),
        glyph: ElementGlyph(id: "g4-wilds", tile: Tile(col: 7, row: 1), speciesID: "galeharrier", level: 10)
    )

    /// Skyreach Peaks: snowy ledges around a bottomless chasm, climbing to Vey's airship dock.
    static let skyreach = AdventureMap(
        regionID: 5,
        theme: .peaks,
        layout: [
            "TTTTTTTTTTTTTTTTTTTT",
            "T~~~~HHHHHHHH~~~..~T",
            "T~~~~HHHHHHHH~~~..~T",
            "T~~~~....==..~~~~~~T",
            "T~~~~,,..==..,,~~~~T",
            "TTT,,,,..==..,,,,TTT",
            "TT,,,,TTTTTTTT,,,,TT",
            "T,,,..TT~~~~TT..,,,T",
            "T.....TT~..~TT.....T",
            "T..TTTTT~~~~TTTTT..T",
            "T..T~~~~~~~~~~~~T..T",
            "T..T~~~~~~~~~~~~T..T",
            "T..TTTTTTTTTTTTTT..T",
            "T........==........T",
            "T....HH..==..F.....T",
            "TTTTTTTTTTTTTTTTTTTT",
        ],
        start: Tile(col: 9, row: 14),
        placements: [
            "ch5-wren": Tile(col: 6, row: 13),
            "ch5-boss": Tile(col: 9, row: 3),
        ],
        wildSpecies: ["fluffwing", "sparkit"],
        exits: [4: [Tile(col: 9, row: 15), Tile(col: 10, row: 15)],
                6: [Tile(col: 19, row: 12), Tile(col: 19, row: 13)]],
        stations: [Tile(col: 14, row: 13): .campfire],
        treasures: [
            Treasure(id: "t5-nest", tile: Tile(col: 1, row: 1), loot: Loot(items: [.potion: 2, .calmTea: 2], coins: 120), requires: .fly),
            Treasure(id: "t5-ledge", tile: Tile(col: 9, row: 8), loot: Loot(items: [.fullElixir: 1], shards: 2), requires: .teleport),
        ],
        // Gale: an updraft over the chasm carries you up to a sky island; a downdraft brings you back.
        features: ElementFeatures(gusts: [
            Tile(col: 15, row: 4): .up, Tile(col: 15, row: 3): .up, Tile(col: 15, row: 2): .right,
            Tile(col: 16, row: 3): .down, Tile(col: 16, row: 4): .down,
        ]),
        glyph: ElementGlyph(id: "g5-skyreach", tile: Tile(col: 17, row: 1), speciesID: "blazefang", level: 14)
    )

    /// Gravel Hollow: a Syndicate quarry with flooded pits, rubble fields and holding cells.
    static let quarry = AdventureMap(
        regionID: 6,
        theme: .quarry,
        layout: [
            "TTTTTTTTTTTTTTTTTTTT",
            "TTTTTTTT....TTTTTTTT",
            "T,,,,,TT....TT,,,,,T",
            "T,,,,,........,,,,,T",
            "T,,TTTTT....TTTTT,,T",
            "T..T~~~~....~~~~T..T",
            "T..T~~~~....~~~~T..T",
            "T..TTTTT....TTTTT..T",
            "T..................T",
            "T..HHHHH....HHHHH..T",
            "T..H.H.H....H.H.H..T",
            "T..HHHHH...........T",
            "T,,,,,,,....,,,,,,,T",
            "T,,,,,,,....,,,,,,,T",
            "T.........==.......T",
            "TTTTTTTTTTTTTTTTTTTT",
        ],
        start: Tile(col: 10, row: 14),
        placements: [
            "ch6-rook": Tile(col: 8, row: 13),
            "ch6-kade": Tile(col: 13, row: 10),
            "ch6-boss": Tile(col: 9, row: 2),
        ],
        wildSpecies: ["pebblit", "cindrop"],
        exits: [5: [Tile(col: 10, row: 15), Tile(col: 11, row: 15)],
                7: [Tile(col: 19, row: 12), Tile(col: 19, row: 13)]],
        stations: [Tile(col: 14, row: 14): .campfire],
        treasures: [
            Treasure(id: "t6-pit", tile: Tile(col: 14, row: 6), loot: Loot(items: [.latticeCandy: 2], coins: 150), requires: .swim),
            Treasure(id: "t6-cell", tile: Tile(col: 4, row: 10), loot: Loot(items: [.fullElixir: 1, .gutsTonic: 1], shards: 2), requires: .teleport),
        ],
        // Terra: push the boulder away from the open cell to reach the glyph. Boulders fill water too.
        features: ElementFeatures(boulders: [Tile(col: 15, row: 11), Tile(col: 6, row: 12), Tile(col: 13, row: 3)]),
        glyph: ElementGlyph(id: "g6-quarry", tile: Tile(col: 15, row: 10), speciesID: "glaciaray", level: 18)
    )

    /// Voltmarsh: crackling reed beds and bog pools winding up to the Null Spire's gate.
    static let voltmarsh = AdventureMap(
        regionID: 7,
        theme: .marsh,
        layout: [
            "TTTTTTTTTTTTTTTTTTTT",
            "TTTTTTTHH..HHTTTTTTT",
            "T~~~~~~HH..HH~~~~~~T",
            "T~~,,,,,....,,,,,~~T",
            "T~,,,~~~....~~~,,,~T",
            "T,,,~~~T....T~~~,,,T",
            "T,,~~T,,,..,,,T~~,,T",
            "T..~~,,,~~~~,,,~~..T",
            "T..,,,,~~~~~~,,,,..T",
            "T...,,,,,..,,,,,...T",
            "T~~~....T..T....~~~T",
            "T~~~~...........~~~T",
            "T.....F...........FT",
            "T..HH.....==.......T",
            "T.........==.......T",
            "TTTTTTTTTTTTTTTTTTTT",
        ],
        start: Tile(col: 10, row: 14),
        placements: [
            "ch7-kade": Tile(col: 5, row: 12),
            "ch7-boss": Tile(col: 9, row: 2),
        ],
        wildSpecies: ["sparkit", "ripplet"],
        exits: [6: [Tile(col: 10, row: 15), Tile(col: 11, row: 15)],
                8: [Tile(col: 19, row: 12), Tile(col: 19, row: 13)]],
        stations: [Tile(col: 14, row: 13): .campfire],
        treasures: [
            Treasure(id: "t7-bog", tile: Tile(col: 9, row: 7), loot: Loot(items: [.potion: 3, .remedy: 2], shards: 2), requires: .swim),
        ],
        doors: [Tile(col: 3, row: 13): Doorway(kind: .market, name: "Stormwatch Post")],
        // Volt: a lightning fence across the whole marsh, live in a wave that rolls from west to east,
        // plus two arcs guarding the glyph.
        features: ElementFeatures(arcs: Dictionary(uniqueKeysWithValues: (1...18).map {
            (Tile(col: $0, row: 9), Double($0) / 18)
        } + [(Tile(col: 17, row: 5), 0.0), (Tile(col: 18, row: 6), 0.5)])),
        glyph: ElementGlyph(id: "g7-voltmarsh", tile: Tile(col: 18, row: 5), speciesID: "crystalback", level: 24)
    )

    /// The Null Spire: a tower of silent glyphs floating over the void, crowned by Oblivyrn.
    static let spire = AdventureMap(
        regionID: 8,
        theme: .spire,
        layout: [
            "TTTTTTTTTTTTTTTTTTTT",
            "TTTTTTT......TTTTTTT",
            "TTTTTT........TTTTTT",
            "TTTTT~~......~~TTTTT",
            "TTTT~~~..==..~~~TTTT",
            "TTT~~,,..==..,,~~TTT",
            "TT~~,,,TT~~TT,,,~~TT",
            "T~~,,,,TT~~TT,,,,~~T",
            "T~,,,,,TT~~TT,,,,,~T",
            "T~..,,,..~~..,,,..~T",
            "T~~.....~~~~.....~~T",
            "TT~~....~~~~....~~TT",
            "TTT~~..........~~TTT",
            "TTTT~....==....~TTTT",
            "TTTT.....==.....TTTT",
            "TTTTTTTTTTTTTTTTTTTT",
        ],
        start: Tile(col: 9, row: 14),
        placements: [
            "ch8-maren": Tile(col: 7, row: 3),
            "ch8-kade": Tile(col: 12, row: 3),
            "ch8-boss": Tile(col: 9, row: 1),
        ],
        wildSpecies: ["shadeling", "glimmet"],
        exits: [7: [Tile(col: 9, row: 15), Tile(col: 10, row: 15)]],
        stations: [Tile(col: 13, row: 14): .campfire],
        treasures: [
            Treasure(id: "t8-void", tile: Tile(col: 9, row: 7), loot: Loot(items: [.fullElixir: 2, .starCandy: 1], shards: 3), requires: .fly),
        ],
        // Umbra: the Spire is dark. Only a little light surrounds you (more with a Lumen beast).
        features: ElementFeatures(isDark: true),
        glyph: ElementGlyph(id: "g8-spire", tile: Tile(col: 2, row: 9), speciesID: "starmane", level: 31)
    )
}
