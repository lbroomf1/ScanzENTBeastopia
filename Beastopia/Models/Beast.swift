//
//  Beast.swift
//  Beastopia
//

import Foundation

/// An individual beast owned by the player and raised in their Beast Haven.
struct Beast: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var speciesID: String
    var nickname: String
    var level: Int = 1
    var xp: Int = 0
    var stats: Stats
    var trait: Trait
    var rarity: Rarity
    /// Hue rotation (in degrees) that gives every scanned beast its own coloring.
    var hue: Double
    /// One-in-256 shimmering variant.
    var isPrismatic: Bool
    /// Bond with the keeper, 0...100. Reveals the hidden element at 30 and unlocks apex evolutions.
    var bond: Int = 10
    /// Fatigue, 0...100. High fatigue reduces training gains.
    var fatigue: Int = 0
    var wins: Int = 0
    var losses: Int = 0
    /// Short, non-reversible fingerprint of the code the beast was found in.
    var originTag: String
    var discoveredAt = Date()

    var species: Species {
        SpeciesDatabase.species(speciesID) ?? SpeciesDatabase.all[0]
    }

    var displayName: String { nickname.isEmpty ? species.name : nickname }

    var isHiddenElementRevealed: Bool { bond >= 30 }

    var xpToNextLevel: Int { level * 50 }

    var maxHP: Int { 40 + stats.life * 2 + level * 4 }

    /// The first evolution path whose requirements are currently satisfied.
    var availableEvolution: Species? {
        for path in species.evolutions {
            guard level >= path.minLevel, bond >= path.minBond else { continue }
            if let stat = path.dominantStat, stats.dominant != stat { continue }
            if let target = SpeciesDatabase.species(path.targetID) { return target }
        }
        return nil
    }
}
