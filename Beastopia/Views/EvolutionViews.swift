//
//  EvolutionViews.swift
//  Beastopia
//

import SwiftUI

/// One move: element icon, name, and what it does.
struct MoveRow: View {
    let move: Move
    /// Highlights a move the beast gains (or loses) by evolving.
    var badge: String?

    var body: some View {
        HStack(spacing: 10) {
            if let element = move.element {
                GameIcon(art: element.iconArt, symbol: element.symbol, size: 22)
                    .foregroundStyle(element.color)
                    .frame(width: 24)
            } else {
                Image(systemName: move.kind == .guarding ? "shield.fill" : "hand.raised.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(move.name).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let badge {
                Text(badge)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.2), in: .capsule)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        switch move.kind {
        case .guarding: "Halves damage taken · restores Guts"
        case .heal: "Heals · \(move.gutsCost) Guts"
        case .physical, .special: "\(move.kind.rawValue.capitalized) · PWR \(move.power) · ACC \(move.accuracy) · \(move.gutsCost) Guts"
        }
    }
}

/// What an evolution changes: stat gains, new and replaced moves, and field abilities.
/// Used in the Beastdex, the Haven's evolution preview, and after a beast evolves.
struct EvolutionChangesView: View {
    let changes: RanchEngine.EvolutionChanges
    /// Current stats, to show "before → after" for a specific beast instead of species base gains.
    var currentStats: Stats?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !changes.statGains.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stat upgrades").font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(changes.statGains, id: \.stat) { gain in
                        HStack(spacing: 6) {
                            GameIcon(art: gain.stat.iconArt, symbol: gain.stat.symbol, size: 16)
                                .frame(width: 18)
                            Text(gain.stat.shortName).font(.caption.monospaced().bold())
                            Spacer()
                            if let currentStats {
                                Text("\(currentStats[gain.stat]) → \(min(Stats.cap, currentStats[gain.stat] + gain.amount))")
                                    .font(.caption.monospacedDigit())
                            }
                            Text("+\(gain.amount)")
                                .font(.caption.monospacedDigit().bold())
                                .foregroundStyle(.green)
                        }
                    }
                }
            }

            if !changes.newMoves.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("New moves").font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(changes.newMoves) { MoveRow(move: $0, badge: "NEW") }
                    if !changes.replacedMoves.isEmpty {
                        Text("Replaces \(changes.replacedMoves.map(\.name).formatted(.list(type: .and))).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !changes.newAbilities.isEmpty || !changes.lostAbilities.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Field abilities").font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(changes.newAbilities) { ability in
                        abilityLine(ability, text: "Gains \(ability.displayName)", color: .green)
                    }
                    ForEach(changes.lostAbilities) { ability in
                        abilityLine(ability, text: "Loses \(ability.displayName)", color: .orange)
                    }
                }
            }

            if changes.elementChanged {
                Label("Element changes from \(changes.from.element.displayName) to \(changes.to.element.displayName).",
                      systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
            }
            Label("Bond +\(RanchEngine.EvolutionChanges.bondGain)", systemImage: "heart.fill")
                .font(.caption)
                .foregroundStyle(.pink)
        }
        .padding(.vertical, 4)
    }

    private func abilityLine(_ ability: TraversalAbility, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            GameIcon(art: ability.iconArt, symbol: ability.symbol, size: 16)
                .frame(width: 18)
            Text(text).font(.caption.bold()).foregroundStyle(color)
        }
    }
}

/// Beastdex entry: art, lore, stats, moves, field abilities, and the evolutions before and after this form.
struct SpeciesDetailView: View {
    @Environment(GameStore.self) private var store
    let species: Species

    /// The highest base stat of any species, so stat bars compare across the whole Beastdex.
    private static let statScale = SpeciesDatabase.all
        .flatMap { species in StatKind.allCases.map { species.base[$0] } }
        .max() ?? 100

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    BeastPortrait(species: species, size: 128)
                        .modifier(IdleBob())
                    HStack(spacing: 8) {
                        ElementBadge(element: species.element)
                        Text(species.stage.displayName)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.12), in: .capsule)
                    }
                    Text(species.lore)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("Base Stats") {
                ForEach(StatKind.allCases) { kind in
                    HStack(spacing: 6) {
                        GameIcon(art: kind.iconArt, symbol: kind.symbol, size: 16).frame(width: 18)
                        MeterBar(label: kind.shortName, value: species.base[kind], maximum: Self.statScale,
                                 tint: species.element.color)
                    }
                }
                LabeledContent("Total", value: "\(species.base.total)").font(.callout.bold())
            }

            Section("Moves") {
                ForEach(species.moves) { move in
                    MoveRow(move: move, badge: move == species.signature ? "SIGNATURE" : nil)
                }
            }

            Section("Field Abilities") {
                let abilities = TraversalAbility.allCases.filter(species.abilities.contains)
                if abilities.isEmpty {
                    Text("None. It can't carry you across water or walls.").foregroundStyle(.secondary)
                } else {
                    ForEach(abilities) { ability in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ability.displayName).font(.subheadline.bold())
                                Text(ability.summary).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            GameIcon(art: ability.iconArt, symbol: ability.symbol, size: 22)
                        }
                    }
                }
            }

            evolvesFromSection
            evolvesIntoSection
        }
        .menuBackground("menu_bg_beastdex")
        .navigationTitle(species.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var evolvesFromSection: some View {
        if let (parent, path) = RanchEngine.preEvolution(of: species) {
            Section {
                speciesLink(parent, caption: "Evolves at \(RanchEngine.requirementText(path))")
                EvolutionChangesView(changes: RanchEngine.evolutionChanges(from: parent, to: species))
            } header: {
                Text("Before: Evolves From")
            }
        } else if species.stage == .mythic {
            Section("Origin") {
                Text("Created by Beast Fusion: fuse two beasts at level \(RanchEngine.fusionMinimumLevel)+ whose elements are \(species.element.displayName) and \(species.hiddenElement.displayName).")
                    .font(.callout)
            }
        }
    }

    @ViewBuilder
    private var evolvesIntoSection: some View {
        Section {
            if species.evolutions.isEmpty {
                Text("Final form. \(species.name) doesn't evolve further.").foregroundStyle(.secondary)
            } else {
                ForEach(species.evolutions, id: \.self) { path in
                    if let target = SpeciesDatabase.species(path.targetID) {
                        speciesLink(target, caption: "At \(RanchEngine.requirementText(path))")
                        if store.discoveredSpecies.contains(target.id) {
                            EvolutionChangesView(changes: RanchEngine.evolutionChanges(from: species, to: target))
                        } else {
                            Label("A hidden form. Evolve a \(species.name) or meet this beast in battle to reveal it.",
                                  systemImage: "eye.slash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("After: Evolves Into")
        } footer: {
            if species.evolutions.count > 1 {
                Text("Branching evolution: the form it takes depends on its highest stat when it evolves.")
            }
        }
    }

    /// A related species. Undiscovered ones stay a silhouette and can't be opened.
    @ViewBuilder
    private func speciesLink(_ other: Species, caption: String) -> some View {
        let discovered = store.discoveredSpecies.contains(other.id)
        let label = HStack(spacing: 12) {
            BeastPortrait(species: other, isSilhouette: !discovered, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(discovered ? other.name : "???").font(.headline)
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
        }
        if discovered {
            NavigationLink(value: other) { label }
        } else {
            label
        }
    }
}

/// Shown after a beast evolves: the new form and exactly what changed for this beast.
struct EvolutionResultSheet: View {
    @Environment(\.dismiss) private var dismiss
    let beastName: String
    let statsBefore: Stats
    let changes: RanchEngine.EvolutionChanges

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        HStack(spacing: 16) {
                            BeastPortrait(species: changes.from, size: 64).opacity(0.6)
                            Image(systemName: "arrow.right").font(.title2.bold())
                            BeastPortrait(species: changes.to, size: 96)
                                .modifier(IdleBob())
                        }
                        Text("\(beastName) evolved into \(changes.to.name)!")
                            .font(.title3.bold())
                            .multilineTextAlignment(.center)
                        Text(changes.to.lore)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section("What Changed") {
                    EvolutionChangesView(changes: changes, currentStats: statsBefore)
                }
            }
            .menuBackground("menu_bg_main")
            .navigationTitle("Evolution!")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Amazing!") { dismiss() } }
        }
    }
}
