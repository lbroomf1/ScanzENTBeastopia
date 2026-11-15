//
//  QuestGuideView.swift
//  Beastopia
//

import SwiftUI

/// Mission help for the current quest step: a clue, battle preparation and a path to follow.
struct QuestGuideSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let region: Region
    let map: AdventureMap
    let objective: Objective?
    /// Close the guide and light a breadcrumb trail to the target.
    let onShowPath: () -> Void

    private var remainingTreasure: [Treasure] {
        map.treasures.filter { !store.openedChests.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let objective {
                    Section("Current Step") {
                        Label(objective.summary, systemImage: "flag.fill")
                            .font(.headline)
                        Label(QuestGuide.clue(for: objective), systemImage: "lightbulb.fill")
                            .font(.callout)
                        Button("Show Me the Way", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill") {
                            SoundFX.play(.tap)
                            onShowPath()
                        }
                        .font(.headline)
                    }

                    let advice = QuestGuide.battleAdvice(for: objective, in: region, partner: store.partner)
                    if !advice.isEmpty {
                        Section("Battle Prep") {
                            ForEach(advice, id: \.self) { tip in
                                Label(tip, systemImage: "shield.lefthalf.filled").font(.callout)
                            }
                            let healing = [ItemKind.berry, .potion, .fullElixir].map(store.count(of:)).reduce(0, +)
                            Label(healing == 0 ? "You have no healing items. Visit a Market first."
                                               : "You're carrying \(healing) healing item\(healing == 1 ? "" : "s").",
                                  systemImage: "cross.vial.fill")
                                .font(.callout)
                                .foregroundStyle(healing == 0 ? .orange : .secondary)
                        }
                    }
                } else {
                    Section {
                        Label("This region is at peace. Explore freely, hunt for treasure, and battle wild beasts in the tall grass.",
                              systemImage: "checkmark.seal.fill")
                    }
                }

                Section {
                    if remainingTreasure.isEmpty {
                        Label("You've found every treasure here.", systemImage: "shippingbox")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(remainingTreasure) { treasure in
                            Label(hint(for: treasure), systemImage: "shippingbox.fill")
                                .font(.callout)
                                .foregroundStyle(canReach(treasure) ? .primary : .secondary)
                        }
                    }
                } header: {
                    Text("Treasure (\(map.treasures.count - remainingTreasure.count)/\(map.treasures.count))")
                }

                Section("Field Abilities") {
                    ForEach(TraversalAbility.allCases) { AbilityRow(ability: $0) }
                }
            }
            .navigationTitle(region.chapter.region)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }

    private func canReach(_ treasure: Treasure) -> Bool {
        treasure.requires.map(store.fieldAbilities.contains) ?? true
    }

    private func hint(for treasure: Treasure) -> String {
        let water = map.theme.waterName
        switch treasure.requires {
        case nil: return "A chest lies hidden somewhere you can walk to."
        case .swim: return canReach(treasure) ? "A chest glints out in the \(water). Swim to it!"
                                              : "A chest glints out in the \(water). You'll need a beast that can swim."
        case .fly: return canReach(treasure) ? "A chest sits over the \(water). Fly to it!"
                                             : "A chest sits over the \(water). You'll need a beast that can fly."
        case .teleport: return canReach(treasure) ? "A chest is walled in. Blink through to reach it."
                                                  : "A chest is walled in. Only a teleporting beast can reach it."
        }
    }
}
