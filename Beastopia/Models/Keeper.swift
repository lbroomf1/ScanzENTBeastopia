//
//  Keeper.swift
//  Beastopia
//

import SwiftUI

/// The player's own character: a Glyphkeeper with a name, a look, a class, a rank and gear.
///
/// Keepers don't fight directly. Their hero stats boost the beasts they send into battle
/// (see `boosted(_:)`), and their class and rank add perks outside battle.
struct Keeper: Codable, Hashable, Sendable {
    static let maxNameLength = 16
    static let maxRank = 30
    /// No beast stat can be boosted by more than this percentage.
    static let maxBonusPercent = 30
    /// Coins charged to change class after creation.
    static let classChangeCost = 300

    var name: String
    var keeperClass: KeeperClass
    var color: KeeperColor
    var style: KeeperStyle
    var rank = 1
    var xp = 0
    var ownedGear: Set<GearKind> = []
    /// At most one piece per slot.
    var equippedGear: Set<GearKind> = []

    var xpToNextRank: Int { rank * 100 }

    /// Adds Keeper XP. Returns the ranks gained.
    mutating func addXP(_ amount: Int) -> Int {
        guard rank < Self.maxRank else { return 0 }
        var ranks = 0
        xp += amount
        while xp >= xpToNextRank, rank < Self.maxRank {
            xp -= xpToNextRank
            rank += 1
            ranks += 1
        }
        if rank == Self.maxRank { xp = 0 }
        return ranks
    }

    // MARK: - Hero stats

    /// The class's growth plus equipped gear.
    func value(of stat: HeroStat) -> Int {
        keeperClass.base(stat) + (rank - 1) * keeperClass.growthTenths(stat) / 10
            + equippedGear.reduce(0) { $0 + $1.bonus(stat) }
    }

    /// Percentage boost to a beast stat in battle: one percent per point of the linked hero stat.
    func bonusPercent(for stat: StatKind) -> Int {
        min(Self.maxBonusPercent, value(of: HeroStat.linked(to: stat)))
    }

    /// A copy of `beast` with this keeper's bonuses applied, for sending into battle.
    /// The battle engine never sees the keeper, so online peers simply receive the boosted beast.
    func boosted(_ beast: Beast) -> Beast {
        var copy = beast
        for stat in StatKind.allCases {
            copy.stats[stat] = beast.stats[stat] * (100 + bonusPercent(for: stat)) / 100
        }
        return copy
    }

    // MARK: - Gear

    func equipped(in slot: GearSlot) -> GearKind? {
        equippedGear.first { $0.slot == slot }
    }

    mutating func equip(_ gear: GearKind) {
        guard ownedGear.contains(gear) else { return }
        equippedGear = equippedGear.filter { $0.slot != gear.slot }
        equippedGear.insert(gear)
    }

    mutating func unequip(_ slot: GearSlot) {
        equippedGear = equippedGear.filter { $0.slot != slot }
    }

    // MARK: - Rank perks

    /// Extra Haven slots: +5 at ranks 5, 15 and 25.
    var bonusHavenSlots: Int {
        [5, 15, 25].filter { rank >= $0 }.count * 5
    }

    /// Market coin prices drop 10% at rank 10.
    var marketDiscountPercent: Int { rank >= 10 ? 10 : 0 }

    /// Beasts earn 10% more battle XP from rank 20.
    var rankXPBonusPercent: Int { rank >= 20 ? 10 : 0 }

    struct Milestone: Identifiable {
        let rank: Int
        let perk: String
        var id: Int { rank }
    }

    static let milestones: [Milestone] = [
        Milestone(rank: 5, perk: "+5 Haven slots"),
        Milestone(rank: 10, perk: "10% off Market coin prices"),
        Milestone(rank: 15, perk: "+5 Haven slots"),
        Milestone(rank: 20, perk: "Beasts earn +10% battle XP"),
        Milestone(rank: 25, perk: "+5 Haven slots"),
    ]
}

/// The keeper's own attributes. Each one boosts two beast stats in battle.
enum HeroStat: String, CaseIterable, Identifiable, Sendable {
    case might, wits, agility

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .might: "figure.strengthtraining.traditional"
        case .wits: "brain.head.profile"
        case .agility: "wind"
        }
    }

    var boostedStats: [StatKind] {
        switch self {
        case .might: [.power, .life]
        case .wits: [.intellect, .skill]
        case .agility: [.speed, .defense]
        }
    }

    static func linked(to stat: StatKind) -> HeroStat {
        allCases.first { $0.boostedStats.contains(stat) } ?? .might
    }
}

/// Raw values are persisted, so never rename them.
enum KeeperClass: String, Codable, CaseIterable, Identifiable, Sendable {
    case tamer, scholar, ranger

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tamer: "Tamer"
        case .scholar: "Scholar"
        case .ranger: "Ranger"
        }
    }

    var symbol: String {
        switch self {
        case .tamer: "pawprint.fill"
        case .scholar: "book.closed.fill"
        case .ranger: "binoculars.fill"
        }
    }

    var summary: String {
        switch self {
        case .tamer: "Raised among beasts. Hits hard and builds bonds fast."
        case .scholar: "Studies the Lattice's glyphs. Sharp minds, quick learners."
        case .ranger: "Roams the wilds. Swift, sturdy and always finds a few extra coins."
        }
    }

    /// The hero stat this class grows fastest.
    var focus: HeroStat {
        switch self {
        case .tamer: .might
        case .scholar: .wits
        case .ranger: .agility
        }
    }

    var perk: String {
        switch self {
        case .tamer: "Beasts gain double bond from battles"
        case .scholar: "Beasts earn +25% battle XP"
        case .ranger: "+25% coins from battles"
        }
    }

    func base(_ stat: HeroStat) -> Int { stat == focus ? 6 : 2 }

    /// Growth per rank, in tenths of a point.
    func growthTenths(_ stat: HeroStat) -> Int { stat == focus ? 6 : 2 }
}

/// Raw values are persisted, so never rename them.
enum KeeperColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case indigo, crimson, amber, forest, ocean, violet, rose, slate

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .indigo: .indigo
        case .crimson: .red
        case .amber: .orange
        case .forest: .green
        case .ocean: .teal
        case .violet: .purple
        case .rose: .pink
        case .slate: .gray
        }
    }
}

/// How the keeper's figure looks on the map. Raw values are persisted, so never rename them.
enum KeeperStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case wanderer, hiker, sprinter

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .wanderer: "figure.walk"
        case .hiker: "figure.hiking"
        case .sprinter: "figure.run"
        }
    }
}

enum GearSlot: String, CaseIterable, Identifiable, Sendable {
    case charm, gloves, cloak

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

/// Equipment that raises hero stats. Bought at the Haven Market.
/// Raw values are persisted, so never rename them.
enum GearKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case latticeCharm, sagesPendant, glyphSigil
    case leatherGloves, ironbarkGauntlets, emberforgedGrips
    case travelersCloak, galeweaveCloak, nullwardMantle

    var id: String { rawValue }

    var name: String {
        switch self {
        case .latticeCharm: "Lattice Charm"
        case .sagesPendant: "Sage's Pendant"
        case .glyphSigil: "Glyph Sigil"
        case .leatherGloves: "Leather Gloves"
        case .ironbarkGauntlets: "Ironbark Gauntlets"
        case .emberforgedGrips: "Emberforged Grips"
        case .travelersCloak: "Traveler's Cloak"
        case .galeweaveCloak: "Galeweave Cloak"
        case .nullwardMantle: "Nullward Mantle"
        }
    }

    var slot: GearSlot {
        switch self {
        case .latticeCharm, .sagesPendant, .glyphSigil: .charm
        case .leatherGloves, .ironbarkGauntlets, .emberforgedGrips: .gloves
        case .travelersCloak, .galeweaveCloak, .nullwardMantle: .cloak
        }
    }

    var symbol: String {
        switch slot {
        case .charm: "seal.fill"
        case .gloves: "hand.raised.fill"
        case .cloak: "tshirt.fill"
        }
    }

    func bonus(_ stat: HeroStat) -> Int {
        switch (self, stat) {
        case (.latticeCharm, .wits), (.leatherGloves, .might), (.travelersCloak, .agility): 2
        case (.sagesPendant, .wits), (.ironbarkGauntlets, .might), (.galeweaveCloak, .agility): 4
        case (.glyphSigil, .wits), (.glyphSigil, .might),
             (.emberforgedGrips, .might), (.emberforgedGrips, .agility),
             (.nullwardMantle, .agility), (.nullwardMantle, .wits): 3
        default: 0
        }
    }

    var summary: String {
        HeroStat.allCases.filter { bonus($0) > 0 }
            .map { "+\(bonus($0)) \($0.displayName)" }
            .joined(separator: ", ")
    }

    var price: Price {
        switch self {
        case .latticeCharm, .leatherGloves, .travelersCloak: .coins(300)
        case .sagesPendant, .ironbarkGauntlets, .galeweaveCloak: .coins(900)
        case .glyphSigil, .emberforgedGrips, .nullwardMantle: .shards(6)
        }
    }

    var requiredRank: Int {
        switch self {
        case .latticeCharm, .leatherGloves, .travelersCloak: 1
        case .sagesPendant, .ironbarkGauntlets, .galeweaveCloak: 8
        case .glyphSigil, .emberforgedGrips, .nullwardMantle: 15
        }
    }
}

extension String {
    /// Swaps the `{keeper}` placeholder in dialogue for the player's name.
    func personalized(for keeper: Keeper?) -> String {
        replacing("{keeper}", with: keeper?.name ?? "Glyphkeeper")
    }
}
