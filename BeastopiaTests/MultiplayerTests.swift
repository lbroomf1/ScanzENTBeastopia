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
}
