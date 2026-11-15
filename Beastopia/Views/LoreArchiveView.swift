//
//  LoreArchiveView.swift
//  Beastopia
//

import SwiftUI

/// The Lattice Archive: lore pages unlocked by the story, by quest steps and by YouTube episode codes.
struct LoreArchiveView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        List {
            ForEach(LoreEntry.Category.allCases, id: \.self) { category in
                Section {
                    ForEach(LoreArchive.entries(in: category)) { entry in
                        if store.isUnlocked(entry) {
                            NavigationLink {
                                LoreEntryView(entry: entry)
                            } label: {
                                row(entry, unlocked: true)
                            }
                        } else {
                            row(entry, unlocked: false)
                        }
                    }
                } header: {
                    Text(category.rawValue)
                } footer: {
                    footer(for: category)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .menuBackground("menu_bg_main")
        .navigationTitle("Lattice Archive")
    }

    private func row(_ entry: LoreEntry, unlocked: Bool) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(unlocked ? entry.title : "???").font(.headline)
                if !unlocked {
                    Text(entry.unlockHint).font(.caption).foregroundStyle(.secondary)
                } else if let mythicID = entry.mythicID, store.discoveredSpecies.contains(mythicID),
                          let mythic = SpeciesDatabase.species(mythicID) {
                    Text("Solved: \(mythic.name)").font(.caption.bold()).foregroundStyle(.green)
                }
            }
        } icon: {
            Image(systemName: unlocked ? symbol(for: entry.category) : "lock.fill")
                .foregroundStyle(unlocked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .accessibilityElement(children: .combine)
    }

    private func symbol(for category: LoreEntry.Category) -> String {
        switch category {
        case .world: "globe.europe.africa.fill"
        case .story: "book.closed.fill"
        case .episodes: "play.rectangle.fill"
        case .fusion: "arrow.triangle.merge"
        }
    }

    @ViewBuilder
    private func footer(for category: LoreEntry.Category) -> some View {
        switch category {
        case .episodes:
            Text("Each Beastopia episode on YouTube shows a code. Scan it or type it on the Scan tab to awaken that episode's beast and unlock its page.")
        case .fusion:
            Text("Rumors point to Mythic fusions. Both beasts must be Lv \(RanchEngine.fusionMinimumLevel) or higher.")
        default:
            EmptyView()
        }
    }
}

struct LoreEntryView: View {
    let entry: LoreEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(entry.category.rawValue.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(entry.title).font(.largeTitle.bold())
                Text(entry.body).font(.body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .menuBackground("menu_bg_main")
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        LoreArchiveView()
    }
    .environment(GameStore())
}
