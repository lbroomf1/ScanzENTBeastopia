//
//  Item.swift
//  Beastopia
//

import SwiftUI

/// What an item costs in the Haven Market.
enum Price: Hashable, Sendable {
    case coins(Int)
    /// Lattice Shards: a rare currency from bosses and treasure, for the most potent goods.
    case shards(Int)

    /// The price of `quantity` of something at this unit price.
    func times(_ quantity: Int) -> Price {
        switch self {
        case .coins(let amount): .coins(amount * quantity)
        case .shards(let amount): .shards(amount * quantity)
        }
    }
}

/// Consumable items. Battle items are used from the Bag during a fight; field items are
/// used on a beast in the Haven. Raw values are persisted, so never rename them.
enum ItemKind: String, Codable, CaseIterable, Identifiable, Sendable {
    // Battle
    case berry, potion, fullElixir, remedy, gutsTonic
    // Field
    case latticeCandy, starCandy, bondTreat, calmTea

    var id: String { rawValue }

    /// How an item works when used in battle.
    enum BattleEffect: Sendable {
        /// Restores this percentage of max HP.
        case heal(percent: Int)
        /// Clears burn, shock and blight.
        case cure
        case guts(Int)
    }

    var name: String {
        switch self {
        case .berry: "Glow Berry"
        case .potion: "Healing Draught"
        case .fullElixir: "Full Elixir"
        case .remedy: "Remedy Herb"
        case .gutsTonic: "Guts Tonic"
        case .latticeCandy: "Lattice Candy"
        case .starCandy: "Star Candy"
        case .bondTreat: "Bond Treat"
        case .calmTea: "Calm Tea"
        }
    }

    var symbol: String {
        switch self {
        case .berry: "circle.circle.fill"
        case .potion: "cross.vial.fill"
        case .fullElixir: "flask.fill"
        case .remedy: "leaf.circle.fill"
        case .gutsTonic: "bolt.heart.fill"
        case .latticeCandy: "seal.fill"
        case .starCandy: "star.circle.fill"
        case .bondTreat: "heart.circle.fill"
        case .calmTea: "cup.and.saucer.fill"
        }
    }

    /// Asset catalog name for this item's icon.
    var iconArt: String { "item_\(rawValue)" }

    var color: Color {
        switch self {
        case .berry: .pink
        case .potion: .green
        case .fullElixir: .mint
        case .remedy: .teal
        case .gutsTonic: .orange
        case .latticeCandy: .blue
        case .starCandy: .yellow
        case .bondTreat: .red
        case .calmTea: .brown
        }
    }

    var summary: String {
        switch self {
        case .berry: "Battle: restores 30% HP."
        case .potion: "Battle: restores 60% HP."
        case .fullElixir: "Battle: fully restores HP and cures ailments."
        case .remedy: "Battle: cures burn, shock and blight."
        case .gutsTonic: "Battle: +50 Guts."
        case .latticeCandy: "Haven: +120 XP."
        case .starCandy: "Haven: +600 XP."
        case .bondTreat: "Haven: Bond +12."
        case .calmTea: "Haven: Fatigue −50."
        }
    }

    var price: Price {
        switch self {
        case .berry: .coins(15)
        case .potion: .coins(40)
        case .fullElixir: .shards(3)
        case .remedy: .coins(20)
        case .gutsTonic: .coins(30)
        case .latticeCandy: .coins(60)
        case .starCandy: .shards(2)
        case .bondTreat: .coins(35)
        case .calmTea: .coins(25)
        }
    }

    var battleEffects: [BattleEffect] {
        switch self {
        case .berry: [.heal(percent: 30)]
        case .potion: [.heal(percent: 60)]
        case .fullElixir: [.heal(percent: 100), .cure]
        case .remedy: [.cure]
        case .gutsTonic: [.guts(50)]
        default: []
        }
    }

    var isBattleItem: Bool { !battleEffects.isEmpty }

    static let battleItems = allCases.filter(\.isBattleItem)
    static let fieldItems = allCases.filter { !$0.isBattleItem }

    /// Whether using it on `beast` outside battle would do anything.
    func isUsefulInField(for beast: Beast) -> Bool {
        switch self {
        case .latticeCandy, .starCandy: beast.level < 99
        case .bondTreat: beast.bond < 100
        case .calmTea: beast.fatigue > 0
        default: false
        }
    }

    /// Applies a field item. Returns the number of levels gained.
    @discardableResult
    func applyInField(to beast: inout Beast) -> Int {
        switch self {
        case .latticeCandy: return RanchEngine.addXP(&beast, amount: 120)
        case .starCandy: return RanchEngine.addXP(&beast, amount: 600)
        case .bondTreat: beast.bond = min(100, beast.bond + 12)
        case .calmTea: beast.fatigue = max(0, beast.fatigue - 50)
        default: break
        }
        return 0
    }
}

/// A bundle of loot: from chests, battle drops and quest rewards.
struct Loot: Sendable {
    var items: [ItemKind: Int] = [:]
    var coins = 0
    var shards = 0

    var isEmpty: Bool { items.isEmpty && coins == 0 && shards == 0 }

    /// "2× Glow Berry, 50 coins, 1 shard"
    var summary: String {
        var parts = ItemKind.allCases.compactMap { kind in
            items[kind].map { "\($0)× \(kind.name)" }
        }
        if coins > 0 { parts.append("\(coins) coins") }
        if shards > 0 { parts.append("\(shards) shard\(shards == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Traversal

/// Field abilities a beast lends its keeper while exploring.
enum TraversalAbility: String, CaseIterable, Identifiable, Sendable {
    case swim, fly, teleport

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .swim: "Swim"
        case .fly: "Fly"
        case .teleport: "Blink"
        }
    }

    var symbol: String {
        switch self {
        case .swim: "figure.open.water.swim"
        case .fly: "bird.fill"
        case .teleport: "sparkles"
        }
    }

    /// Asset catalog name for this ability's icon. Teleport is called Blink in the game.
    var iconArt: String { "ability_\(self == .teleport ? "blink" : rawValue)" }

    var summary: String {
        switch self {
        case .swim: "A Tide beast carries you across water."
        case .fly: "A flying beast lifts you over water, lava and chasms."
        case .teleport: "A Lumen or Umbra beast blinks you up to 5 tiles past walls. You need it for the walled-in chests in Greenmantle Wilds, Skyreach Peaks and Gravel Hollow: tap a spot beyond the wall, or press Blink."
        }
    }
}

extension Species {
    /// Which field abilities this species can lend while exploring.
    var abilities: Set<TraversalAbility> {
        var result: Set<TraversalAbility> = []
        if element == .tide { result.insert(.swim) }
        if element == .gale || ["pyrowl", "solaryx", "aurorion"].contains(id) { result.insert(.fly) }
        if element == .lumen || element == .umbra || id == "chronodrake" { result.insert(.teleport) }
        return result
    }
}
