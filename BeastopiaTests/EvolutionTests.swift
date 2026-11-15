//
//  EvolutionTests.swift
//  BeastopiaTests
//

import Testing
@testable import Beastopia

@Suite("Evolution")
struct EvolutionTests {
    @Test("Cindrop → Pyrowl gains Fly and a new signature move")
    func cindropToPyrowl() throws {
        let changes = RanchEngine.evolutionChanges(from: try TestSupport.species("cindrop"),
                                                   to: try TestSupport.species("pyrowl"))
        #expect(changes.newAbilities.contains(.fly))
        #expect(changes.newMoves.contains(changes.to.signature))
        #expect(changes.replacedMoves.contains(changes.from.signature))
        #expect(changes.statGains.allSatisfy { $0.amount > 0 })
    }

    @Test("Evolving applies exactly the previewed stat gains and bond", arguments: ["cindrop", "ripplet", "sproutle"])
    func evolveMatchesPreview(speciesID: String) throws {
        let species = try TestSupport.species(speciesID)
        let path = try #require(species.evolutions.last, "\(speciesID) should evolve")
        var beast = TestSupport.beast(speciesID, level: path.minLevel, bond: max(path.minBond, 10))
        let before = beast
        let target = try #require(beast.availableEvolution)
        let changes = RanchEngine.evolutionChanges(from: species, to: target)

        #expect(RanchEngine.evolve(&beast)?.id == target.id)
        #expect(beast.speciesID == target.id)
        #expect(beast.bond == min(100, before.bond + RanchEngine.EvolutionChanges.bondGain))
        for kind in StatKind.allCases {
            let gain = changes.statGains.first { $0.stat == kind }?.amount ?? 0
            #expect(beast.stats[kind] == before.stats[kind] + gain, "\(kind) should rise by \(gain)")
        }
    }

    @Test("A beast below the level requirement can't evolve")
    func tooLowLevel() throws {
        let path = try #require(try TestSupport.species("ripplet").evolutions.first)
        var beast = TestSupport.beast("ripplet", level: path.minLevel - 1)
        #expect(beast.availableEvolution == nil)
        #expect(RanchEngine.evolve(&beast) == nil)
        #expect(beast.speciesID == "ripplet")
    }

    @Test("Every evolution target exists and points back to its parent")
    func evolutionGraph() throws {
        for species in SpeciesDatabase.all {
            for path in species.evolutions {
                let target = try #require(SpeciesDatabase.species(path.targetID), "\(species.id) → \(path.targetID) is missing")
                #expect(target.stage > species.stage, "\(species.id) should evolve to a later stage")
                #expect(RanchEngine.preEvolution(of: target) != nil)
            }
        }
    }

    @Test("Rookies have no pre-evolution")
    func rookiesAreRoots() {
        for rookie in SpeciesDatabase.rookiePool {
            #expect(RanchEngine.preEvolution(of: rookie) == nil, "\(rookie.id) shouldn't evolve from anything")
        }
    }
}
