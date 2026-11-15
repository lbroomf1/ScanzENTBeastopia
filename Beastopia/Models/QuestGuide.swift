//
//  QuestGuide.swift
//  Beastopia
//

import Foundation

/// Mission help: hand-written clues for every quest step, plus battle preparation advice.
enum QuestGuide {
    /// Where to look and what to do, keyed by objective ID.
    private static let clues: [String: String] = [
        "ch1-pip": "Pip tends the big red barn in the north-east corner. Follow the path up from the gate.",
        "ch1-pebblit": "The orchard in the north-west is thick with tall grass. Walk through it until the Pebblit rolls out.",
        "ch1-boss": "The possessed dummy waits inside the fenced training yard on the east side. The gap in the fence is on its west wall, sealed by brambles: step on the glowing bloom by the pond to open it.",
        "ch2-brasa": "Elder Brasa sits in the village square just west of the main road, near the glass workshops.",
        "ch2-cindrop": "Rampaging Cindrops prowl the ember fields on either side of the lava river.",
        "ch2-boss": "The Magmaw rages in the crater at the very top of the volcano. Take the central road north. Geysers erupt across the gap in the lava river, so cross while they're quiet.",
        "ch3-nell": "Nell mends nets by the fishing huts on the west side of the beach.",
        "ch3-ripplet": "Grey-tide Ripplets hide in the dune grass along the shoreline.",
        "ch3-kade": "Kade is waiting at the foot of the long pier, staring out to sea.",
        "ch3-boss": "Walk to the far end of the pier. Kade's Tidecrest waits where the boards meet open water.",
        "ch4-ivy": "Ranger Ivy keeps watch in the south-west of the labyrinth, near the entrance.",
        "ch4-sproutle": "Wild Sproutles nest in the band of tall grass that cuts across the middle of the forest.",
        "ch4-boss": "The Warden Thornback guards the clearing before the Lattice node. Follow the central path north. Brambles seal it until you light the blooms in the far top-left and top-right corners.",
        "ch5-wren": "Wren runs the courier hut beside the trailhead at the bottom of the peaks.",
        "ch5-fluffwing": "Drained Fluffwings shiver in the snowdrifts on the ledges either side of the chasm.",
        "ch5-boss": "Climb the left or right ledges around the chasm, then take the path up to the airship dock.",
        "ch6-rook": "Rook is hiding in the rubble just west of the quarry entrance.",
        "ch6-pebblit": "The quarry guard patrols the rubble fields at the south end of the hollow.",
        "ch6-kade": "The holding cells are the grey blocks in the middle of the quarry. Kade is in the right-hand row.",
        "ch6-boss": "The Bouldrake blocks the exit tunnel at the top of the quarry, past the flooded pits.",
        "ch7-kade": "Kade is camped by the old huts in the south-west of the marsh.",
        "ch7-sparkit": "The overcharged swarm crackles in the reed beds all over the marsh.",
        "ch7-boss": "The Spire Gate is at the top of the marsh. Follow the dry ground between the bog pools, and cross the lightning fence while the arcs in front of you are dark.",
        "ch8-maren": "Maren waits on the summit platform, to the left of the stairs.",
        "ch8-kade": "Kade stands on the summit platform, to the right of the stairs.",
        "ch8-nocturne": "The Null-touched Nocturne stalks the purple glyph-grass on the Spire's floating ledges.",
        "ch8-boss": "Oblivyrn coils at the very top of the Spire, beyond Maren and Kade.",
    ]

    static func clue(for objective: Objective) -> String {
        if let clue = clues[objective.id] { return clue }
        switch objective.kind {
        case let .talk(npc, _): return "Find \(npc.name) somewhere in this region."
        case .defeat: return "Search the tall grass."
        case .boss: return "The region's boss awaits."
        }
    }

    /// The beast you'll fight for this step, if it's a battle.
    static func opponent(for objective: Objective, in region: Region) -> (name: String, species: Species, level: Int)? {
        switch objective.kind {
        case .talk:
            return nil
        case let .defeat(encounter):
            guard let species = SpeciesDatabase.species(encounter.speciesID) else { return nil }
            return (encounter.name, species, encounter.level)
        case .boss:
            let chapter = region.chapter
            guard let species = SpeciesDatabase.species(chapter.opponentSpeciesID) else { return nil }
            return (chapter.opponentName, species, chapter.opponentLevel)
        }
    }

    /// Battle prep: which elements hit the opponent hard, and whether your beast is ready.
    static func battleAdvice(for objective: Objective, in region: Region, partner: Beast?) -> [String] {
        guard let foe = opponent(for: objective, in: region) else { return [] }
        var advice: [String] = []
        let strong = Element.allCases.filter { $0.strongAgainst.contains(foe.species.element) }
        let names = strong.map(\.displayName).joined(separator: " or ")
        advice.append("\(foe.name) is a Lv \(foe.level) \(foe.species.element.displayName) beast."
                      + (names.isEmpty ? "" : " \(names) moves hit it hard."))
        let risky = foe.species.element.strongAgainst.map(\.displayName).sorted().joined(separator: " and ")
        advice.append("Its \(foe.species.element.displayName) attacks are strong against \(risky) beasts.")

        if let partner {
            let gap = foe.level - partner.level
            if gap >= 4 {
                advice.append("\(partner.displayName) is Lv \(partner.level) — that's \(gap) levels behind. Train in the Haven, use Lattice Candy, or battle wild beasts in tall grass first.")
            } else if gap > 0 {
                advice.append("\(partner.displayName) is slightly under-leveled. Bring Glow Berries or a Healing Draught.")
            } else {
                advice.append("\(partner.displayName) (Lv \(partner.level)) is ready for this fight.")
            }
            if strong.contains(partner.species.element) {
                advice.append("Good matchup: \(partner.displayName)'s \(partner.species.element.displayName) moves are super effective here.")
            }
            if partner.fatigue >= 60 {
                advice.append("\(partner.displayName) is tired. Rest at a Stable or Campfire for better training gains.")
            }
        }
        return advice
    }
}
