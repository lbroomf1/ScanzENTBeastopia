//
//  BeastdexView.swift
//  Beastopia
//

import SwiftUI

/// Every species in the game. Undiscovered species show as silhouettes; discovered ones open a detail page.
struct BeastdexView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(store.discoveredSpecies.count) of \(SpeciesDatabase.all.count) species discovered")
                        .font(.headline)
                }
                ForEach(Stage.allCases, id: \.self) { stage in
                    Section(stage == .mythic ? "Mythic Beasts" : stage.displayName) {
                        ForEach(SpeciesDatabase.all.filter { $0.stage == stage }) { species in
                            let discovered = store.discoveredSpecies.contains(species.id)
                            if discovered {
                                NavigationLink(value: species) { row(species, discovered: true) }
                            } else {
                                row(species, discovered: false)
                            }
                        }
                    }
                }
            }
            .menuBackground("menu_bg_beastdex")
            .navigationTitle("Beastdex")
            .settingsButton()
            .navigationDestination(for: Species.self) { SpeciesDetailView(species: $0) }
        }
    }

    private func row(_ species: Species, discovered: Bool) -> some View {
        HStack(spacing: 12) {
            BeastPortrait(species: species, isSilhouette: !discovered, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(discovered ? species.name : "???").font(.headline)
                if discovered {
                    ElementBadge(element: species.element)
                    Text(species.lore).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                } else {
                    Text("Not yet discovered").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
