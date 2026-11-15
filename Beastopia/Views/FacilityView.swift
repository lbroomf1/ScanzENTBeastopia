//
//  FacilityView.swift
//  Beastopia
//

import SwiftUI

/// A care station — the Stable, Feeding Trough, Hot Spring, Training Post, Campfire or Market.
/// Opened by walking up to one on the map, or from Haven Grounds in the Haven tab.
struct FacilitySheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let facility: Facility

    @State private var selection: UUID?
    @State private var feedback: String?

    private var beast: Beast? { selection.flatMap(store.beast) ?? store.partner }

    var body: some View {
        NavigationStack {
            Group {
                if facility == .market {
                    MarketList()
                } else if facility == .inn {
                    inn
                } else {
                    care
                }
            }
            .pixelToast($feedback)
            .navigationTitle(facility.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
        .onAppear { selection = selection ?? store.partner?.id }
    }

    /// The innkeeper rests the whole team at once.
    private var inn: some View {
        List {
            Section {
                Label(facility.summary, systemImage: facility.symbol)
                    .font(.callout)
                CurrencyBar()
            }
            Section("Your Beasts") {
                ForEach(store.beasts) { beast in
                    HStack {
                        BeastPortrait(beast: beast, size: 36)
                        MeterBar(label: beast.displayName, value: beast.fatigue, maximum: 100,
                                 tint: beast.fatigue >= 80 ? .red : .orange)
                    }
                }
            }
            Section {
                Button("Stay the Night (\(GameStore.innCost) coins)", systemImage: "moon.zzz.fill") {
                    if store.stayAtInn() {
                        feedback = "Everyone sleeps soundly. All fatigue cleared, bond +1."
                        SoundFX.play(.rest)
                    } else {
                        feedback = store.coins < GameStore.innCost ? "Not enough coins for a room." : "Nobody's tired yet."
                        SoundFX.play(.denied)
                    }
                }
                .font(.headline)
                .disabled(store.beasts.isEmpty)
            }
        }
    }

    private var care: some View {
        List {
            Section {
                Label(facility.summary, systemImage: facility.symbol)
                    .font(.callout)
                if store.beasts.count > 1 {
                    BeastPicker(selection: $selection)
                        .listRowInsets(EdgeInsets())
                        .padding(.vertical, 6)
                }
            }

            if let beast {
                Section(beast.displayName) {
                    MeterBar(label: "LV \(beast.level)", value: beast.xp, maximum: beast.xpToNextLevel, tint: .blue)
                    MeterBar(label: "BOND", value: beast.bond, maximum: 100, tint: .pink)
                    MeterBar(label: "TIRE", value: beast.fatigue, maximum: 100, tint: beast.fatigue >= 80 ? .red : .orange)
                }
                Section { actions(for: beast) }
            } else {
                Text("You need a beast first. Scan a code to awaken one!").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func actions(for beast: Beast) -> some View {
        switch facility {
        case .stable, .campfire:
            Button(facility == .stable ? "Rest in the Stable" : "Rest by the Fire", systemImage: "bed.double.fill") {
                store.update(beast.id) { RanchEngine.rest(&$0) }
                feedback = "\(beast.displayName) takes a long nap. Fatigue −40."
                SoundFX.play(.rest)
            }
            .disabled(beast.fatigue == 0)
        case .feedingTrough:
            Button("Feed", systemImage: "carrot.fill") {
                store.update(beast.id) { RanchEngine.feed(&$0) }
                feedback = "\(beast.displayName) happily munches away. Bond up!"
                SoundFX.play(.feed)
            }
        case .hotSpring:
            let cost = RanchEngine.Upgrade.hotSprings.cost(for: beast)
            Button("Soak (\(cost) coins)", systemImage: "drop.circle.fill") {
                if store.purchase(.hotSprings, for: beast.id) != nil {
                    feedback = "\(beast.displayName) comes out of the spring fully refreshed."
                    SoundFX.play(.rest)
                } else {
                    feedback = "Not enough coins for a soak."
                    SoundFX.play(.denied)
                }
            }
            .disabled(beast.fatigue == 0)
        case .trainingPost:
            ForEach(StatKind.allCases) { kind in
                Button {
                    var result: RanchEngine.TrainingResult?
                    store.update(beast.id) { result = RanchEngine.train(&$0, stat: kind) }
                    if let result {
                        feedback = result.message + (result.levelsGained > 0 ? " · Level up!" : "")
                        SoundFX.play(result.levelsGained > 0 ? .levelUp : .train)
                    }
                } label: {
                    LabeledContent {
                        Text("\(beast.stats[kind])").monospacedDigit()
                    } label: {
                        GameLabel(kind.drillName, art: kind.iconArt, symbol: kind.symbol)
                    }
                }
            }
        case .market, .inn:
            EmptyView()
        }
    }
}

/// Coins and shards, side by side.
struct CurrencyBar: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        HStack(spacing: 14) {
            GameLabel("\(store.coins)", art: GameArt.coinIcon, symbol: "circle.hexagongrid.fill")
                .foregroundStyle(.yellow)
            GameLabel("\(store.shards)", art: GameArt.shardIcon, symbol: "diamond.fill")
                .foregroundStyle(.cyan)
                .accessibilityLabel("\(store.shards) Lattice Shards")
        }
        .font(.subheadline.bold().monospacedDigit())
    }
}

/// The Haven Market: spend coins and Lattice Shards on items.
struct MarketList: View {
    @Environment(GameStore.self) private var store
    @State private var feedback: String?
    @State private var buying: ItemKind?

    var body: some View {
        List {
            Section {
                CurrencyBar()
            } footer: {
                Text("Earn coins from battles, chapters and selling beasts. Lattice Shards come from bosses, raids and hidden treasure.")
            }
            Section("Battle Items") { rows(ItemKind.battleItems) }
            Section("Haven Items") { rows(ItemKind.fieldItems) }
            GearMarketSection(feedback: $feedback)
        }
        .menuBackground("menu_bg_market")
        .pixelToast($feedback)
        .sheet(item: $buying) { item in
            PurchaseQuantitySheet(item: item) { feedback = $0 }
        }
    }

    private func rows(_ items: [ItemKind]) -> some View {
        ForEach(items) { item in
            let price = store.price(of: item)
            HStack(spacing: 12) {
                ItemIcon(item: item)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.headline)
                    Text(item.summary).font(.caption).foregroundStyle(.secondary)
                    Text("Owned: \(store.count(of: item))").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Button {
                    if store.canAfford(price) {
                        buying = item
                    } else {
                        feedback = "Not enough \(price.currencyName) for a \(item.name)."
                        SoundFX.play(.denied)
                    }
                } label: {
                    PriceLabel(price: price)
                }
                .buttonStyle(.bordered)
                .tint(store.canAfford(price) ? .accentColor : .red)
                .accessibilityLabel("Buy \(item.name), \(price.spokenDescription) each")
            }
        }
    }
}

/// Choose how many of an item to buy, with the running total and what you can afford.
struct PurchaseQuantitySheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let item: ItemKind
    /// Called with a message after a purchase (or a failed one).
    let onResult: (String) -> Void

    @State private var quantity = 1

    private var maxQuantity: Int { max(1, store.maxAffordable(item)) }
    private var total: Price { store.price(of: item, quantity: quantity) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    ItemIcon(item: item, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.headline)
                        Text("Owned: \(store.count(of: item))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Stepper(value: $quantity, in: 1...maxQuantity) {
                    Text("Quantity: \(quantity)").font(.title3.bold().monospacedDigit())
                }

                HStack(spacing: 8) {
                    ForEach([1, 5, 10], id: \.self) { preset in
                        Button("\(preset)") { quantity = min(preset, maxQuantity) }
                            .buttonStyle(.bordered)
                            .disabled(preset > maxQuantity)
                    }
                    Button("Max (\(maxQuantity))") { quantity = maxQuantity }
                        .buttonStyle(.bordered)
                }

                HStack {
                    Text("Total").font(.headline)
                    Spacer()
                    PriceLabel(price: total).font(.headline)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Total: \(total.spokenDescription)")

                Button {
                    if store.buy(item, quantity: quantity) {
                        SoundFX.play(.purchase)
                        onResult("Bought \(quantity) × \(item.name).")
                    } else {
                        SoundFX.play(.denied)
                        onResult("Not enough \(total.currencyName) for \(quantity) × \(item.name).")
                    }
                    dismiss()
                } label: {
                    Text("Buy \(quantity)").frame(maxWidth: .infinity)
                }
                .buttonStyle(GameButtonStyle())
                .disabled(!store.canAfford(total))
            }
            .padding()
            .navigationTitle("Buy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel") { dismiss() } }
        }
        .presentationDetents([.height(380), .large])
    }
}

struct PriceLabel: View {
    let price: Price

    var body: some View {
        switch price {
        case .coins(let amount):
            GameLabel("\(amount)", art: GameArt.coinIcon, symbol: "circle.hexagongrid.fill").monospacedDigit()
        case .shards(let amount):
            GameLabel("\(amount)", art: GameArt.shardIcon, symbol: "diamond.fill").monospacedDigit()
        }
    }
}

extension Price {
    var currencyName: String {
        switch self {
        case .coins: "coins"
        case .shards: "Lattice Shards"
        }
    }

    /// For VoiceOver, e.g. "120 coins" or "1 Lattice Shard".
    var spokenDescription: String {
        switch self {
        case .coins(let amount): amount == 1 ? "1 coin" : "\(amount) coins"
        case .shards(let amount): amount == 1 ? "1 Lattice Shard" : "\(amount) Lattice Shards"
        }
    }
}

struct ItemIcon: View {
    let item: ItemKind
    var size: CGFloat = 36

    var body: some View {
        // Art sits on a soft tint of the item's color; the symbol fallback keeps the solid tile.
        let hasArt = UIImage(named: item.iconArt) != nil
        GameIcon(art: item.iconArt, symbol: item.symbol, size: size * 0.8)
            .font(.system(size: size * 0.5))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(hasArt ? AnyShapeStyle(item.color.opacity(0.2)) : AnyShapeStyle(item.color.gradient),
                        in: .rect(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

/// The keeper's inventory. Haven items can be used on a beast here; battle items are used in fights.
struct BagView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?
    @State private var feedback: String?

    private var beast: Beast? { selection.flatMap(store.beast) ?? store.partner }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    CurrencyBar()
                }

                Section {
                    if store.beasts.count > 1 {
                        BeastPicker(selection: $selection)
                            .listRowInsets(EdgeInsets())
                            .padding(.vertical, 6)
                    }
                    let owned = ItemKind.fieldItems.filter { store.count(of: $0) > 0 }
                    if owned.isEmpty {
                        Text("No Haven items. Buy candies, treats and tea at the Market.").foregroundStyle(.secondary)
                    }
                    ForEach(owned) { item in
                        itemRow(item) {
                            Button("Use") { use(item) }
                                .buttonStyle(.borderedProminent)
                                .disabled(beast.map { !item.isUsefulInField(for: $0) } ?? true)
                        }
                    }
                } header: {
                    Text("Haven Items")
                } footer: {
                    if let beast { Text("Using on \(beast.displayName) (Lv \(beast.level)).") }
                }

                Section {
                    let owned = ItemKind.battleItems.filter { store.count(of: $0) > 0 }
                    if owned.isEmpty {
                        Text("No battle items.").foregroundStyle(.secondary)
                    }
                    ForEach(owned) { item in itemRow(item) { EmptyView() } }
                } header: {
                    Text("Battle Items")
                } footer: {
                    Text("Open the Bag tab during a battle to use these. Using an item takes your turn, but it acts before any attacks.")
                }

                Section("Field Abilities") {
                    ForEach(TraversalAbility.allCases) { ability in
                        AbilityRow(ability: ability)
                    }
                }
            }
            .pixelToast($feedback)
            .navigationTitle("Bag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
        .onAppear { selection = selection ?? store.partner?.id }
    }

    private func itemRow(_ item: ItemKind, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 12) {
            ItemIcon(item: item)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.name) ×\(store.count(of: item))").font(.headline)
                Text(item.summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            trailing()
        }
    }

    private func use(_ item: ItemKind) {
        guard let beast, let levels = store.use(item, on: beast.id) else {
            SoundFX.play(.denied)
            return
        }
        feedback = levels > 0 ? "\(beast.displayName) grew to Lv \(beast.level + levels)!"
                              : "\(beast.displayName) enjoyed the \(item.name)."
        SoundFX.play(levels > 0 ? .levelUp : .feed)
    }
}

/// Whether the keeper has a beast that lends a field ability, and which one.
struct AbilityRow: View {
    @Environment(GameStore.self) private var store
    let ability: TraversalAbility

    var body: some View {
        let helper = store.helper(for: ability)
        HStack(spacing: 12) {
            GameIcon(art: ability.iconArt, symbol: ability.symbol, size: 28)
                .font(.title3)
                .foregroundStyle(helper == nil ? Color.secondary : Color.accentColor)
                .saturation(helper == nil ? 0 : 1)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(ability.displayName).font(.headline)
                Text(helper.map { "\($0.displayName) can help. \(ability.summary)" } ?? requirement)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(helper == nil ? 0.6 : 1)
    }

    private var requirement: String {
        switch ability {
        case .swim: "Locked — raise a Tide beast, like Ripplet."
        case .fly: "Locked — raise a Gale beast like Fluffwing, or a Pyrowl."
        case .teleport: "Locked — raise a Lumen or Umbra beast, like Glimmet or Shadeling."
        }
    }
}

/// Haven Grounds: the Haven's care stations, also found by walking around Beast Haven.
struct HavenGrounds: View {
    @Environment(GameStore.self) private var store
    @State private var facility: Facility?
    @State private var showBag = false

    private static let stations: [Facility] = [.stable, .feedingTrough, .hotSpring, .trainingPost, .market]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Haven Grounds").font(.headline)
                Spacer()
                CurrencyBar()
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Self.stations) { station in
                        tile(station.name, symbol: station.symbol) {
                            SoundFX.play(.tap)
                            facility = station
                        }
                    }
                    tile("Bag", symbol: "bag.fill") {
                        SoundFX.play(.tap)
                        showBag = true
                    }
                }
            }
            .scrollIndicators(.hidden)
            Text("You can also visit these on foot: explore Beast Haven from the Story tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .sheet(item: $facility) { FacilitySheet(facility: $0) }
        .sheet(isPresented: $showBag) { BagView() }
    }

    private func tile(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.accentColor.gradient, in: .rect(cornerRadius: 14))
                Text(title).font(.caption.bold()).lineLimit(1)
            }
            .frame(width: 84)
        }
        .buttonStyle(.plain)
    }
}
