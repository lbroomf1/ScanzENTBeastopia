//
//  MapTests.swift
//  BeastopiaTests
//

import Testing
@testable import Beastopia

@Suite("Adventure maps")
struct MapTests {
    static let allMaps = AdventureMap.all + [AdventureMap.arena]

    @Test("Every map is a full rectangle", arguments: allMaps.indices)
    func rectangular(index: Int) {
        let map = Self.allMaps[index]
        #expect(map.width == 20, "Region \(map.regionID) should be 20 tiles wide")
        #expect(map.terrain.allSatisfy { $0.count == map.width }, "Region \(map.regionID) has a ragged row")
    }

    @Test("Every NPC, boss and station can be reached from the start, once the region's puzzle is solved",
          arguments: allMaps.indices)
    func reachable(index: Int) {
        let map = Self.allMaps[index]
        let everything: Set<TraversalAbility> = Set(TraversalAbility.allCases)
        let solved = map.solvedState
        for (id, tile) in map.placements {
            #expect(map.path(from: map.start, toNeighborOf: tile, abilities: everything, in: solved) != nil,
                    "\(id) in region \(map.regionID) is unreachable")
        }
        for tile in map.stations.keys {
            #expect(map.path(from: map.start, toNeighborOf: tile, abilities: everything, in: solved) != nil,
                    "Station at \(tile) in region \(map.regionID) is unreachable")
        }
    }

    @Test("The Arena Hall's hosts and exit are reachable on foot")
    func arenaOnFoot() {
        let arena = AdventureMap.arena
        for host in AdventureMap.ArenaHost.allCases {
            let tile = arena.placements[host.rawValue]
            #expect(tile != nil, "\(host) has no spot in the hall")
            if let tile {
                #expect(arena.path(from: arena.start, toNeighborOf: tile) != nil, "\(host) can't be reached on foot")
            }
        }
        #expect(arena.path(from: arena.start, toAnyOf: Set(arena.exits.keys)) != nil)
    }

    @Test("Walled-in chests really need Blink", arguments: AdventureMap.all.indices)
    func blinkChestsAreWalledIn(index: Int) {
        let map = AdventureMap.all[index]
        let walking = Set(TraversalAbility.allCases).subtracting([.teleport])
        for chest in map.treasures where chest.requires == .teleport {
            #expect(map.path(from: map.start, toAnyOf: [chest.tile], abilities: walking) == nil,
                    "\(chest.id) can be reached without Blink")
        }
    }
}
