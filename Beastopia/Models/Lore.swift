//
//  Lore.swift
//  Beastopia
//

import Foundation

/// A page of the Lattice Archive, the in-game codex of Beastopia's history and secrets.
struct LoreEntry: Identifiable, Sendable {
    enum Unlock: Sendable {
        /// Known from the start.
        case start
        /// Finishing a quest step (stable objective ID from `WorldMap`).
        case objective(String)
        /// Completing a story chapter.
        case chapter(Int)
        /// Claiming the code shown in a YouTube episode.
        case episode(Int)
    }

    enum Category: String, CaseIterable, Sendable {
        case world = "The World"
        case story = "Maren's Journal"
        case episodes = "Episode Archives"
        case fusion = "Fusion Rumors"
    }

    /// Stable, so it's safe to reference from other content.
    let id: String
    let title: String
    let category: Category
    let body: String
    let unlock: Unlock
    /// For Fusion Rumors: the Mythic this rumor points to.
    var mythicID: String? = nil

    /// Shown in place of a locked page, so players know where to look.
    var unlockHint: String {
        switch unlock {
        case .start:
            "Known to every Glyphkeeper."
        case .objective(let id):
            if let objective = WorldMap.regions.flatMap(\.objectives).first(where: { $0.id == id }) {
                "Quest: \(objective.summary)."
            } else {
                "Keep exploring."
            }
        case .chapter(let id):
            "Complete Chapter \(id)."
        case .episode(let number):
            "Scan the code shown in Episode \(number) of the Beastopia series."
        }
    }
}

/// A Beastopia YouTube episode. Each one shows a code on screen that awakens a set beast and
/// unlocks that episode's archive page.
struct Episode: Identifiable, Sendable {
    let number: Int
    let title: String
    /// What viewers type or scan. Matching ignores case, spaces and dashes, so it's easy to type
    /// from a TV or a second screen. Never change a code after its episode airs.
    let code: String
    let speciesID: String
    let rarity: Rarity

    var id: Int { number }
    var originTag: String { "Episode \(number)" }
    var loreID: String { "episode-\(number)" }
    var species: Species? { SpeciesDatabase.species(speciesID) }
}

enum EpisodeCatalog {
    /// Draft line-up. Rename titles and codes to match the real episodes before they air.
    static let episodes: [Episode] = [
        Episode(number: 1, title: "Maren's Last Lesson", code: "EP01-GLYPH-7KQ2",
                speciesID: "prismpup", rarity: .rare),
        Episode(number: 2, title: "The Boy Who Hated Tides", code: "EP02-TIDE-4MZ8",
                speciesID: "puddlepup", rarity: .rare),
        Episode(number: 3, title: "The First Glyphkeepers", code: "EP03-NULL-9RX5",
                speciesID: "gloomkit", rarity: .epic),
    ]

    /// Strips case, spaces, dashes and underscores, so "ep01 glyph 7kq2" matches "EP01-GLYPH-7KQ2".
    static func canonical(_ code: String) -> String {
        code.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    static func episode(matching code: String) -> Episode? {
        let key = canonical(code)
        guard !key.isEmpty else { return nil }
        return episodes.first { canonical($0.code) == key }
    }

    static func episode(number: Int) -> Episode? {
        episodes.first { $0.number == number }
    }
}

enum LoreArchive {
    static func entry(_ id: String) -> LoreEntry? {
        entries.first { $0.id == id }
    }

    static func entries(in category: LoreEntry.Category) -> [LoreEntry] {
        entries.filter { $0.category == category }
    }

    /// Fusion Rumors, one per Mythic. Each is told by an NPC (or an episode) and kept here afterwards.
    static var fusionRumors: [LoreEntry] { entries(in: .fusion) }

    static let entries: [LoreEntry] = world + story + episodeArchives + rumors

    // MARK: - The World

    private static let world: [LoreEntry] = [
        LoreEntry(id: "world-shattering", title: "The Shattering", category: .world, body: """
            Long ago, beasts roamed Beastopia freely. Then something came from beyond the edge of the world: \
            the Null, a hunger with no shape. Wherever it passed, beasts didn't die. They were erased, along \
            with every memory of them. Scholars call that age the Shattering.
            """, unlock: .start),
        LoreEntry(id: "world-lattice", title: "The Codex Lattice", category: .world, body: """
            To hide the beasts from the Null, the first Glyphkeepers wove the Codex Lattice: a net of patterns \
            hidden in every mark the world would ever make. Every barcode and QR glyph is a lock, and a beast \
            sleeps inside each one. The same glyph always holds the same beast, whoever holds the Lens.
            """, unlock: .start),
        LoreEntry(id: "world-glyphkeepers", title: "Glyphkeepers", category: .world, body: """
            A Glyphkeeper carries a Lattice Lens and wakes the beasts sealed in glyphs. Keepers never fight \
            themselves. Their might, wits and agility flow into the beasts they raise, and the bond between \
            keeper and beast is said to be the one thing the Null can't erase.
            """, unlock: .start),
        LoreEntry(id: "world-fusion", title: "The Art of Fusion", category: .world, body: """
            When the first Glyphkeepers ran out of room in the Lattice, they learned to fold two sleeping \
            beasts into one. Fusion still works the same way. Two beasts of different lines become a new rookie \
            carrying a little of each parent. Two beasts of the same line become a stronger version of that \
            beast. And a few element pairings, once both beasts reach Lv 15, wake something that was never \
            sealed at all: a Mythic. Glyphkeepers trade the pairings as rumors. Write down every one you hear.
            """, unlock: .objective("ch1-pip")),
    ]

    // MARK: - Maren's Journal (story chapters)

    private static let story: [LoreEntry] = [
        LoreEntry(id: "journal-1", title: "The Quiet Begins", category: .story, body: """
            "Day 1. A glyph on the barn door used to hum when I passed it. Today it was silent. The Lattice \
            isn't breaking. It's being emptied."
            """, unlock: .chapter(1)),
        LoreEntry(id: "journal-2", title: "Grey Eyes", category: .story, body: """
            "The Caldera beasts' eyes are going grey. A beast whose glyph is drained forgets who it bonded to, \
            and a beast with no bond has only rage left. If anyone asks, I was never here."
            """, unlock: .chapter(2)),
        LoreEntry(id: "journal-3", title: "The Cocky Kid", category: .story, body: """
            "Kade is wasted on stubbornness. He trusts beasts more than people, and he's right to. If my \
            apprentice ever meets him, I hope they're friends. They'll need each other."
            """, unlock: .chapter(3)),
        LoreEntry(id: "journal-4", title: "The Oldest Node", category: .story, body: """
            "Under the Wilds, roots have grown around the first glyph ever carved. The Warden guards it. \
            Every node in the Lattice leads back here, and from here, they lead to the Spire."
            """, unlock: .chapter(4)),
        LoreEntry(id: "journal-5", title: "Blank Glyphs", category: .story, body: """
            "A blank glyph is a lock with no beast inside. Vey's airships fill the sky with them. Every beast \
            pulled out of the Lattice goes somewhere. I'm afraid I know where."
            """, unlock: .chapter(5)),
        LoreEntry(id: "journal-6", title: "The Null Syndicate", category: .story, body: """
            "I founded the Syndicate. I thought that if we fed the Null a little, it would sleep and leave the \
            rest alone. I was wrong. Forgive me, or don't. Just stop them."
            """, unlock: .chapter(6)),
        LoreEntry(id: "journal-7", title: "The Spire Gate", category: .story, body: """
            "The Spire was built as a seal, not a tower. The Thundervex at its gate was the last beast the first \
            Glyphkeepers set to guard it. It isn't evil. It's tired."
            """, unlock: .chapter(7)),
        LoreEntry(id: "journal-8", title: "Oblivyrn", category: .story, body: """
            "The Null took a shape so it could eat faster: Oblivyrn, the Null Wyrm. But a shape can be beaten. \
            And whatever has been beaten can be sealed, and whatever is sealed can be found again."
            """, unlock: .chapter(8)),
    ]

    // MARK: - Episode Archives

    private static let episodeArchives: [LoreEntry] = [
        LoreEntry(id: "episode-1", title: "Maren's Last Lesson", category: .episodes, body: """
            Before she disappeared, Maren taught one last class at the Haven. She held up a cereal box and \
            told her students that everything printed is a promise someone made to the Lattice. Her last \
            words that day: "Thunder needs light to find its way. Remember that when you fuse." No one \
            understood her then.
            """, unlock: .episode(1)),
        LoreEntry(id: "episode-2", title: "The Boy Who Hated Tides", category: .episodes, body: """
            Kade's first beast came from a fishing-net tag on Tidewhisper pier. It was a Puddlepup, not a \
            Tidecrest. He nearly let it go. The pup dragged him out of a grey tide that same week, and he never \
            talked about letting it go again.
            """, unlock: .episode(2)),
        LoreEntry(id: "episode-3", title: "The First Glyphkeepers", category: .episodes, body: """
            There were seven of them, one for each region, and an eighth whose name was scratched from every \
            record. The eighth said beasts should be shut away for good, not just hidden. The Syndicate still \
            keeps the eighth keeper's Lens.
            """, unlock: .episode(3)),
    ]

    // MARK: - Fusion Rumors (one per Mythic)

    private static let rumors: [LoreEntry] = [
        LoreEntry(id: "rumor-magmarch", title: "Fire Married to Stone", category: .fusion, body: """
            Elder Brasa: "When an Ember beast and a Terra beast, both Lv 15 or more, are fused, the mountain \
            itself gets up and walks. We call it Magmarch."
            """, unlock: .objective("ch2-brasa"), mythicID: "magmarch"),
        LoreEntry(id: "rumor-vaporgeist", title: "The Steam Ghost", category: .fusion, body: """
            Nell: "Pour fire into the sea and you get steam. Fuse an Ember beast with a Tide beast, both seasoned \
            ones, and the steam gets a face. Saw it once. Never fished that cove again."
            """, unlock: .objective("ch3-nell"), mythicID: "vaporgeist"),
        LoreEntry(id: "rumor-sylvanwyrm", title: "The Wind in the Leaves", category: .fusion, body: """
            Ranger Ivy: "The Wilds remember a wyrm made of leaves and wind. Fuse Verdant and Gale, both past \
            Lv 15, and it's said to return."
            """, unlock: .objective("ch4-ivy"), mythicID: "sylvanwyrm"),
        LoreEntry(id: "rumor-aurorion", title: "Lights over the Peaks", category: .fusion, body: """
            Wren: "Couriers swear the aurora is a beast. Light carried on the wind: a Lumen and a Gale, both \
            Lv 15 or more, fused together."
            """, unlock: .objective("ch5-wren"), mythicID: "aurorion"),
        LoreEntry(id: "rumor-chronodrake", title: "The Clock Under the Quarry", category: .fusion, body: """
            Rook: "The Syndicate dug up a stopped clock down here. Stone that holds shadow. Fuse a Terra beast \
            with an Umbra beast, both Lv 15+, and time gets a dragon."
            """, unlock: .objective("ch6-rook"), mythicID: "chronodrake"),
        LoreEntry(id: "rumor-maelstryx", title: "Storm at Sea", category: .fusion, body: """
            Kade: "Lightning hitting open water. That's what the marsh folk say a Maelstryx is. Tide and Volt, \
            both Lv 15 or more. I'm going to fuse one first."
            """, unlock: .objective("ch7-kade"), mythicID: "maelstryx"),
        LoreEntry(id: "rumor-halostorm", title: "Thunder Needs Light", category: .fusion, body: """
            From Maren's last lesson: thunder needs light to find its way. Fuse a Volt beast with a Lumen \
            beast, both Lv 15 or more, and a storm with a halo answers.
            """, unlock: .episode(1), mythicID: "halostorm"),
        LoreEntry(id: "rumor-oblivyrn", title: "Darkness Fed to Darkness", category: .fusion, body: """
            Maren: "This is how I made my mistake. Two Umbra beasts, both Lv 15 or more, fused together. \
            Don't do it lightly. What wakes is the shape of the Null itself."
            """, unlock: .objective("ch8-maren"), mythicID: "oblivyrn"),
    ]
}
