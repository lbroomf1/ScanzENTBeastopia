//
//  BeastGenerator.swift
//  Beastopia
//

import CryptoKit
import Foundation

/// Deterministic random number generator (SplitMix64).
/// Used anywhere two devices must agree on the outcome, such as code summoning and multiplayer battles.
struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform integer in `0..<upperBound`. Implemented by hand so results never
    /// depend on standard-library implementation details across OS versions.
    mutating func int(_ upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(next() % UInt64(upperBound))
    }

    /// Uniform double in `0..<1`.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

/// Turns any scanned QR code or barcode into a beast, the same way the classic
/// ranch games summoned monsters from discs. The same code always yields the same beast.
enum BeastGenerator {
    /// SHA-256 digest of a normalized code payload.
    static func digest(of code: String) -> [UInt8] {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return Array(SHA256.hash(data: Data(normalized.utf8)))
    }

    /// A one-way fingerprint of a code, safe to persist without storing the raw payload.
    static func fingerprint(of code: String) -> String {
        digest(of: code).map { String(format: "%02x", $0) }.joined()
    }

    static func generate(fromCode code: String) -> Beast {
        let bytes = digest(of: code)

        let rarity: Rarity = switch bytes[8] {
        case 252...: .mythic
        case 236...: .epic
        case 200...: .rare
        case 140...: .uncommon
        default: .common
        }

        let species: Species
        if rarity == .mythic {
            let pool = SpeciesDatabase.mythicPool
            species = pool[Int(bytes[9]) % pool.count]
        } else {
            // Element first, then a rookie family within it. The element roll matches the
            // original one-rookie-per-element table, so older codes keep their element.
            let element = Element.allCases[Int(bytes[9]) % Element.allCases.count]
            let family = SpeciesDatabase.rookiePool.filter { $0.element == element }
            let pool = family.isEmpty ? SpeciesDatabase.rookiePool : family
            species = pool[Int(bytes[19]) % pool.count]
        }
        return beast(species: species, rarity: rarity, bytes: bytes,
                     originTag: "#" + bytes[0..<4].map { String(format: "%02X", $0) }.joined())
    }

    /// The beast promised by a YouTube episode's code: always the episode's species and rarity,
    /// with trait, hue and stat variance still drawn from the code so it feels like a real summon.
    static func generate(episode: Episode) -> Beast {
        let species = episode.species ?? SpeciesDatabase.rookiePool[0]
        var beast = beast(species: species, rarity: episode.rarity,
                          bytes: digest(of: EpisodeCatalog.canonical(episode.code)),
                          originTag: episode.originTag)
        beast.isPrismatic = false
        return beast
    }

    private static func beast(species: Species, rarity: Rarity, bytes: [UInt8], originTag: String) -> Beast {
        let trait = Trait.allCases[Int(bytes[10]) % Trait.allCases.count]

        var stats = species.base
        for (index, kind) in StatKind.allCases.enumerated() {
            // Each stat varies by ±15% based on the code, then scales with rarity.
            let variance = 0.85 + Double(bytes[13 + index]) / 255.0 * 0.3
            stats[kind] = Int((Double(species.base[kind]) * variance * rarity.statBoost).rounded())
        }

        return Beast(
            speciesID: species.id,
            nickname: "",
            stats: stats,
            trait: trait,
            rarity: rarity,
            hue: Double(bytes[11]) / 255.0 * 60.0 - 30.0,
            isPrismatic: bytes[12] == 0,
            originTag: originTag
        )
    }

    /// The beast sealed in a region's Element Glyph: a Rare of the glyph's species, with stats
    /// scaled to its level like story opponents so it's ready to face the region's boss.
    static func generate(glyph: ElementGlyph) -> Beast {
        var beast = opponent(seed: "glyph-\(glyph.id)", speciesID: glyph.speciesID, level: glyph.level)
        beast.rarity = .rare
        beast.isPrismatic = false
        beast.originTag = elementGlyphTag
        return beast
    }

    /// The origin tag on beasts from Element Glyphs.
    static let elementGlyphTag = "Element Glyph"

    /// Creates a non-player beast (story opponents, raid bosses) from a seed phrase.
    static func opponent(seed: String, speciesID: String? = nil, level: Int) -> Beast {
        var beast = generate(fromCode: seed)
        if let speciesID, let species = SpeciesDatabase.species(speciesID) {
            beast.speciesID = species.id
        }
        // Scale the species' stat shape to a total appropriate for the level, so a
        // level 6 adult is a fair fight for a level 6 rookie rather than a wall.
        let level = min(max(level, 1), 99)
        let base = beast.species.base
        let factor = Double(260 + 25 * level) / Double(base.total)
        for kind in StatKind.allCases {
            beast.stats[kind] = max(5, Int(Double(base[kind]) * factor))
        }
        beast.level = level
        return beast
    }
}
