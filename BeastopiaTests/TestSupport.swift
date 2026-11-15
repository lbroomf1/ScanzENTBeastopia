//
//  TestSupport.swift
//  BeastopiaTests
//

import Foundation
import Testing
@testable import Beastopia

/// Builders for tests. Every store gets in-memory storage and a seeded random source,
/// so tests never touch the real save file and loot rolls are repeatable.
enum TestSupport {
    static func makeStore(storage: InMemorySaveStorage = InMemorySaveStorage(), seed: UInt64 = 42) -> GameStore {
        GameStore(storage: storage, random: SeededRandom(seed: seed))
    }

    /// A store holding `coins` and `shards`, given through loot like the game does.
    static func makeStore(coins: Int, shards: Int = 0, storage: InMemorySaveStorage = InMemorySaveStorage()) -> GameStore {
        let store = makeStore(storage: storage)
        store.add(Loot(coins: coins, shards: shards))
        return store
    }

    static func beast(_ speciesID: String, level: Int = 1, bond: Int = 10) -> Beast {
        var beast = BeastGenerator.generate(fromCode: "test-\(speciesID)")
        beast.speciesID = speciesID
        beast.level = level
        beast.bond = bond
        return beast
    }

    static func species(_ id: String) throws -> Species {
        try #require(SpeciesDatabase.species(id))
    }
}
