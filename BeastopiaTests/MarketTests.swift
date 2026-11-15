//
//  MarketTests.swift
//  BeastopiaTests
//

import Testing
@testable import Beastopia

@Suite("Market purchases")
struct MarketTests {
    @Test("Buying a quantity charges the total and adds that many")
    func buyQuantity() throws {
        let store = TestSupport.makeStore(coins: 1_000)
        guard case .coins(let unit) = store.price(of: .berry) else {
            Issue.record("Glow Berries should cost coins")
            return
        }

        #expect(store.buy(.berry, quantity: 5))
        #expect(store.count(of: .berry) == 5)
        #expect(store.coins == 1_000 - unit * 5)
    }

    @Test("An unaffordable quantity buys nothing")
    func unaffordable() {
        let store = TestSupport.makeStore(coins: 20)
        #expect(!store.buy(.potion, quantity: 3))
        #expect(store.count(of: .potion) == 0)
        #expect(store.coins == 20)
    }

    @Test("Quantities outside 1…max are rejected", arguments: [0, -1, GameStore.maxPurchaseQuantity + 1])
    func invalidQuantity(quantity: Int) {
        let store = TestSupport.makeStore(coins: 1_000_000)
        #expect(!store.buy(.berry, quantity: quantity))
        #expect(store.count(of: .berry) == 0)
    }

    @Test("Max affordable is the balance divided by the unit price, capped")
    func maxAffordable() throws {
        guard case .coins(let unit) = TestSupport.makeStore().price(of: .potion) else {
            Issue.record("Healing Draughts should cost coins")
            return
        }
        #expect(TestSupport.makeStore(coins: unit * 3 + 1).maxAffordable(.potion) == 3)
        #expect(TestSupport.makeStore(coins: 0).maxAffordable(.potion) == 0)
        #expect(TestSupport.makeStore(coins: unit * 500).maxAffordable(.potion) == GameStore.maxPurchaseQuantity)
    }

    @Test("Shard-priced items spend shards, not coins")
    func shardItems() throws {
        let shardItem = try #require(ItemKind.allCases.first { if case .shards = $0.price { true } else { false } },
                                     "Expected at least one item priced in shards")
        let store = TestSupport.makeStore(coins: 1_000, shards: 50)
        #expect(store.buy(shardItem, quantity: 2))
        #expect(store.coins == 1_000)
        #expect(store.shards < 50)
    }

    @Test("Price.times multiplies in the same currency")
    func priceTimes() {
        #expect(Price.coins(15).times(4) == .coins(60))
        #expect(Price.shards(2).times(3) == .shards(6))
    }
}
