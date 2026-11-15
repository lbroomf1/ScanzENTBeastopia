//
//  LoreTests.swift
//  BeastopiaTests
//

import Foundation
import Testing
@testable import Beastopia

@Suite("Lore, episode codes and Fusion Rumors")
struct LoreTests {
    @Test("Episode codes ignore case, spaces and dashes, and can only be claimed once")
    func episodeCodeMatching() throws {
        let store = TestSupport.makeStore()
        let episode = try #require(EpisodeCatalog.episodes.first)
        let entry = try #require(LoreArchive.entry(episode.loreID))
        #expect(!store.isUnlocked(entry))

        guard case .discovered(let beast) = store.claim(code: " ep01 glyph_7kq2 ") else {
            Issue.record("A typed episode code should summon the episode's beast")
            return
        }
        #expect(beast.speciesID == episode.speciesID)
        #expect(beast.rarity == episode.rarity)
        #expect(beast.originTag == episode.originTag)
        #expect(store.hasClaimed(episode))
        #expect(store.isUnlocked(entry))

        guard case .alreadyClaimed = store.claim(code: episode.code) else {
            Issue.record("The same episode code typed differently is still the same claim")
            return
        }
    }

    @Test("Ordinary codes still summon by hash")
    func ordinaryCodesUnchanged() {
        #expect(EpisodeCatalog.episode(matching: "0123456789") == nil)
        let beast = BeastGenerator.generate(fromCode: "0123456789")
        #expect(beast.originTag.hasPrefix("#"))
        let again = BeastGenerator.generate(fromCode: "0123456789")
        #expect(beast.speciesID == again.speciesID)
        #expect(beast.stats.total == again.stats.total)
    }

    @Test("Every episode points at a real species and archive page, with a unique code")
    func episodesAreValid() {
        let codes = EpisodeCatalog.episodes.map { EpisodeCatalog.canonical($0.code) }
        #expect(Set(codes).count == codes.count)
        for episode in EpisodeCatalog.episodes {
            #expect(episode.species != nil, "Episode \(episode.number) species")
            #expect(LoreArchive.entry(episode.loreID) != nil, "Episode \(episode.number) lore page")
        }
    }

    @Test("Every Mythic has exactly one Fusion Rumor, and rumors unlock from real quest steps")
    func rumorsCoverMythics() {
        let rumored = LoreArchive.fusionRumors.compactMap(\.mythicID)
        #expect(Set(rumored) == Set(SpeciesDatabase.mythicPool.map(\.id)))
        #expect(rumored.count == SpeciesDatabase.mythicPool.count)

        let objectiveIDs = Set(WorldMap.regions.flatMap(\.objectives).map(\.id))
        for entry in LoreArchive.entries {
            if case .objective(let id) = entry.unlock {
                #expect(objectiveIDs.contains(id), "\(entry.id) unlocks from unknown objective \(id)")
            }
        }
        #expect(Set(LoreArchive.entries.map(\.id)).count == LoreArchive.entries.count)
    }

    @Test("A fresh save knows only the starting world pages")
    func freshSaveLore() {
        let store = TestSupport.makeStore()
        let unlocked = LoreArchive.entries.filter(store.isUnlocked)
        #expect(unlocked.allSatisfy { if case .start = $0.unlock { true } else { false } })
        #expect(!unlocked.isEmpty)
    }
}
