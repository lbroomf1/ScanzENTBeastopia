//
//  HavenView.swift
//  Beastopia
//

import SwiftUI

/// Beast Haven: the player's ranch, where beasts are trained, upgraded, evolved and fused.
struct HavenView: View {
    @Environment(GameStore.self) private var store
    @State private var showFusion = false
    /// Set once the player has opened Fusion or dismissed the tip, so the tip card goes away.
    @AppStorage("haven.fusionTipSeen") private var fusionTipSeen = false
    @State private var showPrimaryPicker = false

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                KeeperBanner()
                    .padding(.top, 4)

                if store.beasts.isEmpty {
                    ContentUnavailableView("Your Haven Is Quiet",
                                           systemImage: "pawprint",
                                           description: Text("Head to the Scan tab and scan any barcode or QR code to awaken your first beast."))
                        .padding(.top, 80)
                } else {
                    HStack {
                        CurrencyBar()
                        Spacer()
                        Text("\(store.beasts.count)/\(store.havenCapacity) beasts")
                    }
                    .font(.subheadline.bold())
                    .padding(.horizontal)

                    if let primary = store.partner {
                        primaryBanner(primary)
                    }

                    ForEach(store.readyToEvolve) { beast in
                        evolveBanner(beast)
                    }

                    if store.beasts.count >= 2 && !fusionTipSeen {
                        fusionTip
                    }

                    HavenGrounds()
                        .padding(.vertical, 4)

                    Text("Tap a beast to train, upgrade or evolve it. Long-press to set it as your primary.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(store.beasts) { beast in
                            NavigationLink(value: beast.id) {
                                BeastCard(beast: beast,
                                          isPrimary: beast.id == store.partner?.id,
                                          hasDuplicate: !store.duplicates(of: beast.id).isEmpty)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Set as Primary", systemImage: "star") {
                                    store.setPrimary(beast.id)
                                    SoundFX.play(.primary)
                                }
                                .disabled(beast.id == store.partner?.id)
                            }
                        }
                    }
                    .padding()
                }
            }
            .menuBackground("haven_background", scrim: 0.35)
            .navigationTitle("Beast Haven")
            .navigationDestination(for: UUID.self) { id in
                BeastDetailView(beastID: id)
            }
            .settingsButton()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Beast Fusion", systemImage: "arrow.triangle.merge") {
                        fusionTipSeen = true
                        showFusion = true
                    }
                    .disabled(store.beasts.count < 2)
                }
            }
            .sheet(isPresented: $showFusion) { FusionView() }
            .sheet(isPresented: $showPrimaryPicker) { PrimaryBeastPicker() }
        }
    }

    /// Teaches Fusion the first time the player has two beasts, since the toolbar button is easy to miss.
    private var fusionTip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("You can fuse beasts!", systemImage: "arrow.triangle.merge")
                .font(.headline)
            Text("Combine two beasts into one. Different lines make a new rookie with a share of both parents' stats. Two beasts of the same line make a stronger version of that beast. Some element pairs at Lv \(RanchEngine.fusionMinimumLevel)+ wake a Mythic.")
                .font(.callout)
            HStack {
                Button("Try Fusion") {
                    fusionTipSeen = true
                    showFusion = true
                }
                .buttonStyle(.borderedProminent)
                Button("Got It") { fusionTipSeen = true }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .gamePanel(tint: .teal)
        .padding(.horizontal)
    }

    private func primaryBanner(_ beast: Beast) -> some View {
        HStack(spacing: 12) {
            BeastPortrait(beast: beast, size: 56, isAnimated: true)
            VStack(alignment: .leading, spacing: 2) {
                Label("Primary Beast", systemImage: "star.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.yellow)
                Text(beast.displayName).font(.headline)
                Text("Lv \(beast.level) · Leads your adventures and battles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Change") {
                SoundFX.play(.tap)
                showPrimaryPicker = true
            }
            .buttonStyle(.bordered)
            .disabled(store.beasts.count < 2)
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    /// A glowing call-out for a beast that can evolve right now. Tapping it opens the beast's page.
    private func evolveBanner(_ beast: Beast) -> some View {
        NavigationLink(value: beast.id) {
            HStack(spacing: 12) {
                BeastPortrait(beast: beast, size: 48)
                    .modifier(IdleBob())
                VStack(alignment: .leading, spacing: 2) {
                    Label("Ready to Evolve!", systemImage: "sparkles")
                        .font(.caption.bold())
                        .foregroundStyle(GameTheme.gold)
                    Text(beast.displayName).font(.headline)
                    Text("Tap to see its next form")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.headline).foregroundStyle(GameTheme.gold)
            }
            .padding(12)
            .gamePanel(cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

/// Sheet for choosing which beast leads the team.
struct PrimaryBeastPicker: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(store.beasts) { beast in
                Button {
                    store.setPrimary(beast.id)
                    SoundFX.play(.primary)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        BeastPortrait(beast: beast, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(beast.displayName).font(.headline)
                            Text("Lv \(beast.level) · \(beast.species.stage.displayName) · \(beast.species.element.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if beast.id == store.partner?.id {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                                .accessibilityLabel("Current primary")
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Choose Primary Beast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct BeastCard: View {
    let beast: Beast
    var isPrimary = false
    var hasDuplicate = false

    var body: some View {
        VStack(spacing: 6) {
            BeastPortrait(beast: beast, size: 80)
            Text(beast.displayName).font(.headline).lineLimit(1)
            Text("Lv \(beast.level) · \(beast.species.stage.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            if isPrimary {
                Image(systemName: "star.fill").foregroundStyle(.yellow).padding(8)
                    .accessibilityLabel("Primary beast")
            }
        }
        .overlay(alignment: .topLeading) {
            VStack(spacing: 4) {
                if beast.availableEvolution != nil {
                    Image(systemName: "sparkles").foregroundStyle(.orange)
                        .accessibilityLabel("Ready to evolve")
                }
                if hasDuplicate {
                    Image(systemName: "square.on.square.fill").foregroundStyle(.teal)
                        .accessibilityLabel("Has a duplicate")
                }
            }
            .padding(8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(beast.rarity.color.opacity(0.6), lineWidth: 2)
        }
    }
}

// MARK: - Detail

struct BeastDetailView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let beastID: UUID

    /// Actions that permanently remove a beast and need confirming first.
    private enum PendingAction {
        case absorb(donor: Beast, target: Beast)
        case sell(Beast)
        case release(Beast)
    }

    @State private var feedback: String?
    @State private var evolution: EvolutionResult?

    /// A finished evolution, for the "what changed" sheet.
    private struct EvolutionResult: Identifiable {
        let id = UUID()
        let statsBefore: Stats
        let changes: RanchEngine.EvolutionChanges
    }
    @State private var pending: PendingAction?

    var body: some View {
        if let beast = store.beast(beastID) {
            content(beast)
        } else {
            ContentUnavailableView("Beast not found", systemImage: "questionmark")
        }
    }

    private func content(_ beast: Beast) -> some View {
        List {
            Section {
                VStack(spacing: 10) {
                    BeastPortrait(beast: beast, size: 160)
                    Text(beast.species.name).font(.title.bold())
                    HStack {
                        ElementBadge(element: beast.species.element)
                        if beast.isHiddenElementRevealed {
                            ElementBadge(element: beast.species.hiddenElement, hidden: true)
                        }
                        RarityBadge(rarity: beast.rarity)
                    }
                    Text(beast.trait.summary).font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            // A beast that can evolve shows it first, so it's never buried below training.
            if beast.availableEvolution != nil {
                evolutionSection(beast)
            }

            Section("Nickname") {
                TextField(beast.species.name, text: Binding(
                    get: { beast.nickname },
                    set: { name in store.update(beastID) { $0.nickname = String(name.prefix(20)) } }
                ))
            }

            Section("Condition") {
                MeterBar(label: "LV \(beast.level)", value: beast.xp, maximum: beast.xpToNextLevel, tint: .blue)
                MeterBar(label: "BOND", value: beast.bond, maximum: 100, tint: .pink)
                MeterBar(label: "TIRE", value: beast.fatigue, maximum: 100, tint: beast.fatigue >= 80 ? .red : .orange)
                if !beast.isHiddenElementRevealed {
                    Text("Raise bond to 30 to reveal its hidden element.").font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Record", value: "\(beast.wins)W – \(beast.losses)L")
            }

            Section("Stats") {
                ForEach(StatKind.allCases) { kind in
                    MeterBar(label: kind.shortName, value: beast.stats[kind], maximum: Stats.cap, tint: beast.species.element.color)
                }
            }

            Section("Training Grounds") {
                ForEach(StatKind.allCases) { kind in
                    Button {
                        var result: RanchEngine.TrainingResult?
                        store.update(beastID) { result = RanchEngine.train(&$0, stat: kind) }
                        if let result {
                            feedback = result.message + (result.levelsGained > 0 ? " · Level up!" : "")
                            SoundFX.play(result.levelsGained > 0 ? .levelUp : .train)
                        }
                    } label: {
                        GameLabel(kind.drillName, art: kind.iconArt, symbol: kind.symbol)
                    }
                }
                Button("Feed", systemImage: "carrot.fill") {
                    store.update(beastID) { RanchEngine.feed(&$0) }
                    feedback = "\(beast.displayName) happily munches away."
                    SoundFX.play(.feed)
                }
                Button("Rest", systemImage: "bed.double.fill") {
                    store.update(beastID) { RanchEngine.rest(&$0) }
                    feedback = "\(beast.displayName) takes a long nap."
                    SoundFX.play(.rest)
                }
            }

            itemsSection(beast)

            upgradesSection(beast)

            if beast.availableEvolution == nil {
                evolutionSection(beast)
            }

            duplicatesSection(beast)

            Section("Moves") {
                ForEach(beast.species.moves) { move in
                    LabeledContent(move.name) {
                        Text(move.kind == .guarding ? "Guard" : "PWR \(move.power) · \(move.gutsCost) Guts")
                    }
                }
            }

            Section("Lore") {
                Text(beast.species.lore)
                LabeledContent("Found in glyph", value: beast.originTag)
            }

            Section {
                Button("Set as Primary Beast", systemImage: "star") {
                    store.setPrimary(beastID)
                    feedback = "\(beast.displayName) now leads your team!"
                    SoundFX.play(.primary)
                }
                .disabled(store.partner?.id == beastID)
                Menu {
                    ForEach(store.beasts.filter { $0.id != beastID }) { other in
                        Button("\(other.displayName) (Lv \(other.level))") {
                            pending = .absorb(donor: beast, target: other)
                        }
                    }
                } label: {
                    Label("Absorb into Another Beast", systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .disabled(store.beasts.count < 2)
                Button {
                    pending = .sell(beast)
                } label: {
                    GameLabel("Sell for \(RanchEngine.sellValue(of: beast)) Coins", art: GameArt.coinIcon, symbol: "circle.hexagongrid.fill")
                }
                Button("Release", systemImage: "leaf", role: .destructive) { pending = .release(beast) }
            } footer: {
                Text("Absorbing passes on XP — doubled, plus 10% of its stats, when absorbed into the same evolution line.")
            }
        }
        .pixelToast($feedback, tint: beast.species.element.color)
        .navigationTitle(beast.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(confirmationTitle, isPresented: Binding(
            get: { pending != nil },
            set: { if !$0 { pending = nil } }
        ), titleVisibility: .visible) {
            confirmationButton
        }
        .sheet(item: $evolution) { result in
            EvolutionResultSheet(beastName: beast.displayName, statsBefore: result.statsBefore, changes: result.changes)
        }
    }

    // MARK: Items

    @ViewBuilder
    private func itemsSection(_ beast: Beast) -> some View {
        let owned = ItemKind.fieldItems.filter { store.count(of: $0) > 0 }
        if !owned.isEmpty {
            Section("Items") {
                ForEach(owned) { item in
                    Button {
                        guard let levels = store.use(item, on: beastID) else { return }
                        feedback = levels > 0 ? "\(beast.displayName) grew to Lv \(beast.level + levels)!"
                                              : "\(beast.displayName) enjoyed the \(item.name)."
                        SoundFX.play(levels > 0 ? .levelUp : .feed)
                    } label: {
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                    Text(item.summary).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                GameIcon(art: item.iconArt, symbol: item.symbol, size: 28).foregroundStyle(item.color)
                            }
                            Spacer()
                            Text("×\(store.count(of: item))").font(.callout.monospacedDigit().bold())
                        }
                    }
                    .disabled(!item.isUsefulInField(for: beast))
                }
            }
        }
    }

    // MARK: Upgrades

    private func upgradesSection(_ beast: Beast) -> some View {
        Section {
            ForEach(RanchEngine.Upgrade.allCases) { upgrade in
                let cost = upgrade.cost(for: beast)
                Button {
                    buy(upgrade, for: beast)
                } label: {
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(upgrade.name)
                                Text(upgrade.summary).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: upgrade.symbol)
                        }
                        Spacer()
                        GameLabel("\(cost)", art: GameArt.coinIcon, symbol: "circle.hexagongrid.fill")
                            .font(.callout.monospacedDigit().bold())
                            .foregroundStyle(store.coins >= cost ? Color.primary : Color.red)
                    }
                }
                .disabled(!upgrade.isUseful(for: beast))
            }
        } header: {
            Text("Haven Upgrades")
        } footer: {
            Text("You have \(store.coins) coins. Earn more by winning battles, finishing chapters and selling spare beasts.")
        }
    }

    private func buy(_ upgrade: RanchEngine.Upgrade, for beast: Beast) {
        guard let levels = store.purchase(upgrade, for: beastID) else {
            feedback = "Not enough coins for \(upgrade.name)."
            SoundFX.play(.denied)
            return
        }
        if levels > 0 {
            feedback = "\(beast.displayName) grew to Lv \(beast.level + levels)!"
            SoundFX.play(.levelUp)
        } else {
            feedback = "\(beast.displayName) enjoys the \(upgrade.name)."
            SoundFX.play(.purchase)
        }
    }

    // MARK: Duplicates

    @ViewBuilder
    private func duplicatesSection(_ beast: Beast) -> some View {
        let duplicates = store.duplicates(of: beastID)
        if !duplicates.isEmpty {
            Section {
                ForEach(duplicates) { duplicate in
                    HStack {
                        BeastPortrait(beast: duplicate, size: 40)
                        VStack(alignment: .leading) {
                            Text(duplicate.displayName).font(.headline)
                            Text("Lv \(duplicate.level) · +\(RanchEngine.absorbXP(of: duplicate) * 2) XP")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Absorb") { pending = .absorb(donor: duplicate, target: beast) }
                            .buttonStyle(.bordered)
                    }
                }
            } header: {
                Text("Duplicates")
            } footer: {
                Text("Keep duplicates to fuse them, absorb them here to power up \(beast.displayName), or sell them for coins.")
            }
        }
    }

    // MARK: Confirmation

    private var confirmationTitle: String {
        switch pending {
        case .absorb(let donor, let target): "Absorb \(donor.displayName) into \(target.displayName)? \(donor.displayName) returns to the Lattice."
        case .sell(let beast): "Sell \(beast.displayName) for \(RanchEngine.sellValue(of: beast)) coins?"
        case .release(let beast): "Release \(beast.displayName) back into the Lattice?"
        case nil: ""
        }
    }

    @ViewBuilder
    private var confirmationButton: some View {
        switch pending {
        case .absorb(let donor, let target):
            Button("Absorb", role: .destructive) {
                guard let levels = store.absorb(donor.id, into: target.id) else { return }
                SoundFX.play(levels > 0 ? .levelUp : .fuse)
                if donor.id == beastID {
                    dismiss()
                } else {
                    feedback = "\(target.displayName) absorbed \(donor.displayName)" + (levels > 0 ? " · Level up!" : "!")
                }
            }
        case .sell(let beast):
            Button("Sell", role: .destructive) {
                guard store.sell(beast.id) != nil else { return }
                SoundFX.play(.purchase)
                dismiss()
            }
        case .release(let beast):
            Button("Release", role: .destructive) {
                store.release(beast.id)
                SoundFX.play(.release)
                dismiss()
            }
        case nil:
            EmptyView()
        }
    }

    /// Evolve button and preview when ready; otherwise what each evolution needs. Forms the keeper
    /// hasn't discovered stay a silhouette named "???" until they evolve into it or meet it in battle.
    private func evolutionSection(_ beast: Beast) -> some View {
        Section {
            if let target = beast.availableEvolution {
                let known = store.discoveredSpecies.contains(target.id)
                HStack(spacing: 12) {
                    BeastPortrait(species: target, isSilhouette: !known, size: 56)
                        .modifier(IdleBob())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(beast.displayName) is ready to evolve!").font(.headline)
                        Text(known ? "It will become \(target.name)." : "Into a form you haven't discovered yet...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button(known ? "Evolve into \(target.name)!" : "Evolve!", systemImage: "sparkles") {
                    let before = beast.stats
                    let changes = RanchEngine.evolutionChanges(from: beast.species, to: target)
                    store.update(beastID) { RanchEngine.evolve(&$0) }
                    evolution = EvolutionResult(statsBefore: before, changes: changes)
                    if !MusicPlayer.shared.playSting("sting_evolve") { SoundFX.play(.evolve) }
                }
                .buttonStyle(GameButtonStyle())
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                if known {
                    EvolutionChangesView(changes: RanchEngine.evolutionChanges(from: beast.species, to: target),
                                         currentStats: beast.stats)
                }
            } else if beast.species.evolutions.isEmpty {
                Text("\(beast.species.name) has reached its final form.").foregroundStyle(.secondary)
            } else {
                // Not ready yet: show what each evolution needs, what's still missing, and what it would bring.
                ForEach(beast.species.evolutions, id: \.self) { path in
                    if let target = SpeciesDatabase.species(path.targetID) {
                        let known = store.discoveredSpecies.contains(target.id)
                        DisclosureGroup {
                            if known {
                                EvolutionChangesView(changes: RanchEngine.evolutionChanges(from: beast.species, to: target),
                                                     currentStats: beast.stats)
                            } else {
                                Text("A hidden form. Evolve into it or meet it in battle to see what changes.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                BeastPortrait(species: target, isSilhouette: !known, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("→ \(known ? target.name : "???"): \(RanchEngine.requirementText(path))")
                                        .font(.callout)
                                    if let missing = missingText(beast, path) {
                                        Text(missing).font(.caption).foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Evolution")
        }
    }

    /// What a beast still lacks for an evolution path, e.g. "Needs 3 more levels · Bond 12/40".
    private func missingText(_ beast: Beast, _ path: EvolutionPath) -> String? {
        var parts: [String] = []
        if beast.level < path.minLevel {
            let levels = path.minLevel - beast.level
            parts.append("Needs \(levels) more level\(levels == 1 ? "" : "s")")
        }
        if beast.bond < path.minBond { parts.append("Bond \(beast.bond)/\(path.minBond)") }
        if let stat = path.dominantStat, beast.stats.dominant != stat {
            parts.append("Train \(stat.shortName) until it's the highest stat")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Fusion

struct FusionView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var first: UUID?
    @State private var second: UUID?
    @State private var result: Beast?
    /// The two parents of the last fusion, so a Mythic's cutscene can show them merging.
    @State private var fusedParents: [Beast] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FusionGuide()
                        .padding(.horizontal)

                    Text("First parent").font(.headline).padding(.horizontal)
                    BeastPicker(selection: $first, excluding: Set([second].compactMap { $0 }))
                    Text("Second parent").font(.headline).padding(.horizontal)
                    BeastPicker(selection: $second, excluding: Set([first].compactMap { $0 }))

                    if let a = first.flatMap(store.beast), let b = second.flatMap(store.beast),
                       let mythic = RanchEngine.mythicRecipe(a, b) {
                        Label("The Lattice resonates… \(mythic.name) stirs!", systemImage: "sparkles")
                            .font(.headline)
                            .foregroundStyle(.orange)
                            .padding(.horizontal)
                    } else if let a = first.flatMap(store.beast), let b = second.flatMap(store.beast),
                              RanchEngine.isBloodlineFusion(a, b) {
                        let lead = (a.species.stage, a.level) >= (b.species.stage, b.level) ? a : b
                        Label("Bloodline fusion: becomes a stronger \(lead.species.name), Lv \(max(a.level, b.level))+, keeping the best of both.",
                              systemImage: "link")
                            .font(.headline)
                            .foregroundStyle(.teal)
                            .padding(.horizontal)
                    } else if let a = first.flatMap(store.beast), let b = second.flatMap(store.beast) {
                        let child = RanchEngine.freshFusionSpecies(a, b)
                        Label("New line: becomes a fresh \(child.element.displayName) rookie, \(child.name), carrying 15% of both parents' stats.",
                              systemImage: "arrow.triangle.merge")
                            .font(.headline)
                            .padding(.horizontal)
                    }

                    Button("Fuse") {
                        if let first, let second {
                            SoundFX.play(.fuse)
                            fusedParents = [first, second].compactMap(store.beast)
                            result = store.fuse(first, second)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(first == nil || second == nil)

                    FusionRumorList()
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Beast Fusion")
            .toolbar {
                Button("Done") { dismiss() }
            }
            .sheet(item: $result, onDismiss: { dismiss() }) { beast in
                SummonRevealView(beast: beast, parents: fusedParents)
            }
        }
    }
}

/// Explains the three kinds of fusion and their rules.
struct FusionGuide: View {
    var body: some View {
        DisclosureGroup("How Fusion works") {
            VStack(alignment: .leading, spacing: 10) {
                Label("**Different lines:** a new rookie of the stronger parent's element, carrying 15% of both parents' stats. Bond starts at 20.",
                      systemImage: "arrow.triangle.merge")
                Label("**Same line (Bloodline):** keeps the more evolved form and higher level, takes the best of each stat, and may rise in rarity.",
                      systemImage: "link")
                Label("**Mythic:** certain element pairs, with both parents at Lv \(RanchEngine.fusionMinimumLevel)+, wake a Mythic beast. Collect Fusion Rumors to learn which.",
                      systemImage: "sparkles")
                Label("Both parents return to the Lattice. Fusing frees a Haven slot.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.top, 8)
        }
        .font(.headline)
    }
}

/// The Fusion Rumors the player has heard, each pointing at a Mythic recipe.
struct FusionRumorList: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        let rumors = LoreArchive.fusionRumors
        let heard = rumors.filter(store.isUnlocked)
        VStack(alignment: .leading, spacing: 10) {
            Text("Fusion Rumors (\(heard.count)/\(rumors.count))").font(.headline)
            if heard.isEmpty {
                Text("No rumors yet. Talk to people on your travels, and watch the Beastopia episodes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(heard) { rumor in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(rumor.title).font(.subheadline.bold())
                        if let id = rumor.mythicID, store.discoveredSpecies.contains(id),
                           let mythic = SpeciesDatabase.species(id) {
                            Spacer()
                            Label("Solved: \(mythic.name)", systemImage: "checkmark.seal.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                        }
                    }
                    Text(rumor.body).font(.callout).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .gamePanel(tint: .purple)
            }
        }
    }
}
