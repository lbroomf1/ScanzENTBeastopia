//
//  KeeperView.swift
//  Beastopia
//

import SwiftUI

/// The keeper's portrait: their figure on a badge in their signature color.
struct KeeperAvatar: View {
    let keeper: Keeper
    var size: CGFloat = 52

    var body: some View {
        Image(systemName: keeper.style.symbol)
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(keeper.color.color.gradient, in: .circle)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: keeper.keeperClass.symbol)
                    .font(.system(size: size * 0.18, weight: .bold))
                    .foregroundStyle(keeper.color.color)
                    .frame(width: size * 0.36, height: size * 0.36)
                    .background(.white, in: .circle)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Creation

/// Shown on first launch (and for older saves) until the player has made a character.
struct KeeperCreationView: View {
    @Environment(GameStore.self) private var store

    @State private var name = ""
    @State private var keeperClass: KeeperClass = .tamer
    @State private var color: KeeperColor = .indigo
    @State private var style: KeeperStyle = .wanderer

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var preview: Keeper {
        Keeper(name: trimmedName.isEmpty ? "Glyphkeeper" : trimmedName,
               keeperClass: keeperClass, color: color, style: style)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        KeeperAvatar(keeper: preview, size: 96)
                        Text(preview.name).font(.title2.bold())
                        Text("\(keeperClass.displayName) · Rank 1").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } footer: {
                    Text("Maren has vanished, leaving you her Beast Haven and a Lattice Lens. Who are you, new Glyphkeeper?")
                }

                KeeperLookFields(name: $name, color: $color, style: $style)

                Section {
                    ForEach(KeeperClass.allCases) { option in
                        Button {
                            keeperClass = option
                            SoundFX.play(.tap)
                        } label: {
                            ClassRow(keeperClass: option, isSelected: option == keeperClass)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Class")
                } footer: {
                    Text("Your hero stats boost every beast you send into battle. You can change class later for \(Keeper.classChangeCost) coins.")
                }
            }
            .menuBackground("menu_bg_title")
            .navigationTitle("Create Your Keeper")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button("Begin Your Journey") {
                    SoundFX.play(.summon)
                    store.createKeeper(preview)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(trimmedName.isEmpty)
                .padding()
            }
        }
    }
}

/// Name, color and figure pickers shared by creation and editing.
private struct KeeperLookFields: View {
    @Binding var name: String
    @Binding var color: KeeperColor
    @Binding var style: KeeperStyle

    var body: some View {
        Section("Name") {
            TextField("Your name", text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .onChange(of: name) {
                    if name.count > Keeper.maxNameLength { name = String(name.prefix(Keeper.maxNameLength)) }
                }
        }
        Section("Look") {
            Picker("Figure", selection: $style) {
                ForEach(KeeperStyle.allCases) { option in
                    Label(option.displayName, systemImage: option.symbol).tag(option)
                }
            }
            HStack {
                ForEach(KeeperColor.allCases) { option in
                    Button {
                        color = option
                    } label: {
                        Circle()
                            .fill(option.color.gradient)
                            .frame(width: 30, height: 30)
                            .overlay {
                                if option == color {
                                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.rawValue.capitalized)
                    .accessibilityAddTraits(option == color ? .isSelected : [])
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct ClassRow: View {
    let keeperClass: KeeperClass
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: keeperClass.symbol)
                .font(.title2)
                .frame(width: 36)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(keeperClass.displayName).font(.headline)
                Text(keeperClass.summary).font(.caption).foregroundStyle(.secondary)
                Text("Focus: \(keeperClass.focus.displayName) · \(keeperClass.perk)")
                    .font(.caption2.bold())
                    .foregroundStyle(.tint)
            }
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Haven banner

/// The keeper's card at the top of the Haven. Opens their profile.
struct KeeperBanner: View {
    @Environment(GameStore.self) private var store
    @State private var showProfile = false

    var body: some View {
        if let keeper = store.keeper {
            Button {
                SoundFX.play(.tap)
                showProfile = true
            } label: {
                HStack(spacing: 12) {
                    KeeperAvatar(keeper: keeper, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(keeper.name).font(.headline)
                        Text("Rank \(keeper.rank) \(keeper.keeperClass.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if keeper.rank < Keeper.maxRank {
                            ProgressView(value: Double(keeper.xp), total: Double(keeper.xpToNextRank))
                                .tint(keeper.color.color)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(.background.secondary, in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .sheet(isPresented: $showProfile) { KeeperProfileView() }
        }
    }
}

// MARK: - Profile

/// Hero stats, battle bonuses, rank perks and gear.
struct KeeperProfileView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            if let keeper = store.keeper {
                List {
                    Section {
                        HStack(spacing: 14) {
                            KeeperAvatar(keeper: keeper, size: 72)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(keeper.name).font(.title2.bold())
                                Label(keeper.keeperClass.displayName, systemImage: keeper.keeperClass.symbol)
                                    .font(.subheadline)
                                Text(keeper.keeperClass.perk).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if keeper.rank < Keeper.maxRank {
                            VStack(alignment: .leading) {
                                Text("Rank \(keeper.rank) · \(keeper.xp)/\(keeper.xpToNextRank) XP")
                                    .font(.caption.bold())
                                ProgressView(value: Double(keeper.xp), total: Double(keeper.xpToNextRank))
                                    .tint(keeper.color.color)
                            }
                        } else {
                            Text("Rank \(keeper.rank) · Max rank").font(.caption.bold())
                        }
                    } footer: {
                        Text("Earn Keeper XP from battles, quest steps and chapters.")
                    }

                    Section {
                        ForEach(HeroStat.allCases) { stat in
                            HStack {
                                Label(stat.displayName, systemImage: stat.symbol)
                                Spacer()
                                Text("\(keeper.value(of: stat))").bold().monospacedDigit()
                                Text(stat.boostedStats.map { "\($0.shortName) +\(keeper.bonusPercent(for: $0))%" }
                                        .joined(separator: "  "))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 120, alignment: .trailing)
                            }
                        }
                    } header: {
                        Text("Hero Stats")
                    } footer: {
                        Text("Each point boosts two beast stats by 1% in every battle, up to +\(Keeper.maxBonusPercent)%.")
                    }

                    Section("Gear") {
                        ForEach(GearSlot.allCases) { slot in
                            gearRow(slot, keeper: keeper)
                        }
                    }

                    Section {
                        ForEach(Keeper.milestones) { milestone in
                            HStack {
                                Text("Rank \(milestone.rank)").font(.subheadline.bold()).frame(width: 72, alignment: .leading)
                                Text(milestone.perk)
                                Spacer()
                                Image(systemName: keeper.rank >= milestone.rank ? "checkmark.seal.fill" : "lock.fill")
                                    .foregroundStyle(keeper.rank >= milestone.rank ? .green : .secondary)
                            }
                        }
                    } header: {
                        Text("Rank Perks")
                    }
                }
                .menuBackground("menu_bg_settings")
                .navigationTitle("Keeper")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .topBarLeading) { Button("Edit") { showEditor = true } }
                }
                .sheet(isPresented: $showEditor) { KeeperEditor(keeper: keeper) }
            }
        }
    }

    private func gearRow(_ slot: GearSlot, keeper: Keeper) -> some View {
        let owned = GearKind.allCases.filter { $0.slot == slot && keeper.ownedGear.contains($0) }
        let current = keeper.equipped(in: slot)
        return Menu {
            ForEach(owned) { gear in
                Button {
                    store.equip(gear)
                    SoundFX.play(.tap)
                } label: {
                    Label("\(gear.name) (\(gear.summary))", systemImage: gear == current ? "checkmark" : gear.symbol)
                }
            }
            if current != nil {
                Button("Unequip", systemImage: "xmark", role: .destructive) { store.unequip(slot) }
            }
        } label: {
            HStack {
                Image(systemName: current?.symbol ?? GearKind.allCases.first { $0.slot == slot }?.symbol ?? "square.dashed")
                    .frame(width: 28)
                    .foregroundStyle(current == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
                VStack(alignment: .leading) {
                    Text(slot.displayName).font(.caption).foregroundStyle(.secondary)
                    Text(current?.name ?? (owned.isEmpty ? "Buy gear at the Haven Market" : "Empty"))
                        .foregroundStyle(.primary)
                    if let current { Text(current.summary).font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer()
                if !owned.isEmpty { Image(systemName: "chevron.up.chevron.down").foregroundStyle(.tertiary) }
            }
        }
        .disabled(owned.isEmpty)
    }
}

/// Edits the keeper's name and look for free; changing class costs coins.
private struct KeeperEditor: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var color: KeeperColor
    @State private var style: KeeperStyle
    @State private var pendingClass: KeeperClass?

    init(keeper: Keeper) {
        _name = State(initialValue: keeper.name)
        _color = State(initialValue: keeper.color)
        _style = State(initialValue: keeper.style)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                KeeperLookFields(name: $name, color: $color, style: $style)

                if let current = store.keeper?.keeperClass {
                    Section {
                        ForEach(KeeperClass.allCases) { option in
                            Button {
                                if option != current { pendingClass = option }
                            } label: {
                                ClassRow(keeperClass: option, isSelected: option == current)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Class")
                    } footer: {
                        Text("Changing class costs \(Keeper.classChangeCost) coins. Your rank and gear stay the same.")
                    }
                }
            }
            .navigationTitle("Edit Keeper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateLook(name: trimmedName, color: color, style: style)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
            .confirmationDialog("Become a \(pendingClass?.displayName ?? "")?",
                                isPresented: Binding(get: { pendingClass != nil }, set: { if !$0 { pendingClass = nil } }),
                                titleVisibility: .visible) {
                Button("Change Class (\(Keeper.classChangeCost) coins)") {
                    if let pendingClass, store.changeClass(to: pendingClass) {
                        SoundFX.play(.purchase)
                    } else {
                        SoundFX.play(.denied)
                    }
                    pendingClass = nil
                }
            } message: {
                Text(store.coins >= Keeper.classChangeCost ? "You have \(store.coins) coins."
                                                            : "You need \(Keeper.classChangeCost) coins. You have \(store.coins).")
            }
        }
    }
}

// MARK: - Market

/// Keeper gear for sale in the Haven Market.
struct GearMarketSection: View {
    @Environment(GameStore.self) private var store
    @Binding var feedback: String?

    var body: some View {
        if let keeper = store.keeper {
            Section {
                ForEach(GearKind.allCases) { gear in
                    let price = store.price(of: gear.price)
                    let owned = keeper.ownedGear.contains(gear)
                    let locked = keeper.rank < gear.requiredRank
                    HStack(spacing: 12) {
                        Image(systemName: gear.symbol)
                            .font(.title3)
                            .frame(width: 40, height: 40)
                            .background(.tint.opacity(0.15), in: .rect(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(gear.name).font(.headline)
                            Text("\(gear.slot.displayName) · \(gear.summary)").font(.caption).foregroundStyle(.secondary)
                            if locked {
                                Text("Requires Keeper rank \(gear.requiredRank)").font(.caption2).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        if owned {
                            Text("Owned").font(.caption.bold()).foregroundStyle(.secondary)
                        } else {
                            Button {
                                if store.buy(gear) {
                                    feedback = "Bought and equipped the \(gear.name)."
                                    SoundFX.play(.purchase)
                                } else {
                                    feedback = locked ? "Reach Keeper rank \(gear.requiredRank) to buy the \(gear.name)."
                                                      : "Not enough \(price.currencyName) for the \(gear.name)."
                                    SoundFX.play(.denied)
                                }
                            } label: {
                                PriceLabel(price: price)
                            }
                            .buttonStyle(.bordered)
                            .tint(store.canAfford(price) && !locked ? .accentColor : .red)
                        }
                    }
                }
            } header: {
                Text("Keeper Gear")
            } footer: {
                Text("Gear raises your hero stats, which boost every beast you battle with. Change it from your Keeper profile in the Haven.")
            }
        }
    }
}
