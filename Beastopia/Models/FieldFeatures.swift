//
//  FieldFeatures.swift
//  Beastopia
//

import Foundation

// MARK: - Buildings

/// The door of a building the keeper can walk into. Walking onto the door tile goes inside.
struct Doorway: Sendable {
    enum Kind: Sendable {
        /// Rest the whole team, and a bath.
        case inn
        /// A shop counter.
        case market
    }

    let kind: Kind
    /// Shown on the title card when the keeper walks in, e.g. "Cinder Inn".
    let name: String
}

// MARK: - Element mechanics

/// The pieces of a region's element puzzle. Each story region uses the mechanic of its element:
/// Ember geysers, Tide flats, Verdant brambles, Gale gusts, Terra boulders, Volt arcs and Umbra darkness.
struct ElementFeatures: Sendable {
    /// Ember: vents that erupt on a cycle. Tile → phase offset (0..<1) so vents erupt in waves.
    var geysers: [Tile: Double] = [:]
    /// Volt: lightning arcs that are live on a cycle. Tile → phase offset (0..<1).
    var arcs: [Tile: Double] = [:]
    /// Gale: currents that carry the keeper one tile in a direction, even over a chasm. They chain.
    var gusts: [Tile: StepDirection] = [:]
    /// Terra: boulders the keeper can push one tile. A boulder pushed into water fills it.
    var boulders: Set<Tile> = []
    /// Verdant: thorns that block the way until every bloom has been stepped on.
    var brambles: Set<Tile> = []
    var blooms: Set<Tile> = []
    /// Stable ID saved once the brambles are open, so they stay open. Never rename.
    var bramblePuzzleID: String?
    /// Tide: sand that's dry at low tide and under water at high tide.
    var tideFlats: Set<Tile> = []
    /// Umbra: the region is dark except for a small light around the keeper.
    var isDark = false

    var isEmpty: Bool {
        geysers.isEmpty && arcs.isEmpty && gusts.isEmpty && boulders.isEmpty && brambles.isEmpty
            && tideFlats.isEmpty && !isDark
    }
}

/// The parts of a region's element puzzle that change while the keeper explores.
nonisolated struct FieldState: Equatable, Sendable {
    var boulders: Set<Tile>
    /// Water tiles filled in by boulders. They can be walked on.
    var filled: Set<Tile> = []
    var litBlooms: Set<Tile> = []
    var bramblesOpen: Bool
    var highTide = false
}

/// Cycle timings for the element hazards, in seconds.
enum FieldTiming {
    static let geyserPeriod = 3.0
    static let geyserActive = 1.1
    static let arcPeriod = 2.0
    static let arcActive = 0.9
    static let tidePeriod = 14.0
    static let highTide = 6.0

    /// Whether a cycle with the given period and phase offset is in its active part at `time`.
    static func isActive(period: Double, active: Double, phase: Double, at time: Double) -> Bool {
        let position = (time / period + phase).truncatingRemainder(dividingBy: 1)
        return (position < 0 ? position + 1 : position) < active / period
    }

    static func isErupting(phase: Double, at time: Double) -> Bool {
        isActive(period: geyserPeriod, active: geyserActive, phase: phase, at: time)
    }

    static func isArcLive(phase: Double, at time: Double) -> Bool {
        isActive(period: arcPeriod, active: arcActive, phase: phase, at: time)
    }

    static func isHighTide(at time: Double) -> Bool {
        isActive(period: tidePeriod, active: highTide, phase: 0.6, at: time)
    }
}

// MARK: - Element Glyphs

/// A glyph stone hidden in each story region. Reaching it (usually by mastering the region's
/// element mechanic) awakens a beast whose element is strong against the region's boss.
struct ElementGlyph: Sendable {
    /// Stable and saved with opened chests, so never rename.
    let id: String
    let tile: Tile
    let speciesID: String
    let level: Int

    var species: Species? { SpeciesDatabase.species(speciesID) }
}
