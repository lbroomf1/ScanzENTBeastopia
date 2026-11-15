//
//  Species.swift
//  Beastopia
//

import Foundation

/// Life stage of a beast. Rookies come from scans; later stages are reached by evolution.
enum Stage: Int, Codable, CaseIterable, Comparable, Sendable {
    case rookie = 1, adult, apex, mythic

    static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }

    var displayName: String { String(describing: self).capitalized }
}

enum MoveKind: String, Codable, Sendable {
    case physical, special, guarding, heal
}

/// A battle technique. Moves spend Guts, which regenerate every turn.
struct Move: Codable, Hashable, Identifiable, Sendable {
    var id: String { name }
    let name: String
    let element: Element?
    let kind: MoveKind
    let power: Int
    let accuracy: Int
    let gutsCost: Int

    static let strike = Move(name: "Strike", element: nil, kind: .physical, power: 40, accuracy: 95, gutsCost: 10)
    static let guardUp = Move(name: "Guard", element: nil, kind: .guarding, power: 0, accuracy: 100, gutsCost: 0)

    /// The shared elemental move every beast of an element can use.
    static func elemental(_ element: Element) -> Move {
        let name: String = switch element {
        case .ember: "Flare Burst"
        case .tide: "Riptide"
        case .verdant: "Bramble Lash"
        case .gale: "Cyclone Cut"
        case .terra: "Quake Slam"
        case .volt: "Arc Bolt"
        case .lumen: "Prism Ray"
        case .umbra: "Shade Fang"
        }
        let kind: MoveKind = [.terra, .verdant, .umbra].contains(element) ? .physical : .special
        return Move(name: name, element: element, kind: kind, power: 60, accuracy: 90, gutsCost: 25)
    }
}

/// A requirement that must be met for a beast to evolve into another species.
struct EvolutionPath: Codable, Hashable, Sendable {
    let targetID: String
    let minLevel: Int
    /// If set, this stat must be the beast's highest stat (enables branching evolutions).
    let dominantStat: StatKind?
    let minBond: Int
}

/// A species entry in the Beastdex.
struct Species: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let element: Element
    let hiddenElement: Element
    let stage: Stage
    let base: Stats
    let symbol: String
    let lore: String
    let signature: Move
    let evolutions: [EvolutionPath]

    var moves: [Move] {
        [.strike, .elemental(element), signature, .guardUp]
    }
}

/// The master monster database. IDs are stable and persisted, so never rename them.
enum SpeciesDatabase {
    static let all: [Species] = rookies + adults + apexes + mythics + expansion

    static let byID: [String: Species] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func species(_ id: String) -> Species? { byID[id] }

    static var rookiePool: [Species] { all.filter { $0.stage == .rookie } }
    static var mythicPool: [Species] { all.filter { $0.stage == .mythic } }

    // MARK: - Helpers (shared with SpeciesExpansion.swift)

    static func stats(_ l: Int, _ p: Int, _ i: Int, _ d: Int, _ s: Int, _ k: Int) -> Stats {
        Stats(life: l, power: p, intellect: i, defense: d, speed: s, skill: k)
    }

    static func sig(_ name: String, _ element: Element, _ kind: MoveKind, _ power: Int, _ cost: Int) -> Move {
        Move(name: name, element: element, kind: kind, power: power, accuracy: 85, gutsCost: cost)
    }

    static func evo(_ id: String, level: Int, stat: StatKind? = nil, bond: Int = 0) -> EvolutionPath {
        EvolutionPath(targetID: id, minLevel: level, dominantStat: stat, minBond: bond)
    }

    // MARK: - Rookies (found by scanning)

    private static let rookies: [Species] = [
        Species(id: "cindrop", name: "Cindrop", element: .ember, hiddenElement: .volt, stage: .rookie,
                base: stats(50, 62, 40, 38, 52, 45), symbol: "flame.fill",
                lore: "A living ember that fell from the Caldera's first eruption. It purrs like a crackling hearth.",
                signature: sig("Ember Pounce", .ember, .physical, 55, 20),
                evolutions: [evo("pyrowl", level: 10, stat: .intellect), evo("magmaw", level: 10)]),
        Species(id: "ripplet", name: "Ripplet", element: .tide, hiddenElement: .lumen, stage: .rookie,
                base: stats(58, 40, 55, 45, 44, 48), symbol: "drop.fill",
                lore: "Tide pools on the Whisper Coast hum when a Ripplet is sleeping inside.",
                signature: sig("Bubble Volley", .tide, .special, 50, 18),
                evolutions: [evo("tidecrest", level: 10)]),
        Species(id: "sproutle", name: "Sproutle", element: .verdant, hiddenElement: .terra, stage: .rookie,
                base: stats(62, 45, 42, 55, 35, 41), symbol: "leaf.fill",
                lore: "Plants a seed wherever it naps. Old Haven orchards were all started by Sproutles.",
                signature: sig("Seed Barrage", .verdant, .physical, 50, 18),
                evolutions: [evo("thornback", level: 10)]),
        Species(id: "fluffwing", name: "Fluffwing", element: .gale, hiddenElement: .lumen, stage: .rookie,
                base: stats(44, 42, 48, 36, 66, 54), symbol: "bird.fill",
                lore: "So light it must hold onto pebbles during storms. Loves to ride updrafts.",
                signature: sig("Gust Dive", .gale, .physical, 52, 18),
                evolutions: [evo("zephyrix", level: 10)]),
        Species(id: "pebblit", name: "Pebblit", element: .terra, hiddenElement: .ember, stage: .rookie,
                base: stats(60, 55, 30, 66, 28, 40), symbol: "tortoise.fill",
                lore: "A stubborn shell of river stone. It can sleep for a hundred years without noticing.",
                signature: sig("Rock Roll", .terra, .physical, 55, 20),
                evolutions: [evo("bouldrake", level: 10)]),
        Species(id: "sparkit", name: "Sparkit", element: .volt, hiddenElement: .gale, stage: .rookie,
                base: stats(42, 50, 52, 34, 64, 50), symbol: "hare.fill",
                lore: "Its fur builds a static charge with every hop. Petting one is a shocking experience.",
                signature: sig("Static Hop", .volt, .special, 52, 18),
                evolutions: [evo("joltusk", level: 10)]),
        Species(id: "glimmet", name: "Glimmet", element: .lumen, hiddenElement: .tide, stage: .rookie,
                base: stats(48, 36, 64, 42, 48, 56), symbol: "sparkles",
                lore: "A mote of starlight given curiosity. It follows travelers and lights their path.",
                signature: sig("Twinkle Beam", .lumen, .special, 52, 18),
                evolutions: [evo("radiantail", level: 10)]),
        Species(id: "shadeling", name: "Shadeling", element: .umbra, hiddenElement: .verdant, stage: .rookie,
                base: stats(46, 54, 50, 40, 56, 48), symbol: "cat.fill",
                lore: "Hides in the shadow of its keeper. Shy at first, fiercely loyal once trusted.",
                signature: sig("Night Swipe", .umbra, .physical, 52, 18),
                evolutions: [evo("nocturne", level: 10)]),
    ]

    // MARK: - Adults

    private static let adults: [Species] = [
        Species(id: "pyrowl", name: "Pyrowl", element: .ember, hiddenElement: .gale, stage: .adult,
                base: stats(90, 95, 120, 70, 100, 95), symbol: "bird.fill",
                lore: "A wise owl wreathed in fire. Raised by keepers who favored study over strength.",
                signature: sig("Scorch Wing", .ember, .special, 75, 30),
                evolutions: [evo("infernox", level: 25, bond: 50)]),
        Species(id: "magmaw", name: "Magmaw", element: .ember, hiddenElement: .terra, stage: .adult,
                base: stats(110, 130, 60, 95, 70, 80), symbol: "lizard.fill",
                lore: "A molten lizard whose bite can melt iron. Born from a Cindrop trained for raw power.",
                signature: sig("Lava Jaw", .ember, .physical, 80, 32),
                evolutions: [evo("infernox", level: 25, bond: 50)]),
        Species(id: "tidecrest", name: "Tidecrest", element: .tide, hiddenElement: .lumen, stage: .adult,
                base: stats(115, 80, 110, 90, 80, 90), symbol: "fish.fill",
                lore: "Rides the crest of every wave. Sailors say its song calms storms.",
                signature: sig("Crashing Wave", .tide, .special, 75, 30),
                evolutions: [evo("leviathorn", level: 25, bond: 50)]),
        Species(id: "thornback", name: "Thornback", element: .verdant, hiddenElement: .terra, stage: .adult,
                base: stats(125, 95, 70, 120, 60, 75), symbol: "ladybug.fill",
                lore: "Its shell is a living garden of thorns. Predators learn quickly to leave it be.",
                signature: sig("Thorn Volley", .verdant, .physical, 75, 30),
                evolutions: [evo("elderoot", level: 25, bond: 50)]),
        Species(id: "zephyrix", name: "Zephyrix", element: .gale, hiddenElement: .volt, stage: .adult,
                base: stats(85, 90, 95, 70, 135, 110), symbol: "wind",
                lore: "A blur on the horizon. Zephyrix races the wind itself, and usually wins.",
                signature: sig("Slipstream", .gale, .physical, 75, 30),
                evolutions: [evo("tempestrix", level: 25, bond: 50)]),
        Species(id: "bouldrake", name: "Bouldrake", element: .terra, hiddenElement: .ember, stage: .adult,
                base: stats(130, 115, 55, 140, 50, 70), symbol: "mountain.2.fill",
                lore: "A drake of living granite. Mountain villages carve its likeness above their gates.",
                signature: sig("Landslide", .terra, .physical, 80, 32),
                evolutions: [evo("gravolith", level: 25, bond: 50)]),
        Species(id: "joltusk", name: "Joltusk", element: .volt, hiddenElement: .terra, stage: .adult,
                base: stats(95, 115, 90, 80, 115, 95), symbol: "bolt.fill",
                lore: "Twin tusks crackle with lightning. A single charge can power a village for a night.",
                signature: sig("Tusk Thunder", .volt, .physical, 78, 30),
                evolutions: [evo("thundervex", level: 25, bond: 50)]),
        Species(id: "radiantail", name: "Radiantail", element: .lumen, hiddenElement: .gale, stage: .adult,
                base: stats(95, 70, 135, 85, 95, 110), symbol: "sun.max.fill",
                lore: "Its nine tails shimmer like dawn. Said to guide lost beasts back to their keepers.",
                signature: sig("Dawnflare", .lumen, .special, 78, 30),
                evolutions: [evo("solaryx", level: 25, bond: 50)]),
        Species(id: "nocturne", name: "Nocturne", element: .umbra, hiddenElement: .volt, stage: .adult,
                base: stats(90, 120, 100, 80, 115, 95), symbol: "moon.fill",
                lore: "A panther of midnight. Its eyes are the only thing you see before it strikes.",
                signature: sig("Eclipse Claw", .umbra, .physical, 78, 30),
                evolutions: [evo("eclipsar", level: 25, bond: 50)]),
    ]

    // MARK: - Apex forms

    private static let apexes: [Species] = [
        Species(id: "infernox", name: "Infernox", element: .ember, hiddenElement: .umbra, stage: .apex,
                base: stats(180, 210, 160, 150, 150, 160), symbol: "flame.circle.fill",
                lore: "A titan of flame whose footsteps leave glass behind. Legends say it lit the first sun.",
                signature: sig("Cataclysm", .ember, .special, 100, 45), evolutions: []),
        Species(id: "leviathorn", name: "Leviathorn", element: .tide, hiddenElement: .umbra, stage: .apex,
                base: stats(220, 160, 180, 170, 120, 150), symbol: "water.waves",
                lore: "Ruler of the deep trenches. Its horn is said to control the tides.",
                signature: sig("Abyssal Surge", .tide, .special, 100, 45), evolutions: []),
        Species(id: "elderoot", name: "Elderoot", element: .verdant, hiddenElement: .lumen, stage: .apex,
                base: stats(240, 170, 130, 210, 90, 130), symbol: "tree.fill",
                lore: "An ancient forest given a heartbeat. Whole ecosystems live on its back.",
                signature: sig("World Tree Crash", .verdant, .physical, 100, 45), evolutions: []),
        Species(id: "tempestrix", name: "Tempestrix", element: .gale, hiddenElement: .volt, stage: .apex,
                base: stats(160, 170, 160, 130, 230, 190), symbol: "tornado",
                lore: "A living storm front. When it spreads its wings the sky turns green.",
                signature: sig("Eye of the Storm", .gale, .special, 100, 45), evolutions: []),
        Species(id: "gravolith", name: "Gravolith", element: .terra, hiddenElement: .umbra, stage: .apex,
                base: stats(240, 210, 100, 240, 80, 120), symbol: "mountain.2.circle.fill",
                lore: "So dense it bends light. Gravolith is a walking mountain range.",
                signature: sig("Tectonic Fall", .terra, .physical, 105, 48), evolutions: []),
        Species(id: "thundervex", name: "Thundervex", element: .volt, hiddenElement: .gale, stage: .apex,
                base: stats(170, 200, 170, 140, 200, 170), symbol: "bolt.circle.fill",
                lore: "Its roar is thunder; its gaze is lightning. Storm chasers revere it.",
                signature: sig("Heaven's Arc", .volt, .special, 100, 45), evolutions: []),
        Species(id: "solaryx", name: "Solaryx", element: .lumen, hiddenElement: .ember, stage: .apex,
                base: stats(180, 150, 230, 160, 160, 170), symbol: "sun.max.circle.fill",
                lore: "A phoenix of pure daylight. Where Solaryx flies, the Null cannot follow.",
                signature: sig("Solar Crown", .lumen, .special, 100, 45), evolutions: []),
        Species(id: "eclipsar", name: "Eclipsar", element: .umbra, hiddenElement: .lumen, stage: .apex,
                base: stats(170, 210, 190, 150, 190, 150), symbol: "moon.circle.fill",
                lore: "The shadow cast by a dying star. Eclipsar remembers every beast the Null erased.",
                signature: sig("Total Eclipse", .umbra, .special, 100, 45), evolutions: []),
    ]

    // MARK: - Mythic Beasts (ultra-rare scans and Beast Fusion only)

    private static let mythics: [Species] = [
        Species(id: "aurorion", name: "Aurorion", element: .lumen, hiddenElement: .gale, stage: .mythic,
                base: stats(150, 130, 170, 130, 150, 160), symbol: "rainbow",
                lore: "Guardian of the Codex Lattice. Its mane holds every color ever scanned.",
                signature: sig("Aurora Veil", .lumen, .special, 95, 40), evolutions: []),
        Species(id: "chronodrake", name: "Chronodrake", element: .terra, hiddenElement: .umbra, stage: .mythic,
                base: stats(170, 160, 150, 160, 110, 130), symbol: "hourglass",
                lore: "It sleeps between seconds. Those who meet it often lose an afternoon.",
                signature: sig("Time Fracture", .terra, .special, 95, 40), evolutions: []),
        Species(id: "maelstryx", name: "Maelstryx", element: .tide, hiddenElement: .volt, stage: .mythic,
                base: stats(160, 150, 160, 130, 150, 150), symbol: "hurricane",
                lore: "A serpent of storm and sea. Its coils are the reason sailors fear the horizon.",
                signature: sig("Maelstrom", .tide, .special, 95, 40), evolutions: []),
        Species(id: "oblivyrn", name: "Oblivyrn", element: .umbra, hiddenElement: .umbra, stage: .mythic,
                base: stats(200, 190, 180, 170, 150, 160), symbol: "circle.dotted",
                lore: "The Null Wyrm. It devours codes and leaves only silence behind.",
                signature: sig("Null Devour", .umbra, .special, 110, 50), evolutions: []),
    ]
}
