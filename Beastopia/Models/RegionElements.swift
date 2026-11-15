//
//  RegionElements.swift
//  Beastopia
//

import Foundation

extension Element {
    /// Elements that deal bonus damage to this one.
    var weakTo: [Element] {
        Element.allCases.filter { $0.strongAgainst.contains(self) }
    }

    /// One line on what this element is like, for region briefings.
    var blurb: String {
        switch self {
        case .ember: "Fire and heat. Ember beasts hit hard with special attacks and can Burn."
        case .tide: "Water and sea. Tide beasts are steady, and every one of them can Swim."
        case .verdant: "Plants and growth. Verdant beasts are tough, hit physically and can Blight."
        case .gale: "Wind and sky. Gale beasts are fast, and every one of them can Fly."
        case .terra: "Stone and earth. Terra beasts have huge Defense and hit physically."
        case .volt: "Lightning. Volt beasts are quick special attackers that can Shock."
        case .lumen: "Light. Lumen beasts can Blink and are the bane of Umbra."
        case .umbra: "Shadow. Umbra beasts can Blink, hit physically and can Blight."
        }
    }
}

/// How a story region uses its element: its mechanic, its boss's weaknesses and its Element Glyph.
struct RegionBriefing {
    let element: Element
    /// The element puzzle, e.g. "Lava Geysers".
    let mechanicTitle: String
    let mechanicText: String
    let bossName: String
    let bossElement: Element
    /// Elements that hit the boss for bonus damage.
    let counters: [Element]
    let glyph: ElementGlyph?

    var strongAgainstText: String { Self.list(element.strongAgainst.sorted { $0.rawValue < $1.rawValue }) }
    var weakToText: String { Self.list(element.weakTo) }
    var countersText: String { Self.list(counters) }

    /// The species waiting in the glyph, e.g. "a Tide beast (Shellbe)".
    var glyphText: String? {
        guard let species = glyph?.species else { return nil }
        return "a \(species.element.displayName) beast (\(species.name))"
    }

    private static func list(_ elements: [Element]) -> String {
        elements.map(\.displayName).formatted(.list(type: .or))
    }
}

extension Region {
    var briefing: RegionBriefing {
        let bossSpecies = SpeciesDatabase.species(chapter.opponentSpeciesID)
        let bossElement = bossSpecies?.element ?? chapter.element
        let (title, text) = Self.mechanic(for: id)
        return RegionBriefing(element: chapter.element, mechanicTitle: title, mechanicText: text,
                              bossName: chapter.opponentName, bossElement: bossElement,
                              counters: bossElement.weakTo, glyph: AdventureMap.map(for: self)?.glyph)
    }

    /// The region's element mechanic, in the player's terms.
    private static func mechanic(for regionID: Int) -> (String, String) {
        switch regionID {
        case 1: ("Bramble Gate",
                 "Thorny brambles seal the training yard. Step on the glowing bloom by the pond and they wither away.")
        case 2: ("Lava Geysers",
                 "Geysers burst across the only gap in the lava river in a rolling wave. Watch the vents and dash through while they're quiet.")
        case 3: ("The Tide",
                 "The sea rises and falls. At low tide a sandbar leads to a little island; at high tide it floods and washes you back, unless a beast can swim you.")
        case 4: ("Thorn Labyrinth",
                 "Brambles seal the path to the Lattice node. Light the blooms in both far corners of the forest to open it.")
        case 5: ("Mountain Winds",
                 "Gusts blow you along in the direction they point, even over the chasm. Ride the updraft to reach the sky island.")
        case 6: ("Quarry Boulders",
                 "Walk into a boulder to push it one tile. Push them out of your way, or into water to fill it in.")
        case 7: ("Lightning Fence",
                 "Arcs of lightning cross the whole marsh, flickering on and off in a wave. Time your crossing or get zapped.")
        case 8: ("The Silent Dark",
                 "The Spire swallows the light. You can only see a little way around you. A Lumen beast in your Haven lights more.")
        default: ("", "")
        }
    }
}
