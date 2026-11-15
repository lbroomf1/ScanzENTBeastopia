//
//  ElementWorldTests.swift
//  BeastopiaTests
//

import Foundation
import Testing
@testable import Beastopia

@Suite("Buildings, element mechanics and Element Glyphs")
struct ElementWorldTests {
    static let regions = AdventureMap.all

    // MARK: - Buildings

    @Test("Every door is a building's front wall with open ground outside", arguments: regions.indices)
    func doors(index: Int) {
        let map = Self.regions[index]
        for (door, doorway) in map.doors {
            #expect(map.terrain(at: door) == .building, "\(doorway.name)'s door isn't on a building")
            #expect(map.terrain(at: door.moved(.down)) != .building, "\(doorway.name)'s door isn't on the front wall")
            #expect(map.isWalkable(AdventureMap.outside(door)), "Nothing to stand on outside \(doorway.name)")
            #expect(map.path(from: map.start, toAnyOf: [door], abilities: Set(TraversalAbility.allCases),
                             in: map.solvedState) != nil, "\(doorway.name) can't be reached")
        }
    }

    @Test("Towns have an Inn or a Market to walk into")
    func townsHaveBuildings() {
        let kinds = Self.regions.flatMap { $0.doors.values.map(\.kind) }
        #expect(kinds.contains(.inn))
        #expect(kinds.contains(.market))
    }

    @Test("Inside every building, its counters and the way out are reachable")
    func interiors() {
        for kind in [Doorway.Kind.inn, .market] {
            let inside = AdventureMap.interior(Doorway(kind: kind, name: "Test"), regionID: 2)
            #expect(inside.stations.values.contains(kind == .inn ? .inn : .market))
            for tile in inside.stations.keys {
                #expect(inside.path(from: inside.start, toNeighborOf: tile) != nil)
            }
            #expect(inside.path(from: inside.start, toAnyOf: Set(inside.exits.keys)) != nil)
            #expect(Set(inside.exits.values) == [2], "Leaving goes back to the same region")
        }
    }

    @Test("A night at the Inn rests every beast for 20 coins")
    func inn() {
        let store = TestSupport.makeStore(coins: 100)
        for code in ["INN-A", "INN-B"] { _ = store.claim(code: code) }
        #expect(!store.stayAtInn(), "Nobody is tired yet")
        for beast in store.beasts { store.recordBattle(beastID: beast.id, won: false, opponentLevel: 1) }
        let coins = store.coins
        #expect(store.stayAtInn())
        #expect(store.coins == coins - GameStore.innCost)
        #expect(store.beasts.allSatisfy { $0.fatigue == 0 })
    }

    // MARK: - Element Glyphs

    @Test("Every story region's glyph holds a beast strong against its boss", arguments: WorldMap.regions.indices)
    func glyphCountersBoss(index: Int) throws {
        let region = WorldMap.regions[index]
        let map = try #require(AdventureMap.map(for: region))
        let glyph = try #require(map.glyph, "\(region.chapter.region) has no Element Glyph")
        let species = try TestSupport.species(glyph.speciesID)
        let boss = try TestSupport.species(region.chapter.opponentSpeciesID)
        let multiplier = species.element.multiplier(against: boss.element, hidden: boss.hiddenElement)
        // The best any element can do. (Lumen and Umbra are strong against each other, so against
        // Oblivyrn even Lumen only comes out slightly ahead.)
        let best = Element.allCases.map { $0.multiplier(against: boss.element, hidden: boss.hiddenElement) }.max() ?? 1
        #expect(multiplier > 1, "\(species.name) isn't strong against \(boss.name) (×\(multiplier))")
        if region.id == 1 {
            // The Haven glyph gives Ember rather than Gale on purpose: every Gale beast lends Fly,
            // which would let new keepers fly over the Caldera's lava and skip its geysers.
            #expect(multiplier > 1.3)
        } else {
            #expect(multiplier >= best - 0.0001, "A better element than \(species.element) exists against \(boss.name)")
        }
        #expect(glyph.level < region.chapter.opponentLevel)
        #expect(map.path(from: map.start, toAnyOf: [glyph.tile], abilities: Set(TraversalAbility.allCases),
                         in: map.solvedState) != nil, "\(region.chapter.region)'s glyph can't be reached")
    }

    @Test("Glyph IDs are unique and don't clash with chests")
    func glyphIDs() {
        let ids = Self.regions.compactMap { $0.glyph?.id } + Self.regions.flatMap { $0.treasures.map(\.id) }
            + Self.regions.compactMap { $0.features.bramblePuzzleID }
        #expect(Set(ids).count == ids.count)
    }

    @Test("A glyph awakens its beast once, at its level, and the claim is saved")
    func claimGlyph() throws {
        let storage = InMemorySaveStorage()
        let store = TestSupport.makeStore(storage: storage)
        let glyph = try #require(AdventureMap.caldera.glyph)
        guard case .awakened(let beast) = store.claim(glyph) else {
            Issue.record("The first touch should awaken the glyph's beast")
            return
        }
        #expect(beast.speciesID == glyph.speciesID)
        #expect(beast.level == glyph.level)
        #expect(beast.rarity == .rare)
        guard case .alreadyClaimed = store.claim(glyph) else {
            Issue.record("A glyph only gives its beast once")
            return
        }
        #expect(TestSupport.makeStore(storage: storage).hasClaimed(glyph))
    }

    // MARK: - Mechanics

    @Test("Brambles block the Wilds boss until both blooms are lit, and the blooms can be reached")
    func brambles() throws {
        let map = AdventureMap.wilds
        let boss = try #require(map.placements["ch4-boss"])
        let all = Set(TraversalAbility.allCases).subtracting([.teleport])
        #expect(map.path(from: map.start, toNeighborOf: boss, abilities: all) == nil)
        for bloom in map.features.blooms {
            #expect(map.path(from: map.start, toAnyOf: [bloom]) != nil, "Bloom at \(bloom) is out of reach")
        }
        #expect(map.path(from: map.start, toNeighborOf: boss, in: map.solvedState) != nil)
    }

    @Test("The Skyreach updraft carries you to the sky island and the downdraft brings you back, on foot")
    func gusts() throws {
        let map = AdventureMap.skyreach
        let glyph = try #require(map.glyph)
        let there = try #require(map.path(from: map.start, toAnyOf: [glyph.tile]))
        #expect(there.contains(Tile(col: 15, row: 3)), "The route should ride the updraft")
        #expect(map.path(from: glyph.tile, toAnyOf: [map.start]) != nil, "You'd be stranded on the island")
        // Walking against the wind doesn't work: from the bottom of the updraft you can only go up.
        #expect(map.moves(from: Tile(col: 15, row: 4), abilities: [], in: map.initialState) == [Tile(col: 15, row: 3)])
    }

    @Test("The Coast sandbar is dry at low tide and floods at high tide unless a beast can swim")
    func tide() throws {
        let map = AdventureMap.coast
        let glyph = try #require(map.glyph)
        var high = map.initialState
        high.highTide = true
        #expect(map.path(from: map.start, toAnyOf: [glyph.tile]) != nil)
        #expect(map.path(from: map.start, toAnyOf: [glyph.tile], in: high) == nil)
        #expect(map.path(from: map.start, toAnyOf: [glyph.tile], abilities: [.swim], in: high) != nil)
    }

    @Test("Pushing the Quarry boulder aside opens the glyph's cell")
    func boulders() throws {
        let map = AdventureMap.quarry
        let glyph = try #require(map.glyph)
        let walking = Set(TraversalAbility.allCases).subtracting([.teleport])
        #expect(map.path(from: map.start, toAnyOf: [glyph.tile], abilities: walking) == nil)
        var pushed = map.initialState
        pushed.boulders.remove(Tile(col: 15, row: 11))
        pushed.boulders.insert(Tile(col: 16, row: 11))
        #expect(map.path(from: map.start, toAnyOf: [glyph.tile], abilities: walking, in: pushed) != nil)
    }

    @Test("A boulder pushed into water fills it so you can walk across")
    func filledWater() {
        let map = AdventureMap.quarry
        let pit = Tile(col: 12, row: 5)
        #expect(!map.canEnter(pit, with: []))
        var state = map.initialState
        state.filled.insert(pit)
        #expect(map.canEnter(pit, with: [], in: state))
    }

    @Test("Geysers and arcs always leave a gap to cross through")
    func hazardsHaveGaps() {
        for features in [AdventureMap.caldera.features, AdventureMap.voltmarsh.features] {
            for step in 0..<300 {
                let time = Double(step) * 0.05
                let quietGeysers = features.geysers.values.filter { !FieldTiming.isErupting(phase: $0, at: time) }
                let darkArcs = features.arcs.values.filter { !FieldTiming.isArcLive(phase: $0, at: time) }
                #expect(features.geysers.isEmpty || !quietGeysers.isEmpty, "Every geyser erupts at \(time)s")
                #expect(features.arcs.isEmpty || !darkArcs.isEmpty, "Every arc is live at \(time)s")
            }
        }
    }

    @Test("Every story region has an element mechanic and a briefing", arguments: WorldMap.regions.indices)
    func briefings(index: Int) {
        let region = WorldMap.regions[index]
        let briefing = region.briefing
        #expect(!briefing.mechanicTitle.isEmpty)
        #expect(!briefing.counters.isEmpty)
        #expect(!(AdventureMap.map(for: region)?.features.isEmpty ?? true))
    }

    @Test("Solved brambles stay solved after reloading")
    func solvedPuzzleSaved() {
        let storage = InMemorySaveStorage()
        TestSupport.makeStore(storage: storage).markSolved("p4-brambles")
        #expect(TestSupport.makeStore(storage: storage).isSolved("p4-brambles"))
    }
}

@Suite("Challenge Cards and nearby play")
struct ChallengeCardTests {
    @Test("A card round-trips through its text and fits on an NTAG215 sticker")
    func roundTrip() throws {
        var beast = TestSupport.beast("tidecrest", level: 23)
        beast.nickname = "Splash"
        let card = ChallengeCard(keeperName: "Kade", beast: beast)
        #expect(card.payload.utf8.count < 400)
        #expect(ChallengeCard.isCard(card.payload))
        let read = try #require(ChallengeCard(payload: card.payload))
        #expect(read == card)
        #expect(read.ghost.speciesID == "tidecrest")
        #expect(read.ghost.level == 23)
        #expect(read.ghost.stats == beast.stats)
        #expect(read.ghost.nickname == "Kade's Splash")
    }

    @Test("Damaged or forged cards are refused or clamped")
    func untrusted() throws {
        #expect(ChallengeCard(payload: "BEASTOPIA-DUEL:not-base64!!") == nil)
        #expect(ChallengeCard(payload: "hello") == nil)
        #expect(!ChallengeCard.isCard("4006381333931"))
        var forged = ChallengeCard(keeperName: "Cheat", beast: TestSupport.beast("pebblit"))
        forged.s = "not-a-species"
        forged.l = 500
        forged.t = [50_000, -3, 1, 1, 1, 1]
        let ghost = try #require(ChallengeCard(payload: forged.payload)).ghost
        #expect(SpeciesDatabase.species(ghost.speciesID) != nil)
        #expect(ghost.level == 99)
        #expect(ghost.stats.life == Stats.cap)
        #expect(ghost.stats.power == 1)
    }

    @Test("Nearby peers agree on who goes first")
    func nearbyOrder() {
        let a: UInt64 = 12_345, b: UInt64 = 98_765
        #expect(MultiplayerManager.isLocalFirst(localNonce: a, remoteNonce: b)
                != MultiplayerManager.isLocalFirst(localNonce: b, remoteNonce: a))
    }
}
