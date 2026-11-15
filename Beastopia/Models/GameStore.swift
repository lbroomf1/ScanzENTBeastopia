//
//  GameStore.swift
//  Beastopia
//

import Foundation
import Observation
import OSLog

/// Where the save file is read from and written to. Injected into `GameStore` so tests and
/// previews can use memory instead of the real save on disk.
protocol SaveStorage: AnyObject {
    func load() -> Data?
    func save(_ data: Data) throws
    /// Keeps a copy of save data the game couldn't read, so the next `save(_:)` doesn't destroy it.
    func setAside(_ data: Data) throws
}

/// The real save: a JSON file in the app's Documents folder.
final class FileSaveStorage: SaveStorage {
    let url: URL

    init(url: URL = URL.documentsDirectory.appending(path: "beastopia-save.json")) {
        self.url = url
    }

    func load() -> Data? { try? Data(contentsOf: url) }
    func save(_ data: Data) throws { try data.write(to: url, options: .atomic) }

    /// Writes the data beside the save as `beastopia-save.unreadable-<time>.json`. Never overwrites an earlier copy.
    func setAside(_ data: Data) throws {
        let stamp = Int(Date.now.timeIntervalSince1970)
        let name = "\(url.deletingPathExtension().lastPathComponent).unreadable-\(stamp).\(url.pathExtension)"
        try data.write(to: url.deletingLastPathComponent().appending(path: name), options: .withoutOverwriting)
    }
}

/// A save that lives only in memory, for tests and previews.
final class InMemorySaveStorage: SaveStorage {
    private(set) var data: Data?
    private(set) var saveCount = 0

    init(data: Data? = nil) { self.data = data }

    func load() -> Data? { data }
    func save(_ data: Data) throws {
        self.data = data
        saveCount += 1
    }

    /// Save data that was set aside because it couldn't be read.
    private(set) var setAsideData: [Data] = []

    func setAside(_ data: Data) throws { setAsideData.append(data) }
}

/// Wraps any random number generator so it can be stored and passed `inout` to `random(in:using:)`.
struct AnyRandomNumberGenerator: RandomNumberGenerator {
    private var base: any RandomNumberGenerator

    init(_ base: any RandomNumberGenerator) { self.base = base }

    mutating func next() -> UInt64 { base.next() }
}

/// The player's persistent save: their Beast Haven, Beastdex progress and story progress.
@Observable
final class GameStore {
    enum ScanOutcome {
        case discovered(Beast)
        case alreadyClaimed
        case havenFull
    }

    static let baseHavenCapacity = 30

    private(set) var beasts: [Beast] = []
    private(set) var discoveredSpecies: Set<String> = []
    private(set) var completedChapters: Set<Int> = []
    /// IDs of finished quest steps in the adventure world.
    private(set) var completedObjectives: Set<String> = []
    /// Flags recorded by dialogue choices; later dialogue reacts to them.
    private(set) var storyFlags: Set<String> = []
    /// Where the player last stood in each explorable region, keyed by region ID.
    private(set) var adventurePositions: [Int: Tile] = [:]
    private(set) var coins = 0
    /// Lattice Shards: rare currency from bosses and treasure chests.
    private(set) var shards = 0
    private(set) var inventory: [ItemKind: Int] = [:]
    /// IDs of treasure chests already looted, Element Glyphs already awakened and element puzzles
    /// already solved (all stable IDs in one set, so older saves need no new field).
    private(set) var openedChests: Set<String> = []
    /// The player's character. `nil` until they've made one.
    private(set) var keeper: Keeper?
    var partnerID: UUID?

    /// Fingerprints of claimed codes (the raw payload is never stored).
    private var claimedCodes: Set<String> = []

    @ObservationIgnored private let storage: SaveStorage
    /// Source of randomness for loot drops. Inject a seeded generator to make drops repeatable.
    @ObservationIgnored private var random: AnyRandomNumberGenerator

    /// The most of one item that can be bought in a single purchase.
    static let maxPurchaseQuantity = 99

    init(storage: SaveStorage = FileSaveStorage(), random: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.storage = storage
        self.random = AnyRandomNumberGenerator(random)
        load()
    }

    /// Grows with Keeper rank.
    var havenCapacity: Int { Self.baseHavenCapacity + (keeper?.bonusHavenSlots ?? 0) }

    var partner: Beast? {
        beasts.first { $0.id == partnerID } ?? beasts.first
    }

    var nextChapter: Chapter? {
        StoryCampaign.chapters.first { !completedChapters.contains($0.id) }
    }

    func isUnlocked(_ chapter: Chapter) -> Bool {
        chapter.id == 1 || completedChapters.contains(chapter.id - 1)
    }

    // MARK: - Scanning

    func claim(code: String) -> ScanOutcome {
        // Episode codes are matched loosely (case, spaces, dashes), so fingerprint the canonical
        // form: "ep01 glyph 7kq2" and "EP01-GLYPH-7KQ2" are the same claim.
        let episode = EpisodeCatalog.episode(matching: code)
        let fingerprint = BeastGenerator.fingerprint(of: episode.map { EpisodeCatalog.canonical($0.code) } ?? code)
        guard !claimedCodes.contains(fingerprint) else { return .alreadyClaimed }
        guard beasts.count < havenCapacity else { return .havenFull }

        let beast = episode.map(BeastGenerator.generate(episode:)) ?? BeastGenerator.generate(fromCode: code)
        claimedCodes.insert(fingerprint)
        add(beast)
        return .discovered(beast)
    }

    // MARK: - Lore

    /// Whether this episode's code has been claimed on this save.
    func hasClaimed(_ episode: Episode) -> Bool {
        claimedCodes.contains(BeastGenerator.fingerprint(of: EpisodeCatalog.canonical(episode.code)))
    }

    func isUnlocked(_ entry: LoreEntry) -> Bool {
        switch entry.unlock {
        case .start: true
        case .objective(let id):
            // Finishing a chapter counts every step in it as done, as `isComplete(_:in:)` does.
            completedObjectives.contains(id) || WorldMap.regions.contains { region in
                completedChapters.contains(region.id) && region.objectives.contains { $0.id == id }
            }
        case .chapter(let id): completedChapters.contains(id)
        case .episode(let number): EpisodeCatalog.episode(number: number).map(hasClaimed) ?? false
        }
    }

    var unlockedLoreCount: Int {
        LoreArchive.entries.filter(isUnlocked).count
    }

    private func add(_ beast: Beast) {
        // A starter kit with the very first beast, so new keepers can try the Bag in battle.
        if beasts.isEmpty && inventory.isEmpty {
            inventory = [.berry: 3, .remedy: 1]
        }
        beasts.append(beast)
        discoveredSpecies.insert(beast.speciesID)
        if partnerID == nil { partnerID = beast.id }
        save()
    }

    // MARK: - Raising

    func update(_ id: UUID, _ change: (inout Beast) -> Void) {
        guard let index = beasts.firstIndex(where: { $0.id == id }) else { return }
        change(&beasts[index])
        discoveredSpecies.insert(beasts[index].speciesID)
        save()
    }

    func beast(_ id: UUID) -> Beast? {
        beasts.first { $0.id == id }
    }

    /// Beasts that meet an evolution's requirements right now.
    var readyToEvolve: [Beast] {
        beasts.filter { $0.availableEvolution != nil }
    }

    /// Marks a species as seen (for example, met in battle) so the Beastdex reveals it.
    func discover(_ speciesID: String) {
        guard SpeciesDatabase.species(speciesID) != nil, discoveredSpecies.insert(speciesID).inserted else { return }
        save()
    }

    func release(_ id: UUID) {
        beasts.removeAll { $0.id == id }
        if partnerID == id { partnerID = beasts.first?.id }
        save()
    }

    /// The primary beast leads in adventures and is the default fighter in battles.
    func setPrimary(_ id: UUID) {
        guard beast(id) != nil else { return }
        partnerID = id
        save()
    }

    /// Spends coins on a Haven upgrade. Returns the levels gained, or `nil` if it can't be bought.
    func purchase(_ upgrade: RanchEngine.Upgrade, for id: UUID) -> Int? {
        guard let target = beast(id), upgrade.isUseful(for: target) else { return nil }
        let cost = upgrade.cost(for: target)
        guard coins >= cost else { return nil }
        coins -= cost
        var levels = 0
        update(id) { levels = RanchEngine.apply(upgrade, to: &$0) }
        return levels
    }

    /// Merges `donor` into `target`; the donor returns to the Lattice. Returns the levels gained.
    func absorb(_ donor: UUID, into target: UUID) -> Int? {
        guard donor != target, let donorBeast = beast(donor), beast(target) != nil else { return nil }
        var levels = 0
        update(target) { levels = RanchEngine.absorb(donorBeast, into: &$0) }
        release(donor)
        return levels
    }

    /// Sells a beast for coins. Returns the coins earned.
    func sell(_ id: UUID) -> Int? {
        guard let sold = beast(id) else { return nil }
        let value = RanchEngine.sellValue(of: sold)
        coins += value
        release(id)
        return value
    }

    /// Other beasts in the Haven from the same evolution line.
    func duplicates(of id: UUID) -> [Beast] {
        guard let original = beast(id) else { return [] }
        return beasts.filter { $0.id != id && RanchEngine.isSameLine($0, original) }
    }

    func fuse(_ a: UUID, _ b: UUID) -> Beast? {
        guard a != b, let first = beast(a), let second = beast(b) else { return nil }
        let child = RanchEngine.fuse(first, second)
        beasts.removeAll { $0.id == a || $0.id == b }
        if partnerID == a || partnerID == b { partnerID = nil }
        add(child)
        return child
    }

    // MARK: - Keeper

    func createKeeper(_ keeper: Keeper) {
        guard self.keeper == nil else { return }
        self.keeper = keeper
        save()
    }

    /// Updates the keeper's name and look. Changing class goes through `changeClass(to:)`.
    func updateLook(name: String, color: KeeperColor, style: KeeperStyle) {
        keeper?.name = name
        keeper?.color = color
        keeper?.style = style
        save()
    }

    /// Changes class for a fee. Returns `false` if the keeper can't afford it.
    @discardableResult
    func changeClass(to newClass: KeeperClass) -> Bool {
        guard let keeper, keeper.keeperClass != newClass, coins >= Keeper.classChangeCost else { return false }
        coins -= Keeper.classChangeCost
        self.keeper?.keeperClass = newClass
        save()
        return true
    }

    /// Buys and equips a piece of gear. Returns `false` if it's owned, locked or unaffordable.
    @discardableResult
    func buy(_ gear: GearKind) -> Bool {
        guard let keeper, !keeper.ownedGear.contains(gear), keeper.rank >= gear.requiredRank else { return false }
        let price = price(of: gear.price)
        guard canAfford(price) else { return false }
        spend(price)
        self.keeper?.ownedGear.insert(gear)
        self.keeper?.equip(gear)
        save()
        return true
    }

    func equip(_ gear: GearKind) {
        keeper?.equip(gear)
        save()
    }

    func unequip(_ slot: GearSlot) {
        keeper?.unequip(slot)
        save()
    }

    /// The beast as it fights: with the keeper's hero bonuses applied.
    func battleReady(_ beast: Beast) -> Beast {
        keeper?.boosted(beast) ?? beast
    }

    private func addKeeperXP(_ amount: Int) -> Int {
        keeper?.addXP(amount) ?? 0
    }

    // MARK: - Items

    func count(of item: ItemKind) -> Int { inventory[item] ?? 0 }

    func add(_ loot: Loot) {
        for (item, amount) in loot.items { inventory[item, default: 0] += amount }
        coins += loot.coins
        shards += loot.shards
        save()
    }

    /// Removes one of an item. Returns `false` if there are none left.
    @discardableResult
    func consume(_ item: ItemKind) -> Bool {
        guard count(of: item) > 0 else { return false }
        inventory[item] = count(of: item) - 1
        if inventory[item] == 0 { inventory[item] = nil }
        save()
        return true
    }

    func canAfford(_ price: Price) -> Bool {
        switch price {
        case .coins(let amount): coins >= amount
        case .shards(let amount): shards >= amount
        }
    }

    /// A Market price after the keeper's rank discount (coins only).
    func price(of price: Price) -> Price {
        guard case .coins(let amount) = price, let discount = keeper?.marketDiscountPercent, discount > 0 else { return price }
        return .coins(amount * (100 - discount) / 100)
    }

    func price(of item: ItemKind) -> Price { price(of: item.price) }

    /// The discounted price of `quantity` of an item.
    func price(of item: ItemKind, quantity: Int) -> Price { price(of: item).times(quantity) }

    /// How many of an item the keeper can afford right now, up to `maxPurchaseQuantity`.
    func maxAffordable(_ item: ItemKind) -> Int {
        let (unit, balance) = switch price(of: item) {
        case .coins(let amount): (amount, coins)
        case .shards(let amount): (amount, shards)
        }
        guard unit > 0 else { return Self.maxPurchaseQuantity }
        return min(Self.maxPurchaseQuantity, balance / unit)
    }

    private func spend(_ price: Price) {
        switch price {
        case .coins(let amount): coins -= amount
        case .shards(let amount): shards -= amount
        }
    }

    /// Buys `quantity` of an item from the Market in one go. Returns `false` (and buys nothing)
    /// if the quantity is out of range or the keeper can't afford all of them.
    @discardableResult
    func buy(_ item: ItemKind, quantity: Int = 1) -> Bool {
        guard (1...Self.maxPurchaseQuantity).contains(quantity) else { return false }
        let total = price(of: item, quantity: quantity)
        guard canAfford(total) else { return false }
        spend(total)
        inventory[item, default: 0] += quantity
        save()
        return true
    }

    /// Uses a field item on a beast. Returns the levels gained, or `nil` if it couldn't be used.
    func use(_ item: ItemKind, on id: UUID) -> Int? {
        guard !item.isBattleItem, let target = beast(id), item.isUsefulInField(for: target), consume(item) else { return nil }
        var levels = 0
        update(id) { levels = item.applyInField(to: &$0) }
        return levels
    }

    // MARK: - Exploring

    /// Field abilities lent by every beast in the Haven.
    var fieldAbilities: Set<TraversalAbility> {
        beasts.reduce(into: []) { $0.formUnion($1.species.abilities) }
    }

    /// The beast that lends an ability: the primary beast if it can, otherwise the highest level.
    func helper(for ability: TraversalAbility) -> Beast? {
        if let partner, partner.species.abilities.contains(ability) { return partner }
        return beasts.filter { $0.species.abilities.contains(ability) }.max { $0.level < $1.level }
    }

    /// Opens a chest and adds its loot. Returns `false` if it was already opened.
    func open(_ treasure: Treasure) -> Bool {
        guard !openedChests.contains(treasure.id) else { return false }
        openedChests.insert(treasure.id)
        add(treasure.loot)
        return true
    }

    /// What happened when the keeper touched an Element Glyph.
    enum GlyphOutcome {
        case awakened(Beast)
        case alreadyClaimed
        case havenFull
    }

    /// Awakens the beast sealed in a region's Element Glyph, once per save.
    func claim(_ glyph: ElementGlyph) -> GlyphOutcome {
        guard !openedChests.contains(glyph.id) else { return .alreadyClaimed }
        guard beasts.count < havenCapacity else { return .havenFull }
        let beast = BeastGenerator.generate(glyph: glyph)
        openedChests.insert(glyph.id)
        add(beast)
        return .awakened(beast)
    }

    func hasClaimed(_ glyph: ElementGlyph) -> Bool { openedChests.contains(glyph.id) }

    /// Records a solved element puzzle (e.g. opened brambles) so it stays solved.
    func markSolved(_ puzzleID: String) {
        guard openedChests.insert(puzzleID).inserted else { return }
        save()
    }

    func isSolved(_ puzzleID: String) -> Bool { openedChests.contains(puzzleID) }

    /// What a night at an Inn costs.
    static let innCost = 20

    /// Rests every beast at an Inn: fatigue cleared and bond +1. Returns `false` if the keeper
    /// can't afford it or nobody is tired.
    @discardableResult
    func stayAtInn() -> Bool {
        guard coins >= Self.innCost, beasts.contains(where: { $0.fatigue > 0 }) else { return false }
        coins -= Self.innCost
        for index in beasts.indices {
            beasts[index].fatigue = 0
            beasts[index].bond = min(100, beasts[index].bond + 1)
        }
        save()
        return true
    }

    // MARK: - Battles

    struct BattleRewards {
        var levels = 0
        var xp = 0
        var loot = Loot()
        var keeperXP = 0
        var keeperRanks = 0
    }

    /// Applies battle rewards to a beast: experience, coins and, on a win, item drops.
    /// Bosses always drop Lattice Shards. The keeper's class and rank add bonuses,
    /// and the keeper earns XP of their own.
    @discardableResult
    func recordBattle(beastID: UUID, won: Bool, opponentLevel: Int, isBoss: Bool = false) -> BattleRewards {
        var rewards = BattleRewards()
        let keeperClass = keeper?.keeperClass
        var xpBonus = keeper?.rankXPBonusPercent ?? 0
        if keeperClass == .scholar { xpBonus += 25 }
        rewards.xp = ((won ? 40 : 15) + opponentLevel * 6) * (100 + xpBonus) / 100
        let bondGain = (won ? 3 : 1) * (keeperClass == .tamer ? 2 : 1)
        update(beastID) { beast in
            if won { beast.wins += 1 } else { beast.losses += 1 }
            beast.bond = min(100, beast.bond + bondGain)
            beast.fatigue = min(100, beast.fatigue + 15)
            rewards.levels = RanchEngine.addXP(&beast, amount: rewards.xp)
        }
        if won {
            rewards.loot = drops(opponentLevel: opponentLevel, isBoss: isBoss)
            rewards.loot.coins += (25 + opponentLevel * 5) * (keeperClass == .ranger ? 125 : 100) / 100
        }
        if keeper != nil {
            rewards.keeperXP = won ? 20 + opponentLevel * 2 : 5
            rewards.keeperRanks = addKeeperXP(rewards.keeperXP)
        }
        add(rewards.loot)
        return rewards
    }

    private func drops(opponentLevel: Int, isBoss: Bool) -> Loot {
        var loot = Loot()
        if isBoss {
            loot.shards = 1 + opponentLevel / 10
            loot.items[.potion] = 1
            loot.items[.latticeCandy] = 1
            return loot
        }
        let roll = Double.random(in: 0..<1, using: &random)
        if roll < 0.35 {
            loot.items[.berry] = 1
        } else if roll < 0.5 {
            loot.items[[.remedy, .gutsTonic, .calmTea].randomElement(using: &random) ?? .remedy] = 1
        } else if roll < 0.58 {
            loot.items[.potion] = 1
        } else if roll < 0.62 {
            loot.shards = 1
        }
        return loot
    }

    func completeChapter(_ chapter: Chapter) {
        guard !completedChapters.contains(chapter.id) else { return }
        completedChapters.insert(chapter.id)
        coins += chapter.coinReward
        _ = addKeeperXP(150)
        discoveredSpecies.insert(chapter.opponentSpeciesID)
        save()
    }

    // MARK: - Adventure world

    func isComplete(_ objective: Objective, in region: Region) -> Bool {
        completedChapters.contains(region.id) || completedObjectives.contains(objective.id)
    }

    /// The next quest step in a region, or `nil` if the region is locked or finished.
    func activeObjective(in region: Region) -> Objective? {
        guard isUnlocked(region.chapter) else { return nil }
        return region.objectives.first { !isComplete($0, in: region) }
    }

    /// Marks a quest step done. Steps must be completed in order; the boss step completes the chapter.
    func completeObjective(_ objective: Objective, in region: Region) {
        guard activeObjective(in: region)?.id == objective.id else { return }
        completedObjectives.insert(objective.id)
        _ = addKeeperXP(40)
        if case .boss = objective.kind {
            completeChapter(region.chapter)
        } else {
            save()
        }
    }

    func setAdventurePosition(_ tile: Tile, regionID: Int) {
        guard adventurePositions[regionID] != tile else { return }
        adventurePositions[regionID] = tile
        save()
    }

    func choose(_ choice: DialogueChoice) {
        if let flag = choice.flag { storyFlags.insert(flag) }
        coins += choice.coinReward
        save()
    }

    // MARK: - Persistence

    private static let logger = Logger(subsystem: "Beastopia", category: "Save")
    /// Set when an unreadable save couldn't be backed up. Saving stays off for the session so it isn't overwritten.
    private var isSavingBlocked = false

    private struct SaveFile: Codable {
        /// Bump when the format changes in a way older builds can't read, and keep decoding older versions.
        static let currentVersion = 1

        /// `nil` for saves written before versioning, which are version 1.
        var version: Int?
        var beasts: [Beast]
        var discoveredSpecies: Set<String>
        var completedChapters: Set<Int>
        var coins: Int
        /// Kept for older saves; the name now lives in `keeper`.
        var keeperName: String
        var partnerID: UUID?
        var claimedCodes: Set<String>
        // Optional so saves from before the adventure world still decode.
        var completedObjectives: Set<String>?
        var storyFlags: Set<String>?
        var adventurePositions: [Int: Tile]?
        // Optional so saves from before items still decode. Keyed by item raw value.
        var inventory: [String: Int]?
        var shards: Int?
        var openedChests: Set<String>?
        // Optional so saves from before player characters still decode.
        var keeper: Keeper?
    }

    func save() {
        guard !isSavingBlocked else { return }
        let file = SaveFile(version: SaveFile.currentVersion, beasts: beasts, discoveredSpecies: discoveredSpecies,
                            completedChapters: completedChapters, coins: coins,
                            keeperName: keeper?.name ?? "Glyphkeeper", partnerID: partnerID, claimedCodes: claimedCodes,
                            completedObjectives: completedObjectives, storyFlags: storyFlags,
                            adventurePositions: adventurePositions,
                            inventory: Dictionary(uniqueKeysWithValues: inventory.map { ($0.key.rawValue, $0.value) }),
                            shards: shards, openedChests: openedChests, keeper: keeper)
        do {
            try storage.save(JSONEncoder().encode(file))
        } catch {
            Self.logger.error("Failed to save: \(error, privacy: .public)")
        }
    }

    private func load() {
        guard let data = storage.load() else { return }
        let file: SaveFile
        do {
            file = try JSONDecoder().decode(SaveFile.self, from: data)
            // A save from a newer build may hold data this build would silently drop.
            guard (file.version ?? 1) <= SaveFile.currentVersion else {
                throw CocoaError(.fileReadUnsupportedScheme)
            }
        } catch {
            // Start fresh, but keep the unreadable save so the next save doesn't overwrite the player's progress.
            Self.logger.error("Unreadable save, setting it aside: \(error, privacy: .public)")
            do {
                try storage.setAside(data)
            } catch {
                Self.logger.fault("Couldn't set aside unreadable save: \(error, privacy: .public)")
                isSavingBlocked = true
            }
            return
        }
        beasts = file.beasts
        discoveredSpecies = file.discoveredSpecies
        completedChapters = file.completedChapters
        coins = file.coins
        keeper = file.keeper
        partnerID = file.partnerID
        claimedCodes = file.claimedCodes
        completedObjectives = file.completedObjectives ?? []
        storyFlags = file.storyFlags ?? []
        adventurePositions = file.adventurePositions ?? [:]
        shards = file.shards ?? 0
        openedChests = file.openedChests ?? []
        for (key, amount) in file.inventory ?? [:] {
            if let item = ItemKind(rawValue: key), amount > 0 { inventory[item] = amount }
        }
    }
}
