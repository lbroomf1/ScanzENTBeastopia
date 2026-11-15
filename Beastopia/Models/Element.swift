//
//  Element.swift
//  Beastopia
//

import SwiftUI

/// The eight elemental affinities of Beastopia. Every beast has a visible
/// primary element and a hidden secondary element that is revealed as bond grows.
enum Element: String, Codable, CaseIterable, Identifiable, Sendable {
    case ember, tide, verdant, gale, terra, volt, lumen, umbra

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .ember: "flame.fill"
        case .tide: "drop.fill"
        case .verdant: "leaf.fill"
        case .gale: "wind"
        case .terra: "mountain.2.fill"
        case .volt: "bolt.fill"
        case .lumen: "sun.max.fill"
        case .umbra: "moon.fill"
        }
    }

    /// Asset catalog name for this element's icon.
    var iconArt: String { "element_\(rawValue)" }

    var color: Color {
        switch self {
        case .ember: .orange
        case .tide: .blue
        case .verdant: .green
        case .gale: .mint
        case .terra: .brown
        case .volt: .yellow
        case .lumen: .pink
        case .umbra: .purple
        }
    }

    /// Elements this element deals bonus damage to.
    var strongAgainst: Set<Element> {
        switch self {
        case .ember: [.verdant, .gale]
        case .tide: [.ember, .terra]
        case .verdant: [.tide, .terra]
        case .gale: [.verdant, .volt]
        case .terra: [.volt, .ember]
        case .volt: [.tide, .gale]
        case .lumen: [.umbra]
        case .umbra: [.lumen]
        }
    }

    /// Damage multiplier when an attack of this element hits a defender.
    /// The defender's hidden element contributes a smaller, secondary modifier.
    func multiplier(against primary: Element, hidden: Element?) -> Double {
        var value = 1.0
        if strongAgainst.contains(primary) { value *= 1.5 }
        if primary.strongAgainst.contains(self) { value *= 0.67 }
        if let hidden {
            if strongAgainst.contains(hidden) { value *= 1.15 }
            if hidden.strongAgainst.contains(self) { value *= 0.9 }
        }
        return value
    }
}

/// The six core stats, an homage to the classic ranch-sim stat block.
struct Stats: Codable, Hashable, Sendable {
    var life: Int
    var power: Int
    var intellect: Int
    var defense: Int
    var speed: Int
    var skill: Int

    static let cap = 999

    var total: Int { life + power + intellect + defense + speed + skill }

    subscript(stat: StatKind) -> Int {
        get {
            switch stat {
            case .life: life
            case .power: power
            case .intellect: intellect
            case .defense: defense
            case .speed: speed
            case .skill: skill
            }
        }
        set {
            let clamped = min(max(newValue, 1), Stats.cap)
            switch stat {
            case .life: life = clamped
            case .power: power = clamped
            case .intellect: intellect = clamped
            case .defense: defense = clamped
            case .speed: speed = clamped
            case .skill: skill = clamped
            }
        }
    }

    /// The stat with the highest value, used for stat-gated evolutions.
    var dominant: StatKind {
        StatKind.allCases.max { self[$0] < self[$1] } ?? .power
    }
}

enum StatKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case life, power, intellect, defense, speed, skill

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .life: "LIF"
        case .power: "POW"
        case .intellect: "INT"
        case .defense: "DEF"
        case .speed: "SPD"
        case .skill: "SKI"
        }
    }

    /// The Beast Training drill that raises this stat.
    var drillName: String {
        switch self {
        case .life: "Endurance Run"
        case .power: "Boulder Push"
        case .intellect: "Rune Study"
        case .defense: "Waterfall Stand"
        case .speed: "Canyon Sprint"
        case .skill: "Target Practice"
        }
    }

    var symbol: String {
        switch self {
        case .life: "heart.fill"
        case .power: "figure.strengthtraining.traditional"
        case .intellect: "brain.head.profile"
        case .defense: "shield.fill"
        case .speed: "hare.fill"
        case .skill: "scope"
        }
    }

    /// Asset catalog name for this stat's icon.
    var iconArt: String { "stat_\(rawValue)" }
}

enum Rarity: Int, Codable, CaseIterable, Comparable, Sendable {
    case common, uncommon, rare, epic, mythic

    static func < (lhs: Rarity, rhs: Rarity) -> Bool { lhs.rawValue < rhs.rawValue }

    var displayName: String {
        switch self {
        case .mythic: "Mythic Beast"
        default: String(describing: self).capitalized
        }
    }

    var color: Color {
        switch self {
        case .common: .gray
        case .uncommon: .green
        case .rare: .blue
        case .epic: .purple
        case .mythic: .orange
        }
    }

    /// Multiplier applied to generated base stats.
    var statBoost: Double {
        switch self {
        case .common: 1.0
        case .uncommon: 1.08
        case .rare: 1.16
        case .epic: 1.25
        case .mythic: 1.4
        }
    }
}

/// Personality traits shape how fast each stat grows during training.
enum Trait: String, Codable, CaseIterable, Sendable {
    case brave, clever, sturdy, swift, precise, hardy, wild, gentle

    var displayName: String { rawValue.capitalized }

    var favoredStat: StatKind {
        switch self {
        case .brave: .power
        case .clever: .intellect
        case .sturdy: .defense
        case .swift: .speed
        case .precise: .skill
        case .hardy: .life
        case .wild: .power
        case .gentle: .life
        }
    }

    var summary: String {
        switch self {
        case .brave: "Charges in head-first. Power grows quickly."
        case .clever: "Solves puzzles for fun. Intellect grows quickly."
        case .sturdy: "Hard to knock over. Defense grows quickly."
        case .swift: "Never sits still. Speed grows quickly."
        case .precise: "Focused and calm. Skill grows quickly."
        case .hardy: "Shrugs off fatigue. Life grows quickly."
        case .wild: "Unpredictable. Power grows quickly, but tires fast."
        case .gentle: "Bonds easily with its keeper."
        }
    }
}
