//
//  WorldMap.swift
//  Beastopia
//

import Foundation

/// A character the player can talk to in the adventure world.
struct NPC: Sendable {
    let name: String
    let title: String
    let symbol: String

    /// Dialogue portrait art, named after the character's last name: "Elder Brasa" → `portrait_brasa`.
    var portraitArt: String {
        "portrait_" + (name.split(separator: " ").last.map { $0.lowercased() } ?? "")
    }

    static let pip = NPC(name: "Pip", title: "Haven Caretaker", symbol: "person.fill")
    static let brasa = NPC(name: "Elder Brasa", title: "Caldera Village Elder", symbol: "flame.fill")
    static let nell = NPC(name: "Nell", title: "Tidewhisper Fisher", symbol: "fish.fill")
    static let kade = NPC(name: "Kade", title: "Rival Glyphkeeper", symbol: "person.fill.questionmark")
    static let ivy = NPC(name: "Ranger Ivy", title: "Warden of the Wilds", symbol: "leaf.fill")
    static let wren = NPC(name: "Wren", title: "Skyreach Courier", symbol: "paperplane.fill")
    static let rook = NPC(name: "Rook", title: "Syndicate Deserter", symbol: "theatermasks.fill")
    static let maren = NPC(name: "Maren", title: "Your Mentor", symbol: "book.closed.fill")
}

/// One line of dialogue. Lines can be gated on story flags set by earlier choices,
/// which is how small decisions ripple forward through the story.
struct DialogueLine: Sendable {
    /// `nil` means the NPC being talked to is speaking.
    let speaker: String?
    let text: String
    var requires: String? = nil
    var excludes: String? = nil

    func isVisible(with flags: Set<String>) -> Bool {
        if let requires, !flags.contains(requires) { return false }
        if let excludes, flags.contains(excludes) { return false }
        return true
    }
}

/// A response the player can pick at the end of a conversation.
struct DialogueChoice: Identifiable, Sendable {
    var id: String { text }
    let text: String
    let reply: String
    /// Story flag recorded when this choice is made.
    var flag: String? = nil
    var coinReward = 0
}

struct Dialogue: Sendable {
    let lines: [DialogueLine]
    var choices: [DialogueChoice] = []
}

/// A wild or minor beast fought as a quest step.
struct Encounter: Sendable {
    let seed: String
    let name: String
    let speciesID: String
    let level: Int

    var opponent: Beast {
        var beast = BeastGenerator.opponent(seed: seed, speciesID: speciesID, level: level)
        beast.nickname = name
        return beast
    }
}

/// A single step of a region's quest. Steps are completed in order.
struct Objective: Identifiable, Sendable {
    enum Kind: Sendable {
        case talk(NPC, Dialogue)
        case defeat(Encounter)
        /// The chapter's boss. Defeating it completes the chapter.
        case boss
    }

    /// Stable and persisted, so never rename.
    let id: String
    let summary: String
    let kind: Kind
}

/// A location on the world map. Each region hosts one chapter of the story.
struct Region: Identifiable, Sendable {
    let chapter: Chapter
    /// Normalized (0...1) position on the world map.
    let x: Double
    let y: Double
    let description: String
    let objectives: [Objective]

    var id: Int { chapter.id }
}

enum WorldMap {
    static func region(for chapter: Chapter) -> Region? {
        regions.first { $0.id == chapter.id }
    }

    // MARK: - Helpers

    private static func chapter(_ id: Int) -> Chapter { StoryCampaign.chapters[id - 1] }

    private static func say(_ text: String, if flag: String? = nil, unless excluded: String? = nil) -> DialogueLine {
        DialogueLine(speaker: nil, text: text, requires: flag, excludes: excluded)
    }

    private static func you(_ text: String) -> DialogueLine {
        DialogueLine(speaker: "You", text: text)
    }

    private static func talk(_ id: String, _ summary: String, _ npc: NPC,
                             _ lines: [DialogueLine], choices: [DialogueChoice] = []) -> Objective {
        Objective(id: id, summary: summary, kind: .talk(npc, Dialogue(lines: lines, choices: choices)))
    }

    private static func defeat(_ id: String, _ summary: String, name: String, species: String, level: Int) -> Objective {
        Objective(id: id, summary: summary,
                  kind: .defeat(Encounter(seed: id, name: name, speciesID: species, level: level)))
    }

    private static func boss(_ chapterID: Int) -> Objective {
        let chapter = chapter(chapterID)
        return Objective(id: "ch\(chapterID)-boss", summary: "Defeat \(chapter.opponentName)", kind: .boss)
    }

    // MARK: - Regions

    static let regions: [Region] = [
        Region(chapter: chapter(1), x: 0.50, y: 0.88,
               description: "Maren's old ranch. Orchards, a creaky barn and a training yard gone quiet.",
               objectives: [
                   talk("ch1-pip", "Talk to Pip at the barn", .pip, [
                       say("You must be {keeper}, Maren's new Glyphkeeper! She left in such a hurry…"),
                       say("Something's wrong with the old training dummy. A Lattice spark got into it."),
                       say("And a stray Pebblit has been rolling through the orchard all week."),
                       say("Oh! Maren wanted me to teach you Fusion. Once you have two beasts, open Beast Fusion in the Haven."),
                       say("Two beasts of different lines become a brand-new rookie that keeps a bit of both. Two of the same line become a stronger version of that beast."),
                       say("And Glyphkeepers whisper that certain element pairs, both Lv 15 or more, wake a Mythic. Listen for Fusion Rumors on your travels. I'll write them in your Lattice Archive."),
                   ], choices: [
                       DialogueChoice(text: "Leave it to me.", reply: "Ha! Maren said you'd say that."),
                       DialogueChoice(text: "Where did Maren go?",
                                      reply: "She wouldn't say. Only that the Lattice was \"going quiet.\" She left you this.",
                                      flag: "asked.maren", coinReward: 50),
                   ]),
                   defeat("ch1-pebblit", "Shoo the stray Pebblit from the orchard",
                          name: "Stray Pebblit", species: "pebblit", level: 1),
                   boss(1),
               ]),
        Region(chapter: chapter(2), x: 0.20, y: 0.72,
               description: "A smoldering volcano ringed by a village of glassblowers and fire-beast tamers.",
               objectives: [
                   talk("ch2-brasa", "Speak with Elder Brasa", .brasa, [
                       say("Our beasts have gone wild. Their eyes turn grey, then they rage."),
                       say("A masked figure was seen near the crater. Grey coat, hollow circle on the sleeve."),
                       say("An old Caldera saying: fuse fire with stone, both beasts Lv 15 or more, and the mountain itself walks."),
                       say("Will you help us, {keeper}?"),
                   ], choices: [
                       DialogueChoice(text: "I'll calm the beasts first.",
                                      reply: "A gentle heart. The Caldera will remember that.", flag: "caldera.gentle"),
                       DialogueChoice(text: "I'll hunt down the masked figure.",
                                      reply: "Bold. Be careful — fire bites back.", flag: "caldera.bold"),
                   ]),
                   defeat("ch2-cindrop", "Calm a rampaging Cindrop",
                          name: "Rampaging Cindrop", species: "cindrop", level: 4),
                   boss(2),
               ]),
        Region(chapter: chapter(3), x: 0.80, y: 0.64,
               description: "Sea-glass beaches and singing tide pools — though the singing has stopped.",
               objectives: [
                   talk("ch3-nell", "Ask Nell about the grey sea", .nell, [
                       say("Forty years I've fished this coast. Never seen the water go grey."),
                       say("Some cocky kid with a Tidecrest showed up yesterday. Says he'll fix it himself."),
                       say("Here's a tale for you. Fuse a fire beast with a sea beast, both seasoned ones, and the steam gets a face."),
                   ]),
                   defeat("ch3-ripplet", "Free a grey-tide Ripplet",
                          name: "Grey-tide Ripplet", species: "ripplet", level: 8),
                   talk("ch3-kade", "Confront Kade on the pier", .kade, [
                       say("Maren's apprentice, {keeper}? Figures she'd pick someone slow."),
                       say("This coast is mine. I'm the one who'll find out what's silencing the Lattice."),
                   ], choices: [
                       DialogueChoice(text: "We want the same thing. Work with me.",
                                      reply: "…Maybe. Beat me first, then we'll talk.", flag: "kade.friendly"),
                       DialogueChoice(text: "Stay out of my way.",
                                      reply: "Ha! Now that's a rival. Let's go.", flag: "kade.rival"),
                   ]),
                   boss(3),
               ]),
        Region(chapter: chapter(4), x: 0.42, y: 0.52,
               description: "A maze of ancient trees hiding one of the Lattice's oldest nodes.",
               objectives: [
                   talk("ch4-ivy", "Find Ranger Ivy", .ivy, [
                       say("The Warden Thornback won't let anyone near the node. Not since the Syndicate came."),
                       say("Prove you're no Syndicate thug. The Wilds' beasts will tell it who you are."),
                       say("The Wilds remember a wyrm of leaves and wind. Fuse Verdant and Gale, both past Lv 15, and it's said to return."),
                   ]),
                   defeat("ch4-sproutle", "Earn the trust of a wild Sproutle",
                          name: "Wild Sproutle", species: "sproutle", level: 12),
                   boss(4),
               ]),
        Region(chapter: chapter(5), x: 0.18, y: 0.34,
               description: "Wind-carved peaks where storm-beasts nest — and Syndicate airships circle.",
               objectives: [
                   talk("ch5-wren", "Meet Wren at the courier post", .wren, [
                       say("Vey's airships drain storm-beasts into blank glyphs. Dozens a day."),
                       say("Couriers swear the aurora is a beast: light riding the wind. Lumen and Gale, fused at Lv 15 or more."),
                       say("I can get you aboard the flagship. How do you want to do this?"),
                   ], choices: [
                       DialogueChoice(text: "Quietly. Free the captured beasts first.",
                                      reply: "Smart. I'll show you the cargo hatch.", flag: "sky.stealth"),
                       DialogueChoice(text: "Head-on. Take Vey down.",
                                      reply: "Loud and fast it is. Hold on tight!", flag: "sky.direct"),
                   ]),
                   defeat("ch5-fluffwing", "Rescue a drained Fluffwing",
                          name: "Drained Fluffwing", species: "fluffwing", level: 15),
                   boss(5),
               ]),
        Region(chapter: chapter(6), x: 0.76, y: 0.38,
               description: "A Syndicate quarry dug deep into the hollow. Kade is being held somewhere below.",
               objectives: [
                   talk("ch6-rook", "Meet the deserter, Rook", .rook, [
                       say("I wore the grey coat for three years. I'm done. I know where they keep your friend."),
                       say("The Syndicate dug up a stopped clock down here. Stone that holds shadow. Fuse Terra with Umbra at Lv 15+ and time gets a dragon."),
                       say("You'll have to trust me."),
                   ], choices: [
                       DialogueChoice(text: "I trust you. Lead the way.",
                                      reply: "…Thank you. Nobody's said that to me in a long time.", flag: "rook.trusted"),
                       DialogueChoice(text: "One wrong move and we're done.",
                                      reply: "Fair. I'd say the same.", flag: "rook.doubted"),
                   ]),
                   defeat("ch6-pebblit", "Break through the quarry guard",
                          name: "Quarry Guard Pebblit", species: "pebblit", level: 19),
                   talk("ch6-kade", "Find Kade in the holding cells", .kade, [
                       say("{keeper}, you came. I… didn't think you would.", if: "kade.friendly"),
                       say("Of course it's you. Don't expect me to say thanks.", if: "kade.rival"),
                       say("Their Bouldrake guards the exit. I can't fight it alone — my Tidecrest is exhausted."),
                       you("Then we break out together."),
                   ]),
                   boss(6),
               ]),
        Region(chapter: chapter(7), x: 0.50, y: 0.22,
               description: "A crackling marsh. At its heart, the Null Spire pierces the storm clouds.",
               objectives: [
                   talk("ch7-kade", "Plan the assault with Kade", .kade, [
                       say("Maren founded the Syndicate. I should have told you sooner."),
                       say("Partner, I'm glad it's you up there with me.", if: "kade.friendly"),
                       say("Try to keep up, rival.", if: "kade.rival"),
                       say("Rook got word to the Caldera. Brasa's people are holding the marsh road.", if: "rook.trusted"),
                       say("Marsh folk say lightning striking open water makes a Maelstryx. Tide and Volt, both Lv 15+. I'm fusing one first."),
                   ], choices: [
                       DialogueChoice(text: "We go in together.", reply: "Together, then."),
                       DialogueChoice(text: "Cover me. I'll take the gate.", reply: "Don't get yourself erased."),
                   ]),
                   defeat("ch7-sparkit", "Clear the charged Sparkit swarm",
                          name: "Overcharged Sparkit", species: "sparkit", level: 24),
                   boss(7),
               ]),
        Region(chapter: chapter(8), x: 0.50, y: 0.07,
               description: "A tower of silent glyphs. Every code the Syndicate erased ended up here.",
               objectives: [
                   talk("ch8-maren", "Face Maren at the summit", .maren, [
                       say("I meant to feed the Null until it slept. Instead I woke it."),
                       say("The storm-beasts you freed are weakening it. Thank you.", if: "sky.stealth"),
                       say("Two Umbra beasts, both Lv 15 or more, fused together. That's how I gave the Null a shape. Never do it lightly."),
                       say("I'm sorry I left you with so little, {keeper}."),
                   ], choices: [
                       DialogueChoice(text: "You tried to save them. I forgive you.",
                                      reply: "Then let me help you finish it.", flag: "maren.forgiven"),
                       DialogueChoice(text: "This is your fault.",
                                      reply: "It is. And I'll carry it. But please — stop it.", flag: "maren.blamed"),
                   ]),
                   talk("ch8-kade", "Stand with Kade", .kade, [
                       say("Whatever happens up there, {keeper} — I've got your back.", if: "kade.friendly"),
                       say("Don't you dare lose before I get my rematch.", if: "kade.rival"),
                       say("Maren's with us. Somehow that makes this easier.", if: "maren.forgiven"),
                       say("Let's end what Maren started.", unless: "maren.forgiven"),
                   ]),
                   defeat("ch8-nocturne", "Defeat the Null-touched Nocturne",
                          name: "Null-touched Nocturne", species: "nocturne", level: 32),
                   boss(8),
               ]),
    ]
}
