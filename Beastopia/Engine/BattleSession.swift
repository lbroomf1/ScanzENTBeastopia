//
//  BattleSession.swift
//  Beastopia
//

import Foundation
import Observation

/// Drives a battle for the UI. Works identically for story, offline Arena and
/// online matches: online sessions just set `sendChoice` and feed in remote choices.
@Observable
final class BattleSession: Identifiable {
    enum Kind: Equatable {
        case story(chapterID: Int)
        case practice
        case raid
        case online
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let localIndex: Int
    /// The player's own beast, for applying rewards when the battle ends.
    let localBeastID: UUID
    let opponentLevel: Int

    private(set) var engine: BattleEngine
    private(set) var isWaitingForPeer = false
    var peerDisconnected = false
    private(set) var rewardsApplied = false
    /// The player ran from the battle.
    private(set) var fled = false
    /// Boss battles always drop Lattice Shards.
    var isBossFight = false
    /// Wild and quest encounters can be fled; bosses and versus matches can't.
    var canFlee = false

    /// Items are offline-only: online peers exchange only move indices.
    var canUseItems: Bool { kind != .online }

    /// Called with (turn, moveIndex) when the local player picks a move in an online match.
    var sendChoice: ((Int, Int) -> Void)?

    private var pending: [Int: [Int: Int]] = [:]

    init(kind: Kind, title: String, engine: BattleEngine, localIndex: Int, localBeastID: UUID, opponentLevel: Int) {
        self.kind = kind
        self.title = title
        self.engine = engine
        self.localIndex = localIndex
        self.localBeastID = localBeastID
        self.opponentLevel = opponentLevel
    }

    var local: Combatant { engine.combatants[localIndex] }

    var allies: [Combatant] { engine.combatants.filter { $0.side == local.side } }
    var enemies: [Combatant] { engine.combatants.filter { $0.side != local.side } }

    var isOver: Bool { engine.isOver || peerDisconnected || fled }

    /// `true` if the local side won. In online versus a disconnect counts as a win.
    var didWin: Bool {
        if fled { return false }
        if let winner = engine.winner { return winner == local.side }
        return peerDisconnected && kind == .online && enemies.contains { $0.controller == .remote }
    }

    var canChoose: Bool {
        !isOver && !local.isDown && pending[engine.turn]?[localIndex] == nil
    }

    func choose(_ moveIndex: Int) {
        guard canChoose, local.moves.indices.contains(moveIndex) else { return }
        let turn = engine.turn
        pending[turn, default: [:]][localIndex] = moveIndex
        sendChoice?(turn, moveIndex)
        resolveIfReady()
    }

    /// Spends the local beast's turn on a battle item. The caller removes it from the inventory.
    func use(_ item: ItemKind) {
        guard canChoose, canUseItems, let choice = BattleEngine.choice(for: item) else { return }
        pending[engine.turn, default: [:]][localIndex] = choice
        resolveIfReady()
    }

    func flee() {
        guard canFlee, !isOver else { return }
        fled = true
    }

    /// Records a remote player's choice. Untrusted input is validated before use.
    func receive(turn: Int, moveIndex: Int, from combatantIndex: Int) {
        guard engine.combatants.indices.contains(combatantIndex),
              engine.combatants[combatantIndex].controller == .remote,
              turn >= engine.turn, turn <= engine.turn + 1,
              (0..<4).contains(moveIndex) else { return }
        pending[turn, default: [:]][combatantIndex] = moveIndex
        resolveIfReady()
    }

    func markRewardsApplied() { rewardsApplied = true }

    private func resolveIfReady() {
        while !engine.isOver {
            let turn = engine.turn
            let choices = pending[turn] ?? [:]
            let needed = engine.combatants.filter { !$0.isDown && $0.controller != .ai }.map(\.id)
            guard needed.allSatisfy({ choices[$0] != nil }) else {
                isWaitingForPeer = choices[localIndex] != nil || local.isDown
                return
            }
            isWaitingForPeer = false
            engine.resolveTurn(choices: choices)
            pending[turn] = nil
        }
        isWaitingForPeer = false
    }

    // MARK: - Factories

    static func story(_ chapter: Chapter, beast: Beast) -> BattleSession {
        let combatants = [
            Combatant(index: 0, beast: beast, side: 0, controller: .local),
            Combatant(index: 1, beast: chapter.opponent, side: 1, controller: .ai),
        ]
        let session = BattleSession(kind: .story(chapterID: chapter.id), title: chapter.title,
                                    engine: BattleEngine(combatants: combatants, seed: .random(in: .min ... .max)),
                                    localIndex: 0, localBeastID: beast.id, opponentLevel: chapter.opponentLevel)
        session.isBossFight = true
        return session
    }

    /// A quest-step battle against a wild or minor beast in a story region.
    static func encounter(_ encounter: Encounter, chapterID: Int, beast: Beast) -> BattleSession {
        let combatants = [
            Combatant(index: 0, beast: beast, side: 0, controller: .local),
            Combatant(index: 1, beast: encounter.opponent, side: 1, controller: .ai),
        ]
        let session = BattleSession(kind: .story(chapterID: chapterID), title: encounter.name,
                                    engine: BattleEngine(combatants: combatants, seed: .random(in: .min ... .max)),
                                    localIndex: 0, localBeastID: beast.id, opponentLevel: encounter.level)
        session.canFlee = true
        return session
    }

    /// Offline versus against an AI rival scaled to the player's beast.
    static func practice(beast: Beast) -> BattleSession {
        let seed = UInt64.random(in: .min ... .max)
        let level = max(1, beast.level + Int.random(in: -1...2))
        var rival = BeastGenerator.opponent(seed: "rival-\(seed)", level: level)
        rival.nickname = "Rival \(rival.species.name)"
        let combatants = [
            Combatant(index: 0, beast: beast, side: 0, controller: .local),
            Combatant(index: 1, beast: rival, side: 1, controller: .ai),
        ]
        return BattleSession(kind: .practice, title: "Arena Practice",
                             engine: BattleEngine(combatants: combatants, seed: seed),
                             localIndex: 0, localBeastID: beast.id, opponentLevel: level)
    }

    /// A fight against the AI-controlled ghost of another keeper's beast, from a Challenge Card.
    static func challenge(_ card: ChallengeCard, beast: Beast) -> BattleSession {
        let ghost = card.ghost
        let combatants = [
            Combatant(index: 0, beast: beast, side: 0, controller: .local),
            Combatant(index: 1, beast: ghost, side: 1, controller: .ai),
        ]
        return BattleSession(kind: .practice, title: "Challenge: \(card.keeperName)",
                             engine: BattleEngine(combatants: combatants, seed: .random(in: .min ... .max)),
                             localIndex: 0, localBeastID: beast.id, opponentLevel: ghost.level)
    }

    /// Co-op raid: the player and an ally team up against a boss.
    /// `ally` is AI-controlled offline or a remote player online.
    static func raid(beast: Beast, ally: Beast, allyController: Controller, localFirst: Bool, seed: UInt64) -> BattleSession {
        let boss = raidBoss(seed: seed, partyLevel: (beast.level + ally.level) / 2)
        let first = localFirst ? beast : ally
        let second = localFirst ? ally : beast
        let combatants = [
            Combatant(index: 0, beast: first, side: 0, controller: localFirst ? .local : allyController),
            Combatant(index: 1, beast: second, side: 0, controller: localFirst ? allyController : .local),
            Combatant(index: 2, beast: boss, side: 1, controller: .ai, hpMultiplier: 3),
        ]
        let session = BattleSession(kind: allyController == .remote ? .online : .raid, title: "Raid: \(boss.displayName)",
                                    engine: BattleEngine(combatants: combatants, seed: seed),
                                    localIndex: localFirst ? 0 : 1, localBeastID: beast.id, opponentLevel: boss.level)
        session.isBossFight = true
        return session
    }

    static func raidBoss(seed: UInt64, partyLevel: Int) -> Beast {
        let apexes = SpeciesDatabase.all.filter { $0.stage == .apex }
        let species = apexes[Int(seed % UInt64(apexes.count))]
        var boss = BeastGenerator.opponent(seed: "raid-\(seed)", speciesID: species.id, level: partyLevel + 3)
        boss.nickname = "Corrupted \(species.name)"
        return boss
    }
}
