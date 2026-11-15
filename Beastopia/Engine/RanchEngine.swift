//
//  RanchEngine.swift
//  Beastopia
//

import Foundation

/// Raising rules: Beast Training, resting, feeding, leveling, evolution and Beast Fusion.
enum RanchEngine {
    struct TrainingResult {
        let stat: StatKind
        let gain: Int
        let levelsGained: Int
        let message: String
    }

    private static func freshRNG() -> SeededRandom {
        SeededRandom(seed: UInt64.random(in: .min ... .max))
    }

    // MARK: - Training

    static func train(_ beast: inout Beast, stat: StatKind) -> TrainingResult {
        var rng = freshRNG()
        let favored = beast.trait.favoredStat == stat ? 1.5 : 1.0
        let fatiguePenalty = max(0.2, 1.0 - Double(beast.fatigue) / 120.0)
        let raw = Double(3 + rng.int(5)) * favored * fatiguePenalty
        let gain = max(1, Int(raw.rounded()))

        beast.stats[stat] += gain
        beast.fatigue = min(100, beast.fatigue + fatigueCost(for: beast.trait))
        beast.bond = min(100, beast.bond + 1)
        let levels = addXP(&beast, amount: 20)

        let message: String
        if beast.fatigue >= 80 {
            message = "\(beast.displayName) is exhausted. Let it rest!"
        } else if gain >= 6 {
            message = "Great session! \(stat.shortName) +\(gain)"
        } else {
            message = "\(stat.shortName) +\(gain)"
        }
        return TrainingResult(stat: stat, gain: gain, levelsGained: levels, message: message)
    }

    private static func fatigueCost(for trait: Trait) -> Int {
        switch trait {
        case .wild: 18
        case .hardy: 8
        default: 12
        }
    }

    static func rest(_ beast: inout Beast) {
        beast.fatigue = max(0, beast.fatigue - 40)
        beast.bond = min(100, beast.bond + 1)
    }

    static func feed(_ beast: inout Beast) {
        beast.fatigue = max(0, beast.fatigue - 10)
        beast.bond = min(100, beast.bond + (beast.trait == .gentle ? 8 : 5))
    }

    // MARK: - Haven upgrades

    /// Coin-bought boosts from Haven facilities, so keepers can catch up to tougher chapter bosses.
    enum Upgrade: CaseIterable, Identifiable {
        case hotSprings, royalFeast, growthElixir

        var id: Self { self }

        var name: String {
            switch self {
            case .hotSprings: "Hot Springs"
            case .royalFeast: "Royal Feast"
            case .growthElixir: "Growth Elixir"
            }
        }

        var symbol: String {
            switch self {
            case .hotSprings: "drop.circle.fill"
            case .royalFeast: "fork.knife.circle.fill"
            case .growthElixir: "flask.fill"
            }
        }

        var summary: String {
            switch self {
            case .hotSprings: "Clears all fatigue."
            case .royalFeast: "Bond +15, fatigue −20."
            case .growthElixir: "Instantly gain a level."
            }
        }

        func cost(for beast: Beast) -> Int {
            switch self {
            case .hotSprings: 30
            case .royalFeast: 50
            case .growthElixir: 20 + beast.level * 10
            }
        }

        func isUseful(for beast: Beast) -> Bool {
            switch self {
            case .hotSprings: beast.fatigue > 0
            case .royalFeast: beast.bond < 100 || beast.fatigue > 0
            case .growthElixir: beast.level < 99
            }
        }
    }

    /// Applies an upgrade and returns the number of levels gained.
    @discardableResult
    static func apply(_ upgrade: Upgrade, to beast: inout Beast) -> Int {
        switch upgrade {
        case .hotSprings:
            beast.fatigue = 0
            beast.bond = min(100, beast.bond + 2)
            return 0
        case .royalFeast:
            beast.bond = min(100, beast.bond + 15)
            beast.fatigue = max(0, beast.fatigue - 20)
            return 0
        case .growthElixir:
            return addXP(&beast, amount: beast.xpToNextLevel - beast.xp)
        }
    }

    // MARK: - Duplicates

    /// Coins a beast fetches when sold to the Lattice Market.
    static func sellValue(of beast: Beast) -> Int {
        let rarityBonus = (beast.rarity.rawValue + 1) * 15
        let stageBonus = beast.species.stage.rawValue * 20
        return 10 + beast.level * 4 + rarityBonus + stageBonus + (beast.isPrismatic ? 200 : 0)
    }

    /// Experience a beast passes on when absorbed into another.
    static func absorbXP(of beast: Beast) -> Int {
        40 + beast.level * 25
    }

    /// The rookie a species ultimately evolves from (walks evolution paths backwards).
    static func lineRoot(of speciesID: String) -> String {
        var current = speciesID
        var visited: Set<String> = [current]
        while let parent = SpeciesDatabase.all.first(where: { $0.evolutions.contains { $0.targetID == current } }),
              visited.insert(parent.id).inserted {
            current = parent.id
        }
        return current
    }

    /// Duplicates: two beasts from the same evolution line (e.g. a rookie and its adult form).
    static func isSameLine(_ a: Beast, _ b: Beast) -> Bool {
        a.speciesID == b.speciesID || lineRoot(of: a.speciesID) == lineRoot(of: b.speciesID)
    }

    /// Absorbing a duplicate of the same line is far stronger: the survivor also inherits
    /// a slice of the donor's stats and bond, rewarding players who keep scanning their favourites.
    /// Returns the number of levels gained.
    @discardableResult
    static func absorb(_ donor: Beast, into beast: inout Beast) -> Int {
        let sameLine = isSameLine(donor, beast)
        if sameLine {
            for kind in StatKind.allCases {
                beast.stats[kind] = min(Stats.cap, beast.stats[kind] + donor.stats[kind] / 10)
            }
            beast.bond = min(100, beast.bond + 5)
        }
        beast.isPrismatic = beast.isPrismatic || donor.isPrismatic
        return addXP(&beast, amount: absorbXP(of: donor) * (sameLine ? 2 : 1))
    }

    // MARK: - Leveling

    /// Adds experience and returns the number of levels gained.
    @discardableResult
    static func addXP(_ beast: inout Beast, amount: Int) -> Int {
        var rng = freshRNG()
        var levels = 0
        beast.xp += amount
        while beast.xp >= beast.xpToNextLevel, beast.level < 99 {
            beast.xp -= beast.xpToNextLevel
            applyLevelUp(to: &beast, using: &rng)
            beast.level += 1
            levels += 1
        }
        return levels
    }

    /// Stat growth for one level, proportional to the species' base stats.
    static func applyLevelUp(to beast: inout Beast, using rng: inout SeededRandom) {
        let base = beast.species.base
        for kind in StatKind.allCases {
            beast.stats[kind] += max(1, base[kind] / 25) + rng.int(3)
        }
    }

    // MARK: - Evolution

    /// What evolving from one species into another changes, matching what `evolve(_:)` applies.
    struct EvolutionChanges {
        let from: Species
        let to: Species
        /// Stats that rise, and by how much (stats never drop when evolving).
        let statGains: [(stat: StatKind, amount: Int)]
        let newMoves: [Move]
        /// Moves the old form had that the new one doesn't (its old signature, and elemental move if the element changes).
        let replacedMoves: [Move]
        let newAbilities: [TraversalAbility]
        let lostAbilities: [TraversalAbility]
        static let bondGain = 10

        var elementChanged: Bool { from.element != to.element }
    }

    static func evolutionChanges(from: Species, to: Species) -> EvolutionChanges {
        let gains = StatKind.allCases.compactMap { kind -> (stat: StatKind, amount: Int)? in
            let amount = to.base[kind] - from.base[kind]
            return amount > 0 ? (kind, amount) : nil
        }
        let oldMoves = Set(from.moves.map(\.name)), newMoves = Set(to.moves.map(\.name))
        return EvolutionChanges(
            from: from, to: to, statGains: gains,
            newMoves: to.moves.filter { !oldMoves.contains($0.name) },
            replacedMoves: from.moves.filter { !newMoves.contains($0.name) },
            newAbilities: TraversalAbility.allCases.filter { to.abilities.contains($0) && !from.abilities.contains($0) },
            lostAbilities: TraversalAbility.allCases.filter { from.abilities.contains($0) && !to.abilities.contains($0) })
    }

    /// The species this one evolves from, with the path that leads here.
    static func preEvolution(of species: Species) -> (species: Species, path: EvolutionPath)? {
        for parent in SpeciesDatabase.all {
            if let path = parent.evolutions.first(where: { $0.targetID == species.id }) { return (parent, path) }
        }
        return nil
    }

    /// Plain-language evolution requirements, e.g. "Lv 10, INT as highest stat, Bond 40".
    static func requirementText(_ path: EvolutionPath) -> String {
        var parts = ["Lv \(path.minLevel)"]
        if let stat = path.dominantStat { parts.append("\(stat.shortName) as highest stat") }
        if path.minBond > 0 { parts.append("Bond \(path.minBond)") }
        return parts.joined(separator: ", ")
    }

    /// Evolves the beast if it meets a path's requirements. Returns the new species.
    @discardableResult
    static func evolve(_ beast: inout Beast) -> Species? {
        guard let target = beast.availableEvolution else { return nil }
        let oldBase = beast.species.base
        for kind in StatKind.allCases {
            // Keep everything the keeper trained, then add the jump between stages.
            beast.stats[kind] += max(0, target.base[kind] - oldBase[kind])
        }
        beast.speciesID = target.id
        beast.bond = min(100, beast.bond + EvolutionChanges.bondGain)
        return target
    }

    // MARK: - Beast Fusion

    static let fusionMinimumLevel = 15

    /// Secret recipe: two parents whose elements match a Mythic's element pair.
    static func mythicRecipe(_ a: Beast, _ b: Beast) -> Species? {
        guard a.level >= fusionMinimumLevel, b.level >= fusionMinimumLevel else { return nil }
        let parents: Set<Element> = [a.species.element, b.species.element]
        return SpeciesDatabase.mythicPool.first { [$0.element, $0.hiddenElement] == parents }
    }

    /// Fusing two beasts of the same evolution line refines them instead of starting over:
    /// the child keeps the more evolved form and higher level, the best of each stat plus a
    /// bonus from the other parent, and a better shot at a rarity upgrade.
    static func isBloodlineFusion(_ a: Beast, _ b: Beast) -> Bool {
        mythicRecipe(a, b) == nil && isSameLine(a, b)
    }

    private static func bloodlineFuse(_ a: Beast, _ b: Beast, using rng: inout SeededRandom) -> Beast {
        let lead = (a.species.stage, a.level) >= (b.species.stage, b.level) ? a : b
        let other = lead.id == a.id ? b : a

        var stats = lead.stats
        for kind in StatKind.allCases {
            let best = max(a.stats[kind], b.stats[kind])
            let worst = min(a.stats[kind], b.stats[kind])
            stats[kind] = min(Stats.cap, best + worst / 5)
        }

        var rarity = max(a.rarity, b.rarity)
        if rng.int(2) == 0, let next = Rarity(rawValue: min(rarity.rawValue + 1, Rarity.epic.rawValue)) {
            rarity = next
        }

        var child = Beast(
            speciesID: lead.speciesID,
            nickname: lead.nickname,
            stats: stats,
            trait: lead.trait,
            rarity: max(rarity, lead.rarity),
            hue: lead.hue,
            isPrismatic: a.isPrismatic || b.isPrismatic || rng.int(64) == 0,
            bond: max(a.bond, b.bond),
            originTag: lead.originTag
        )
        child.level = max(a.level, b.level)
        child.xp = lead.xp
        child.wins = a.wins + b.wins
        child.losses = a.losses + b.losses
        // The weaker parent's experience still counts for something.
        addXP(&child, amount: absorbXP(of: other))
        return child
    }

    /// The rookie that two beasts of different lines fuse into: the original rookie of the
    /// stronger parent's element.
    static func freshFusionSpecies(_ a: Beast, _ b: Beast) -> Species {
        let stronger = a.stats.total >= b.stats.total ? a : b
        return SpeciesDatabase.rookiePool.first { $0.element == stronger.species.element }
            ?? SpeciesDatabase.rookiePool[0]
    }

    /// Fuses two beasts. Different lines make a new rookie that inherits a portion of both
    /// parents' stats; the same line makes a refined version of that beast.
    static func fuse(_ a: Beast, _ b: Beast) -> Beast {
        var rng = freshRNG()
        if isBloodlineFusion(a, b) { return bloodlineFuse(a, b, using: &rng) }
        let childSpecies = mythicRecipe(a, b) ?? freshFusionSpecies(a, b)

        var stats = childSpecies.base
        for kind in StatKind.allCases {
            // Inherit 15% of the parents' average, like the classic "combine" lab.
            let inherited = (a.stats[kind] + b.stats[kind]) / 2 * 15 / 100
            stats[kind] += inherited
        }

        var rarity = max(a.rarity, b.rarity)
        if childSpecies.stage == .mythic {
            rarity = .mythic
        } else if rng.int(4) == 0, let next = Rarity(rawValue: min(rarity.rawValue + 1, Rarity.epic.rawValue)) {
            rarity = next
        }

        return Beast(
            speciesID: childSpecies.id,
            nickname: "",
            stats: stats,
            trait: rng.int(2) == 0 ? a.trait : b.trait,
            rarity: rarity,
            hue: (a.hue + b.hue) / 2,
            isPrismatic: a.isPrismatic || b.isPrismatic || rng.int(128) == 0,
            bond: 20,
            originTag: "Fusion"
        )
    }
}
