//
//  ChallengeCard.swift
//  Beastopia
//

import CoreImage.CIFilterBuiltins
import Foundation
import UIKit

/// A keeper's fighter, packed small enough for a QR code or a cheap NFC sticker (a card is about
/// 150 bytes, so it fits an NTAG215 or NTAG216; the tiny NTAG213 is too small). Anyone who scans it fights an AI-controlled "ghost"
/// of that beast, so keepers can battle without being online at the same time.
///
/// Cards are just text, so they're untrusted: decoding goes through `MultiplayerManager.sanitized`.
struct ChallengeCard: Codable, Equatable, Sendable {
    /// Format version, so later builds can still read older cards.
    var v = 1
    /// Keeper name.
    var k: String
    /// Species ID.
    var s: String
    /// Nickname, empty for none.
    var n: String
    /// Level.
    var l: Int
    /// Stats: life, power, intellect, defense, speed, skill.
    var t: [Int]
    /// Trait raw value.
    var r: String
    /// Rarity raw value.
    var q: Int

    /// Every card starts with this, which is how the Scan tab tells a card from a summoning code.
    static let prefix = "BEASTOPIA-DUEL:"

    init(keeperName: String, beast: Beast) {
        k = String(keeperName.prefix(16))
        s = beast.speciesID
        n = String(beast.nickname.prefix(12))
        l = beast.level
        t = StatKind.allCases.map { beast.stats[$0] }
        r = beast.trait.rawValue
        q = beast.rarity.rawValue
    }

    static func isCard(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix(prefix)
    }

    /// The text written to the tag or drawn in the QR code.
    var payload: String {
        let json = (try? JSONEncoder().encode(self)) ?? Data()
        let base64 = json.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return Self.prefix + base64
    }

    /// Reads a card's text. Returns `nil` for anything that isn't a well-formed card.
    init?(payload: String) {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count < 1_024, text.uppercased().hasPrefix(Self.prefix) else { return nil }
        var base64 = String(text.dropFirst(Self.prefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let card = try? JSONDecoder().decode(ChallengeCard.self, from: data),
              card.t.count == StatKind.allCases.count else { return nil }
        self = card
    }

    /// The beast on the card, clamped to legal values like a beast from an online peer.
    var ghost: Beast {
        var stats = Stats(life: 1, power: 1, intellect: 1, defense: 1, speed: 1, skill: 1)
        for (kind, value) in zip(StatKind.allCases, t) { stats[kind] = value }
        var beast = Beast(speciesID: s, nickname: n, stats: stats, trait: Trait(rawValue: r) ?? .brave,
                          rarity: Rarity(rawValue: q) ?? .common, hue: 0, isPrismatic: false,
                          originTag: "Challenge Card")
        beast.level = l
        beast = MultiplayerManager.sanitized(beast)
        // A ghost is named after its keeper, e.g. "Kade's Tidecrest".
        let keeper = String(k.prefix(16))
        beast.nickname = keeper.isEmpty ? beast.species.name : "\(keeper)'s \(beast.displayName)"
        return beast
    }

    var keeperName: String { k.isEmpty ? "A keeper" : k }

    /// A crisp QR code of the payload, for showing on screen or printing.
    var qrImage: UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
