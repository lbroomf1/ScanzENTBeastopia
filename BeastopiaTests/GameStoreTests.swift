//
//  GameStoreTests.swift
//  BeastopiaTests
//

import Foundation
import Testing
@testable import Beastopia

@Suite("Game store and save data")
struct GameStoreTests {
    @Test("A store with empty storage starts a fresh game")
    func freshGame() {
        let store = TestSupport.makeStore()
        #expect(store.beasts.isEmpty)
        #expect(store.coins == 0)
        #expect(store.keeper == nil)
    }

    @Test("Progress saved by one store loads in the next")
    func saveRoundTrip() throws {
        let storage = InMemorySaveStorage()
        let first = TestSupport.makeStore(coins: 500, storage: storage)
        #expect(first.buy(.berry, quantity: 3))
        guard case .discovered(let beast) = first.claim(code: "ROUND-TRIP") else {
            Issue.record("A new code should summon a beast")
            return
        }
        #expect(storage.saveCount > 0)

        let second = TestSupport.makeStore(storage: storage)
        #expect(second.coins == first.coins)
        #expect(second.count(of: .berry) == first.count(of: .berry))
        #expect(second.beasts.map(\.id) == [beast.id])
        #expect(second.discoveredSpecies.contains(beast.speciesID))
    }

    @Test("Meeting a beast reveals it in the Beastdex and is saved")
    func discoverSpecies() {
        let storage = InMemorySaveStorage()
        let store = TestSupport.makeStore(storage: storage)
        store.discover("pyrowl")
        store.discover("not-a-species")
        #expect(store.discoveredSpecies == ["pyrowl"])
        #expect(TestSupport.makeStore(storage: storage).discoveredSpecies.contains("pyrowl"))
    }

    @Test("Corrupt save data is set aside before a fresh game overwrites it")
    func corruptSave() {
        let corrupt = Data("not json".utf8)
        let storage = InMemorySaveStorage(data: corrupt)
        let store = TestSupport.makeStore(storage: storage)
        #expect(store.beasts.isEmpty)
        #expect(storage.setAsideData == [corrupt])

        store.save()
        #expect(storage.setAsideData == [corrupt])
    }

    @Test("A save from a newer build is set aside, not loaded")
    func futureVersionSave() throws {
        let storage = InMemorySaveStorage()
        let store = TestSupport.makeStore(storage: storage)
        _ = store.claim(code: "0123456789")
        let saved = try #require(storage.data)
        var json = try #require(try JSONSerialization.jsonObject(with: saved) as? [String: Any])
        #expect(json["version"] as? Int == 1)
        json["version"] = 99
        let future = try JSONSerialization.data(withJSONObject: json)

        let futureStorage = InMemorySaveStorage(data: future)
        let reloaded = TestSupport.makeStore(storage: futureStorage)
        #expect(reloaded.beasts.isEmpty)
        #expect(futureStorage.setAsideData == [future])
    }

    @Test("The same code can only be claimed once")
    func claimOnce() {
        let store = TestSupport.makeStore()
        guard case .discovered = store.claim(code: "0123456789") else {
            Issue.record("First scan should summon a beast")
            return
        }
        guard case .alreadyClaimed = store.claim(code: "0123456789") else {
            Issue.record("Second scan of the same code should be refused")
            return
        }
        #expect(store.beasts.count == 1)
    }

    @Test("The first beast comes with a starter kit")
    func starterKit() {
        let store = TestSupport.makeStore()
        _ = store.claim(code: "STARTER")
        #expect(store.count(of: .berry) == 3)
        #expect(store.count(of: .remedy) == 1)
    }

    @Test("A chest can only be looted once")
    func treasureOnce() {
        let store = TestSupport.makeStore()
        let chest = Treasure(id: "test-chest", tile: Tile(col: 1, row: 1), loot: Loot(items: [.potion: 2], coins: 30))
        #expect(store.open(chest))
        #expect(!store.open(chest))
        #expect(store.coins == 30)
        #expect(store.count(of: .potion) == 2)
    }

    @Test("Loot drops are repeatable with the same injected seed")
    func seededDrops() throws {
        func run(seed: UInt64) -> (coins: Int, shards: Int, items: [ItemKind: Int]) {
            let store = TestSupport.makeStore(seed: seed)
            _ = store.claim(code: "DROPS")
            let beastID = store.beasts[0].id
            let before = ItemKind.allCases.map(store.count(of:))
            for _ in 0..<20 {
                store.recordBattle(beastID: beastID, won: true, opponentLevel: 5)
            }
            let items = Dictionary(uniqueKeysWithValues: zip(ItemKind.allCases, zip(before, ItemKind.allCases.map(store.count(of:)))
                .map { $1 - $0 }))
            return (store.coins, store.shards, items)
        }
        let a = run(seed: 7), b = run(seed: 7)
        #expect(a.coins == b.coins)
        #expect(a.shards == b.shards)
        #expect(a.items == b.items)
    }

    @Test("Bosses always drop shards and a potion")
    func bossDrops() {
        let store = TestSupport.makeStore()
        _ = store.claim(code: "BOSS")
        let rewards = store.recordBattle(beastID: store.beasts[0].id, won: true, opponentLevel: 20, isBoss: true)
        #expect(rewards.loot.shards == 3)
        #expect(rewards.loot.items[.potion] == 1)
    }

    @Test("Losing still earns experience but no coins")
    func lossRewards() {
        let store = TestSupport.makeStore()
        _ = store.claim(code: "LOSS")
        let rewards = store.recordBattle(beastID: store.beasts[0].id, won: false, opponentLevel: 3)
        #expect(rewards.xp > 0)
        #expect(rewards.loot.isEmpty)
        #expect(store.coins == 0)
    }
}
