//
//  BattleEngine.swift
//  Beastopia
//

import Foundation

/// Who decides a combatant's move each turn.
enum Controller: Sendable {
    case local, remote, ai
}

/// Lingering ailments inflicted by elemental attacks. Each lasts a few turns.
enum StatusEffect: String, Sendable {
    /// Ember: loses a little HP every turn.
    case burn
    /// Volt: sometimes too stunned to act.
    case shock
    /// Verdant and Umbra: loses more HP every turn.
    case blight

    var displayName: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .burn: "flame.fill"
        case .shock: "bolt.fill"
        case .blight: "allergens.fill"
        }
    }

    /// Asset catalog name for this status's icon.
    var iconArt: String { "status_\(rawValue)" }

    /// Which ailment an element's attacks can inflict.
    static func inflicted(by element: Element) -> StatusEffect? {
        switch element {
        case .ember: .burn
        case .volt: .shock
        case .verdant, .umbra: .blight
        default: nil
        }
    }

    /// Percent of max HP lost at the end of each turn.
    var damagePercent: Int {
        switch self {
        case .burn: 6
        case .shock: 0
        case .blight: 8
        }
    }
}

/// Something that happened in battle, for the battle screen to animate.
struct BattleEvent: Identifiable, Sendable {
    enum Kind: Sendable {
        case attack(move: String, element: Element?)
        case damage(amount: Int, critical: Bool, effectiveness: Double)
        case miss
        case heal(amount: Int)
        case guardUp
        case inflicted(StatusEffect)
        case statusDamage(StatusEffect, amount: Int)
        case stunned
        case cured
        case item(ItemKind)
        case guts(Int)
        case knockout
    }

    let id: Int
    /// The combatant this happened to.
    let target: Int
    /// The combatant who caused it.
    let source: Int
    let kind: Kind
    /// The target's HP once this event has played.
    let hpAfter: Int
}

/// A beast's in-battle state.
struct Combatant: Identifiable, Sendable {
    let id: Int
    let side: Int
    let controller: Controller
    let name: String
    let speciesID: String
    let element: Element
    let hiddenElement: Element
    let stats: Stats
    let moves: [Move]
    let maxHP: Int
    let hue: Double
    let isPrismatic: Bool
    var hp: Int
    var guts = 50
    var guarding = false
    var status: StatusEffect?
    var statusTurns = 0

    var isDown: Bool { hp <= 0 }

    init(index: Int, beast: Beast, side: Int, controller: Controller, hpMultiplier: Double = 1) {
        id = index
        self.side = side
        self.controller = controller
        name = beast.displayName
        speciesID = beast.speciesID
        element = beast.species.element
        hiddenElement = beast.species.hiddenElement
        stats = beast.stats
        moves = beast.species.moves
        maxHP = Int(Double(beast.maxHP) * hpMultiplier)
        hue = beast.hue
        isPrismatic = beast.isPrismatic
        hp = maxHP
    }
}

/// Deterministic turn-based battle simulation.
///
/// Given the same seed, combatants and per-turn choices, every device produces the
/// exact same result. Multiplayer relies on this: peers only exchange chosen moves
/// (lockstep), never HP or damage, so there's nothing to desync or spoof.
struct BattleEngine: Sendable {
    static let gutsRegen = 12
    static let maxGuts = 100
    /// Choices at or above this value use a battle item instead of a move:
    /// `itemChoiceBase + index` into `ItemKind.battleItems`.
    static let itemChoiceBase = 100
    static let statusDuration = 3

    static func choice(for item: ItemKind) -> Int? {
        ItemKind.battleItems.firstIndex(of: item).map { itemChoiceBase + $0 }
    }

    private(set) var combatants: [Combatant]
    private var rng: SeededRandom
    private(set) var turn = 1
    private(set) var log: [String] = []
    private(set) var events: [BattleEvent] = []
    /// The winning side, once the battle is over.
    private(set) var winner: Int?

    init(combatants: [Combatant], seed: UInt64) {
        self.combatants = combatants
        rng = SeededRandom(seed: seed)
        let names = combatants.map(\.name).joined(separator: " vs ")
        log.append("Battle start! \(names)")
    }

    var isOver: Bool { winner != nil }

    func canAfford(_ move: Move, combatant index: Int) -> Bool {
        combatants[index].guts >= move.gutsCost
    }

    // MARK: - Turn resolution

    /// Resolves one full turn. `choices` maps combatant index to move index;
    /// AI-controlled combatants (or missing/invalid choices) are decided by the engine.
    mutating func resolveTurn(choices: [Int: Int]) {
        guard !isOver else { return }

        for i in combatants.indices { combatants[i].guarding = false }

        // Decide every action up front so turn order can't influence choices.
        var actions: [Int: Int] = [:]
        var items: [Int: ItemKind] = [:]
        for c in combatants where !c.isDown {
            if c.controller != .ai, let choice = choices[c.id], combatants[c.id].moves.indices.contains(choice) {
                actions[c.id] = choice
            } else if c.controller != .ai, let choice = choices[c.id], choice >= Self.itemChoiceBase,
                      ItemKind.battleItems.indices.contains(choice - Self.itemChoiceBase) {
                items[c.id] = ItemKind.battleItems[choice - Self.itemChoiceBase]
            } else {
                actions[c.id] = aiChoice(for: c.id)
            }
        }

        // Items are used before anyone attacks.
        for (actor, item) in items.sorted(by: { $0.key < $1.key }) {
            use(item, by: actor)
        }

        // Faster beasts act first; a seeded tiebreak keeps ordering deterministic.
        let tiebreak = combatants.map { _ in rng.int(1000) }
        let order = combatants.indices.sorted {
            let a = combatants[$0], b = combatants[$1]
            if a.stats.speed != b.stats.speed { return a.stats.speed > b.stats.speed }
            if tiebreak[$0] != tiebreak[$1] { return tiebreak[$0] > tiebreak[$1] }
            return $0 < $1
        }

        for actor in order {
            guard !combatants[actor].isDown, let moveIndex = actions[actor], !isOver else { continue }
            if combatants[actor].status == .shock, rng.int(100) < 30 {
                log.append("\(combatants[actor].name) is shocked and can't move!")
                record(.stunned, target: actor, source: actor)
                continue
            }
            var move = combatants[actor].moves[moveIndex]
            if !canAfford(move, combatant: actor) { move = .guardUp }
            perform(move, by: actor)
            checkForWinner()
        }

        if !isOver { applyStatusEffects() }

        for i in combatants.indices where !combatants[i].isDown {
            combatants[i].guts = min(Self.maxGuts, combatants[i].guts + Self.gutsRegen)
        }
        turn += 1
    }

    private mutating func record(_ kind: BattleEvent.Kind, target: Int, source: Int) {
        events.append(BattleEvent(id: events.count, target: target, source: source, kind: kind,
                                  hpAfter: combatants[target].hp))
    }

    /// End-of-turn ailment damage and countdown.
    private mutating func applyStatusEffects() {
        for i in combatants.indices where !combatants[i].isDown {
            guard let status = combatants[i].status else { continue }
            let name = combatants[i].name
            if status.damagePercent > 0 {
                let amount = max(1, combatants[i].maxHP * status.damagePercent / 100)
                combatants[i].hp = max(0, combatants[i].hp - amount)
                log.append("\(name) is hurt by its \(status.displayName.lowercased()) (\(amount)).")
                record(.statusDamage(status, amount: amount), target: i, source: i)
                if combatants[i].isDown {
                    log.append("\(name) is down!")
                    record(.knockout, target: i, source: i)
                    checkForWinner()
                    if isOver { return }
                    continue
                }
            }
            combatants[i].statusTurns -= 1
            if combatants[i].statusTurns <= 0 {
                combatants[i].status = nil
                log.append("\(name) shook off its \(status.displayName.lowercased()).")
                record(.cured, target: i, source: i)
            }
        }
    }

    private mutating func use(_ item: ItemKind, by actor: Int) {
        let name = combatants[actor].name
        log.append("Used \(item.name) on \(name)!")
        record(.item(item), target: actor, source: actor)
        for effect in item.battleEffects {
            switch effect {
            case .heal(let percent):
                let amount = min(combatants[actor].maxHP - combatants[actor].hp, combatants[actor].maxHP * percent / 100)
                combatants[actor].hp += amount
                log.append("\(name) recovers \(amount) HP.")
                record(.heal(amount: amount), target: actor, source: actor)
            case .cure:
                if combatants[actor].status != nil {
                    combatants[actor].status = nil
                    combatants[actor].statusTurns = 0
                    log.append("\(name) is cured!")
                    record(.cured, target: actor, source: actor)
                }
            case .guts(let amount):
                combatants[actor].guts = min(Self.maxGuts, combatants[actor].guts + amount)
                log.append("\(name) is fired up! +\(amount) Guts.")
                record(.guts(amount), target: actor, source: actor)
            }
        }
    }

    private mutating func perform(_ move: Move, by actor: Int) {
        combatants[actor].guts -= move.gutsCost
        let name = combatants[actor].name

        switch move.kind {
        case .guarding:
            combatants[actor].guarding = true
            combatants[actor].guts = min(Self.maxGuts, combatants[actor].guts + 15)
            log.append("\(name) braces itself and gathers Guts.")
            record(.guardUp, target: actor, source: actor)
        case .heal:
            let amount = combatants[actor].maxHP * move.power / 100
            combatants[actor].hp = min(combatants[actor].maxHP, combatants[actor].hp + amount)
            log.append("\(name) recovers \(amount) HP.")
            record(.heal(amount: amount), target: actor, source: actor)
        case .physical, .special:
            guard let target = pickTarget(for: actor) else { return }
            attack(with: move, from: actor, to: target)
        }
    }

    private mutating func pickTarget(for actor: Int) -> Int? {
        let side = combatants[actor].side
        let enemies = combatants.filter { $0.side != side && !$0.isDown }.map(\.id)
        guard !enemies.isEmpty else { return nil }
        return enemies.count == 1 ? enemies[0] : enemies[rng.int(enemies.count)]
    }

    private mutating func attack(with move: Move, from attacker: Int, to defender: Int) {
        let a = combatants[attacker], d = combatants[defender]

        record(.attack(move: move.name, element: move.element), target: defender, source: attacker)
        let hitChance = min(100, max(50, move.accuracy + (a.stats.skill - d.stats.speed) / 10))
        guard rng.int(100) < hitChance else {
            log.append("\(a.name)'s \(move.name) missed!")
            record(.miss, target: defender, source: attacker)
            return
        }

        var damage = Self.baseDamage(move: move, attacker: a, defender: d)
        damage *= 0.85 + 0.15 * rng.unit()

        let isCritical = rng.int(1000) < min(a.stats.skill, 250)
        if isCritical { damage *= 1.5 }
        if d.guarding { damage *= 0.5 }

        let dealt = max(1, Int(damage.rounded()))
        combatants[defender].hp = max(0, d.hp - dealt)

        var line = "\(a.name) used \(move.name)! \(dealt) damage"
        if isCritical { line += " — critical hit" }
        let effectiveness = move.element?.multiplier(against: d.element, hidden: d.hiddenElement) ?? 1
        if effectiveness > 1.2 { line += " — super effective" }
        if effectiveness < 0.8 { line += " — not very effective" }
        log.append(line + ".")
        record(.damage(amount: dealt, critical: isCritical, effectiveness: effectiveness), target: defender, source: attacker)
        if combatants[defender].isDown {
            log.append("\(d.name) is down!")
            record(.knockout, target: defender, source: attacker)
            return
        }

        // Elemental techniques (not plain Strikes) can leave a lingering ailment.
        if let element = move.element, let status = StatusEffect.inflicted(by: element),
           combatants[defender].status == nil, rng.int(100) < 20 {
            combatants[defender].status = status
            combatants[defender].statusTurns = Self.statusDuration
            log.append("\(d.name) is afflicted with \(status.displayName.lowercased())!")
            record(.inflicted(status), target: defender, source: attacker)
        }
    }

    /// Expected damage before randomness, critical hits and guarding.
    static func baseDamage(move: Move, attacker a: Combatant, defender d: Combatant) -> Double {
        let physical = move.kind == .physical
        let attack = Double(physical ? a.stats.power : a.stats.intellect)
        let defense = Double(physical ? d.stats.defense : (d.stats.defense + d.stats.intellect) / 2)
        var damage = Double(move.power) * attack / (defense + 40) * 0.9 + 3
        if let element = move.element {
            if element == a.element { damage *= 1.2 }
            damage *= element.multiplier(against: d.element, hidden: d.hiddenElement)
        }
        return damage
    }

    private mutating func checkForWinner() {
        let sides = Set(combatants.map(\.side))
        for side in sides.sorted() where combatants.filter({ $0.side == side }).allSatisfy(\.isDown) {
            winner = sides.first { $0 != side }
            log.append(winner == 0 ? "Side A wins!" : "Side B wins!")
            return
        }
    }

    // MARK: - AI

    /// Picks the affordable move with the best expected damage, with a little unpredictability.
    private mutating func aiChoice(for index: Int) -> Int {
        let me = combatants[index]
        let guardIndex = me.moves.firstIndex { $0.kind == .guarding } ?? 0
        let affordable = me.moves.indices.filter { me.moves[$0].kind != .guarding && me.guts >= me.moves[$0].gutsCost }
        guard !affordable.isEmpty else { return guardIndex }
        guard let target = combatants.first(where: { $0.side != me.side && !$0.isDown }) else { return guardIndex }

        if rng.int(100) < 20 { return affordable[rng.int(affordable.count)] }
        return affordable.max { lhs, rhs in
            Self.baseDamage(move: me.moves[lhs], attacker: me, defender: target)
                < Self.baseDamage(move: me.moves[rhs], attacker: me, defender: target)
        } ?? guardIndex
    }
}
