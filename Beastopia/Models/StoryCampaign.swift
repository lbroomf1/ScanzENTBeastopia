//
//  StoryCampaign.swift
//  Beastopia
//

import Foundation

/// A chapter of the main storyline, "The Silent Lattice".
struct Chapter: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let region: String
    let element: Element
    let intro: String
    let opponentName: String
    let opponentSpeciesID: String
    let opponentLevel: Int
    let outro: String
    let coinReward: Int

    var opponent: Beast {
        var beast = BeastGenerator.opponent(seed: "story-\(id)", speciesID: opponentSpeciesID, level: opponentLevel)
        beast.nickname = opponentName
        return beast
    }
}

enum StoryCampaign {
    static let prologue = """
    Long ago, every beast in Beastopia roamed free. Then came the Shattering — the Null, \
    a hunger from beyond the world, began erasing beasts from existence.

    To save them, the first Glyphkeepers sealed every beast into the Codex Lattice: patterns \
    hidden inside the marks and codes of the world. Every barcode, every QR glyph, every \
    printed pattern is a lock — and somewhere inside, a beast is sleeping.

    You are a new Glyphkeeper. Your mentor, Old Maren, has left you her Beast Haven and \
    a Lattice Lens. Scan the world. Wake the beasts. And find out why the Lattice has \
    begun to go silent.
    """

    static let chapters: [Chapter] = [
        Chapter(id: 1, title: "The First Glyph", region: "Beast Haven", element: .verdant,
                intro: "Maren's old training dummy has been possessed by a stray Lattice spark. Show it what a Glyphkeeper can do.",
                opponentName: "Haven Sprout", opponentSpeciesID: "sproutle", opponentLevel: 2,
                outro: "Maren's journal falls open: \"The Lattice is going quiet, region by region. Follow the silence.\"",
                coinReward: 100),
        Chapter(id: 2, title: "Embers of the Caldera", region: "Emberfall Caldera", element: .ember,
                intro: "The volcano's beasts are rampaging. A masked figure in grey was seen near the crater — the Null Syndicate.",
                opponentName: "Feral Magmaw", opponentSpeciesID: "magmaw", opponentLevel: 6,
                outro: "The Magmaw calms. Burned into the rock is a sigil: a hollow circle. The Syndicate is real.",
                coinReward: 200),
        Chapter(id: 3, title: "Songs Under the Tide", region: "Tidewhisper Coast", element: .tide,
                intro: "The Tidecrest's song has stopped and the sea is turning grey. Your rival Kade got here first.",
                opponentName: "Kade's Tidecrest", opponentSpeciesID: "tidecrest", opponentLevel: 10,
                outro: "Kade scoffs, but warns you: \"The Syndicate is harvesting codes. Erasing them for something big.\"",
                coinReward: 300),
        Chapter(id: 4, title: "The Thorn Labyrinth", region: "Greenmantle Wilds", element: .verdant,
                intro: "An ancient Thornback guards the Wilds' Lattice node. It will only let a worthy keeper pass.",
                opponentName: "Warden Thornback", opponentSpeciesID: "thornback", opponentLevel: 14,
                outro: "Inside the node you find Maren's handwriting: \"The Null isn't a monster. It's a beast that was never sealed.\"",
                coinReward: 400),
        Chapter(id: 5, title: "Storm over Skyreach", region: "Skyreach Peaks", element: .gale,
                intro: "Syndicate airships circle the peaks, draining storm-beasts into blank glyphs. Stop their commander.",
                opponentName: "Commander Vey's Zephyrix", opponentSpeciesID: "zephyrix", opponentLevel: 18,
                outro: "Vey escapes, dropping a manifest: every erased code is being fed to something called Oblivyrn.",
                coinReward: 500),
        Chapter(id: 6, title: "The Iron Quarry", region: "Gravel Hollow", element: .terra,
                intro: "Kade's been captured in the quarry. Team up with old enemies to break him out.",
                opponentName: "Syndicate Bouldrake", opponentSpeciesID: "bouldrake", opponentLevel: 22,
                outro: "Kade joins you. \"Maren founded the Syndicate,\" he admits. \"Before it went wrong.\"",
                coinReward: 600),
        Chapter(id: 7, title: "Thunder at the Spire Gate", region: "Voltmarsh", element: .volt,
                intro: "The Null Spire rises from the marsh. Its gate is guarded by a beast charged with stolen lightning.",
                opponentName: "Gatekeeper Thundervex", opponentSpeciesID: "thundervex", opponentLevel: 28,
                outro: "At the top of the Spire, a figure waits. It's Maren — and she isn't alone.",
                coinReward: 800),
        Chapter(id: 8, title: "The Silent Lattice", region: "Null Spire", element: .umbra,
                intro: "Maren meant to seal the Null forever by feeding it codes until it slept. Instead it woke. Oblivyrn must be stopped.",
                opponentName: "Oblivyrn, the Null Wyrm", opponentSpeciesID: "oblivyrn", opponentLevel: 35,
                outro: "Oblivyrn shatters into a billion glyphs, scattering across the world. The Lattice sings again. Every code you scan now might hold a beast it once devoured… Your Beastopia is only beginning.",
                coinReward: 2000),
    ]
}
