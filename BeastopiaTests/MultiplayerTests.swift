//
//  MultiplayerTests.swift
//  BeastopiaTests
//

import Foundation
import Testing
@testable import Beastopia

struct MultiplayerTests {
    @Test("A peer's out-of-range stats are clamped to 1–999")
    func sanitizedClampsStats() throws {
        // Decoding skips the `Stats` setter's clamp, which is how a modified client would send these.
        let data = try JSONEncoder().encode(TestSupport.beast("pebblit"))
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var stats = try #require(json["stats"] as? [String: Any])
        stats["power"] = 50_000
        stats["defense"] = -7
        json["stats"] = stats
        let forged = try JSONDecoder().decode(Beast.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(forged.stats.power == 50_000)

        let clean = MultiplayerManager.sanitized(forged)
        #expect(clean.stats.power == Stats.cap)
        #expect(clean.stats.defense == 1)
    }

    @Test("A peer's beast gets a fresh ID and every other field is clamped")
    func sanitizedClampsEverything() {
        var forged = TestSupport.beast("pebblit", level: 12)
        let ownID = forged.id
        forged.originTag = String(repeating: "A", count: 10_000)
        forged.hue = .nan
        forged.bond = 5_000
        forged.fatigue = -40
        forged.xp = .max
        forged.wins = -1

        let clean = MultiplayerManager.sanitized(forged)
        #expect(clean.id != ownID)
        #expect(clean.originTag.count <= 24)
        #expect(clean.hue == 0)
        #expect(clean.bond == 100)
        #expect(clean.fatigue == 0)
        #expect(clean.xp <= 99 * 50)
        #expect(clean.wins == 0)
    }

    @Test("Sanitizing never changes what the battle engine reads from a legitimate beast")
    func sanitizedKeepsBattleFields() {
        let honest = TestSupport.beast("tidecrest", level: 30, bond: 60)
        let clean = MultiplayerManager.sanitized(honest)
        #expect(clean.speciesID == honest.speciesID)
        #expect(clean.stats == honest.stats)
        #expect(clean.level == honest.level)
        #expect(clean.trait == honest.trait)
        #expect(clean.hue == honest.hue)
    }
}
