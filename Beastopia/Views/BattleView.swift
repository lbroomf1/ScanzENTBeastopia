//
//  BattleView.swift
//  Beastopia
//

import SwiftUI

/// Turn-based battle screen shared by story, Arena practice, raids and online matches.
///
/// The engine resolves a whole turn at once; this view replays the turn's events one beat at
/// a time — lunges, hits, floating numbers, draining HP bars — so each action reads clearly.
struct BattleView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let session: BattleSession
    /// Called once when the player leaves a finished battle, with whether they won.
    var onFinish: (Bool) -> Void = { _ in }

    private enum CommandTab: String, CaseIterable, Identifiable {
        case fight = "Fight", bag = "Bag"
        var id: String { rawValue }
    }

    @State private var rewards: GameStore.BattleRewards?
    @State private var tab: CommandTab = .fight
    @State private var showLog = false

    // Playback state.
    @State private var queue: [BattleEvent] = []
    @State private var playedEvents = 0
    @State private var isAnimating = false
    @State private var displayedHP: [Int: Int] = [:]
    @State private var hitCounts: [Int: Int] = [:]
    @State private var screenShakes = 0
    @State private var lunging: Int?
    @State private var flashing: Int?
    @State private var floaters: [Floater] = []
    @State private var caption: String?
    @State private var banner: Banner?
    @State private var didPlayFanfare = false
    // Arena-only presentation.
    @State private var showsIntro = false
    @State private var crowdHype = 0
    @State private var showsConfetti = false
    @AppStorage(GameSettings.hapticsKey) private var hapticsOn = true
    /// From Settings: no screen shake or hit jolts.
    @AppStorage(GameSettings.reduceEffectsKey) private var reduceEffects = false

    private var showsResult: Bool { session.isOver && !isAnimating }

    /// Practice, raids and online matches happen in the Beast Arena, in front of a crowd.
    private var isArenaMatch: Bool {
        switch session.kind {
        case .practice, .raid, .online: true
        case .story: false
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            arena
            messageBox
            if showsResult {
                resultPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                commandPanel
            }
        }
        .padding()
        .overlay {
            if showsConfetti { ConfettiBurst() }
        }
        .overlay {
            if showsIntro {
                ArenaIntroCard(allies: session.allies, enemies: session.enemies, announcement: announcement) {
                    withAnimation(.easeOut(duration: 0.3)) { showsIntro = false }
                }
                .transition(.opacity)
            }
        }
        .environment(\.colorScheme, .dark)
        .background(backdrop.ignoresSafeArea())
        .animation(.spring(duration: 0.35), value: showsResult)
        .interactiveDismissDisabled(!session.isOver)
        .sensoryFeedback(.impact(weight: .heavy), trigger: hitCounts.values.reduce(0, +)) { _, _ in hapticsOn }
        .onAppear {
            playedEvents = session.engine.events.count
            for combatant in session.engine.combatants { displayedHP[combatant.id] = combatant.hp }
            // Meeting a beast in battle (wild, story or arena) adds it to the Beastdex.
            for enemy in session.enemies { store.discover(enemy.speciesID) }
            // The announcer only introduces a fresh match, not one reopened mid-fight.
            if isArenaMatch && session.engine.events.isEmpty { showsIntro = true }
        }
        .onChange(of: session.engine.events.count) { _, count in
            let events = session.engine.events
            guard playedEvents < count, count <= events.count else { return }
            queue.append(contentsOf: events[playedEvents..<count])
            playedEvents = count
            if !isAnimating { Task { await playQueue() } }
        }
        .onChange(of: session.isOver, initial: true) { _, isOver in
            guard isOver, !session.rewardsApplied else { return }
            session.markRewardsApplied()
            // Running away earns nothing, but costs nothing either.
            guard !session.fled else { return }
            rewards = store.recordBattle(beastID: session.localBeastID, won: session.didWin,
                                         opponentLevel: session.opponentLevel, isBoss: session.isBossFight)
        }
        .onChange(of: showsResult, initial: true) { _, showing in
            guard showing, !didPlayFanfare, !session.fled else { return }
            didPlayFanfare = true
            let won = session.didWin, leveled = (rewards?.levels ?? 0) > 0
            Task {
                if !MusicPlayer.shared.playSting(won ? "sting_victory" : "sting_defeat") {
                    SoundFX.play(won ? .victory : .defeat)
                }
                if isArenaMatch && won {
                    // The Arena crowd celebrates the winner.
                    SoundFX.play(.roar)
                    crowdHype += 1
                    showsConfetti = true
                }
                guard leveled else { return }
                try? await Task.sleep(for: .milliseconds(900))
                SoundFX.play(.levelUp)
            }
        }
        .sheet(isPresented: $showLog) { BattleLogSheet(log: session.engine.log) }
        .music(musicTrack)
        .crowdAmbience(isArenaMatch)
    }

    /// The announcer's line on the intro card.
    private var announcement: String {
        let me = store.keeper.map { "\($0.name)'s \(session.local.name)" } ?? session.local.name
        let rival = session.enemies.first?.name ?? "a mystery beast"
        let partners = session.allies.map(\.name).formatted(.list(type: .and))
        switch session.kind {
        case .practice:
            return "In the ring tonight: \(me) takes on Kade's \(rival)!"
        case .raid:
            return "\(rival) storms the Arena! Can \(partners) bring it down?"
        case .online where session.allies.count > 1:
            return "Two keepers unite! \(partners) face \(rival)!"
        case .online:
            return "From across Beastopia: \(me) faces \(rival)!"
        case .story:
            return ""
        }
    }

    private var musicTrack: String {
        switch session.kind {
        case .story(let chapterID) where session.isBossFight:
            chapterID == StoryCampaign.chapters.count ? "music_finale" : "music_boss"
        case .raid: "music_boss"
        default: "music_battle"
        }
    }

    // MARK: - Layout

    private var backdrop: some View {
        BattleBackdrop(skyColor: session.enemies.first?.element.color ?? .gray,
                       groundColor: session.local.element.color,
                       art: backdropArt)
    }

    /// The region's battle art for story fights; the arena's for everything else.
    private var backdropArt: String {
        guard case .story(let chapterID) = session.kind,
              let map = AdventureMap.all.first(where: { $0.regionID == chapterID }) else { return "battle_bg_arena" }
        return "battle_bg_\(map.theme)"
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(session.title).font(.headline).lineLimit(1)
                Text("Turn \(session.engine.turn)").font(.caption.bold()).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Battle Log", systemImage: "text.bubble") { showLog = true }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
            if session.canFlee && !session.isOver {
                Button("Run", systemImage: "figure.run") {
                    SoundFX.play(.miss)
                    session.flee()
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .disabled(isAnimating)
            }
        }
    }

    private var arena: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                Spacer(minLength: 0)
                ForEach(session.enemies) { battler($0, isAlly: false) }
            }
            Spacer(minLength: 8)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(session.allies) { battler($0, isAlly: true) }
                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity)
        .background(alignment: .top) {
            if isArenaMatch { ArenaCrowdStrip(hype: crowdHype) }
        }
        // Big hits shake the whole arena, not just the target.
        // Reduce Battle Effects (Settings) keeps the arena still.
        .keyframeAnimator(initialValue: CGSize.zero, trigger: screenShakes) { content, offset in
            content.offset(reduceEffects ? .zero : offset)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(.zero, duration: 0.01)
                CubicKeyframe(CGSize(width: 9, height: -6), duration: 0.05)
                CubicKeyframe(CGSize(width: -8, height: 5), duration: 0.06)
                CubicKeyframe(CGSize(width: 6, height: 3), duration: 0.06)
                CubicKeyframe(CGSize(width: -3, height: -2), duration: 0.06)
                CubicKeyframe(.zero, duration: 0.06)
            }
        }
        .overlay {
            if let banner {
                Text(banner.text)
                    .font(.title.weight(.black))
                    .foregroundStyle(banner.color.gradient)
                    .shadow(color: .black, radius: 0, x: 2, y: 2)
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    .id(banner.id)
            }
        }
    }

    private func battler(_ combatant: Combatant, isAlly: Bool) -> some View {
        let hp = displayedHP[combatant.id] ?? combatant.hp
        let isDown = hp <= 0
        let lunge = lunging == combatant.id ? (isAlly ? CGSize(width: 34, height: -24) : CGSize(width: -34, height: 24)) : .zero
        let size: CGFloat = session.engine.combatants.count > 2 ? 78 : 104

        let sprite = ZStack {
            BattlePlatform(color: combatant.element.color, width: size * 1.35)
                .offset(y: size * 0.5)
            if let species = SpeciesDatabase.species(combatant.speciesID) {
                BeastPortrait(species: species, hue: combatant.hue, isPrismatic: combatant.isPrismatic, size: size,
                              isAnimated: true)
                    .modifier(IdleBob(isActive: !isDown))
                    .overlay {
                        Circle().fill(.white).opacity(flashing == combatant.id ? 0.75 : 0)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if combatant.guarding {
                            Image(systemName: "shield.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                                .shadow(radius: 2)
                                .transition(.scale)
                        }
                    }
                    .rotationEffect(.degrees(isDown ? (isAlly ? -80 : 80) : 0))
                    .opacity(isDown ? 0.25 : 1)
                    .saturation(isDown ? 0 : 1)
            }
            ForEach(floaters.filter { $0.combatant == combatant.id }) { floater in
                FloatingText(floater: floater)
            }
        }
        .offset(lunge)
        .keyframeAnimator(initialValue: 0.0, trigger: hitCounts[combatant.id] ?? 0) { content, x in
            content.offset(x: reduceEffects ? 0 : x)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(0, duration: 0.01)
                CubicKeyframe(12, duration: 0.05)
                CubicKeyframe(-10, duration: 0.07)
                CubicKeyframe(7, duration: 0.07)
                CubicKeyframe(-4, duration: 0.06)
                CubicKeyframe(0, duration: 0.06)
            }
        }

        let panel = CombatantPanel(combatant: combatant, displayedHP: hp,
                                   isLocal: combatant.id == session.localIndex)

        return VStack(spacing: 6) {
            if isAlly {
                sprite
                panel
            } else {
                panel
                sprite
            }
        }
        .frame(maxWidth: 180)
        .accessibilityElement(children: .combine)
    }

    private var messageBox: some View {
        Text(caption ?? idlePrompt)
            .font(.callout.bold())
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .gamePanel(cornerRadius: 14)
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.15), value: caption)
            // Battle events play out visually; speak each one so VoiceOver users can follow the fight.
            .onChange(of: caption) {
                if let caption { AccessibilityNotification.Announcement(caption).post() }
            }
    }

    private var idlePrompt: String {
        if session.isOver { return session.engine.log.last ?? "" }
        if session.local.isDown { return "\(session.local.name) is down! Your ally fights on…" }
        if session.isWaitingForPeer { return "Waiting for the other keeper…" }
        return "What will \(session.local.name) do?"
    }

    // MARK: - Commands

    private var commandPanel: some View {
        VStack(spacing: 8) {
            if session.canUseItems {
                Picker("Command", selection: $tab) {
                    ForEach(CommandTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if session.isWaitingForPeer {
                ProgressView().frame(height: 120)
            } else if tab == .bag && session.canUseItems {
                bag
            } else {
                moves
            }
        }
        .disabled(isAnimating)
        .opacity(isAnimating ? 0.6 : 1)
    }

    private var moves: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(Array(session.local.moves.enumerated()), id: \.offset) { index, move in
                Button {
                    SoundFX.play(.tap)
                    session.choose(index)
                } label: {
                    MoveButtonLabel(move: move, effectiveness: effectiveness(of: move))
                }
                .buttonStyle(GameButtonStyle(tint: move.element?.color ?? Color(white: 0.45), cornerRadius: 12))
                .disabled(!session.canChoose || session.local.guts < move.gutsCost)
            }
        }
    }

    private var bag: some View {
        let owned = ItemKind.battleItems.filter { store.count(of: $0) > 0 }
        return Group {
            if owned.isEmpty {
                ContentUnavailableView("Bag Empty", systemImage: "bag",
                                       description: Text("Buy items at a Market or find them in treasure chests."))
                    .frame(height: 140)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(owned) { item in
                            Button {
                                guard store.consume(item) else { return }
                                SoundFX.play(.tap)
                                session.use(item)
                                tab = .fight
                            } label: {
                                HStack(spacing: 10) {
                                    GameIcon(art: item.iconArt, symbol: item.symbol, size: 28)
                                        .font(.title3)
                                        .foregroundStyle(item.color)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.name).font(.subheadline.bold())
                                        Text(item.summary).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("×\(store.count(of: item))").font(.callout.monospacedDigit().bold())
                                }
                                .padding(10)
                                .background(.regularMaterial, in: .rect(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .disabled(!session.canChoose || !isUseful(item))
                            .opacity(isUseful(item) ? 1 : 0.5)
                        }
                    }
                }
                .frame(maxHeight: 170)
            }
        }
    }

    private func isUseful(_ item: ItemKind) -> Bool {
        let me = session.local
        return item.battleEffects.contains { effect in
            switch effect {
            case .heal: me.hp < me.maxHP
            case .cure: me.status != nil
            case .guts: me.guts < BattleEngine.maxGuts
            }
        }
    }

    /// How hard a move hits the first standing enemy, judged on its visible element only.
    private func effectiveness(of move: Move) -> Double {
        guard let element = move.element,
              let target = session.enemies.first(where: { !$0.isDown }) else { return 1 }
        return element.multiplier(against: target.element, hidden: nil)
    }

    // MARK: - Results

    private var resultPanel: some View {
        VStack(spacing: 10) {
            if session.fled {
                Text("Got away safely!").font(.title.bold())
            } else {
                Text(session.didWin ? "Victory!" : "Defeat")
                    .font(.largeTitle.weight(.black))
                    .foregroundStyle(session.didWin ? Color.green.gradient : Color.red.gradient)
            }
            if session.peerDisconnected {
                Text("The other keeper left the battle.").font(.callout)
            }
            if let rewards {
                VStack(spacing: 6) {
                    Label("+\(rewards.xp) XP", systemImage: "star.fill").foregroundStyle(.blue)
                    if rewards.levels > 0 {
                        Label("\(session.local.name) grew \(rewards.levels) level\(rewards.levels == 1 ? "" : "s")!",
                              systemImage: "arrow.up.circle.fill")
                            .foregroundStyle(.orange)
                    }
                    if store.beast(session.localBeastID)?.availableEvolution != nil {
                        Label("\(session.local.name) is ready to evolve! Visit the Haven.", systemImage: "sparkles")
                            .foregroundStyle(GameTheme.gold)
                            .multilineTextAlignment(.center)
                    }
                    if !rewards.loot.isEmpty {
                        Label(rewards.loot.summary, systemImage: "gift.fill")
                            .foregroundStyle(.pink)
                            .multilineTextAlignment(.center)
                    }
                    if rewards.keeperXP > 0 {
                        Label("+\(rewards.keeperXP) Keeper XP", systemImage: "person.fill").foregroundStyle(.mint)
                    }
                    if rewards.keeperRanks > 0, let keeper = store.keeper {
                        Label("\(keeper.name) reached Keeper rank \(keeper.rank)!", systemImage: "crown.fill")
                            .foregroundStyle(.yellow)
                    }
                }
                .font(.callout.bold())
                .padding(12)
                .frame(maxWidth: .infinity)
                .gamePanel(cornerRadius: 14)
            }
            Button {
                onFinish(session.didWin)
                dismiss()
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(GameButtonStyle())
        }
    }

    // MARK: - Playback

    private func playQueue() async {
        isAnimating = true
        while !queue.isEmpty {
            let event = queue.removeFirst()
            await play(event)
        }
        withAnimation {
            caption = nil
            lunging = nil
            // Re-sync in case anything changed without an event.
            for combatant in session.engine.combatants { displayedHP[combatant.id] = combatant.hp }
        }
        isAnimating = false
    }

    private func name(_ index: Int) -> String {
        session.engine.combatants.indices.contains(index) ? session.engine.combatants[index].name : ""
    }

    private func play(_ event: BattleEvent) async {
        let target = name(event.target), source = name(event.source)
        switch event.kind {
        case let .attack(move, _):
            caption = "\(source) used \(move)!"
            withAnimation(.easeOut(duration: 0.15)) { lunging = event.source }
            await pause(180)
            withAnimation(.spring(duration: 0.25)) { lunging = nil }

        case let .damage(amount, critical, effectiveness):
            SoundFX.play(critical ? .critical : .hit)
            hitCounts[event.target, default: 0] += 1
            if critical || effectiveness > 1.2 { screenShakes += 1 }
            flash(event.target)
            addFloater("−\(amount)", on: event.target, color: critical ? .yellow : .red, large: critical)
            withAnimation(.easeOut(duration: 0.45)) { displayedHP[event.target] = event.hpAfter }
            if isArenaMatch && (critical || effectiveness > 1.2) {
                SoundFX.play(.cheer)
                crowdHype += 1
            }
            if critical {
                show(Banner(text: "Critical hit!", color: .yellow))
            } else if effectiveness > 1.2 {
                show(Banner(text: "Super effective!", color: .orange))
            } else if effectiveness < 0.8 {
                caption = "It's not very effective…"
            }
            await pause(critical || effectiveness > 1.2 ? 650 : 480)

        case .miss:
            SoundFX.play(.miss)
            caption = "\(source)'s attack missed!"
            addFloater("MISS", on: event.target, color: .gray)
            await pause(420)

        case let .heal(amount):
            SoundFX.play(.heal)
            caption = "\(target) recovered \(amount) HP!"
            addFloater("+\(amount)", on: event.target, color: .green)
            withAnimation(.easeOut(duration: 0.45)) { displayedHP[event.target] = event.hpAfter }
            await pause(480)

        case .guardUp:
            SoundFX.play(.guardUp)
            caption = "\(target) braces itself and gathers Guts!"
            addFloater("GUARD", on: event.target, color: .blue)
            await pause(420)

        case let .inflicted(status):
            SoundFX.play(.hit)
            caption = "\(target) is afflicted with \(status.displayName.lowercased())!"
            addFloater(status.displayName.uppercased(), on: event.target, color: status.color)
            await pause(520)

        case let .statusDamage(status, amount):
            SoundFX.play(.hit)
            hitCounts[event.target, default: 0] += 1
            caption = "\(target) is hurt by its \(status.displayName.lowercased())!"
            addFloater("−\(amount)", on: event.target, color: status.color)
            withAnimation(.easeOut(duration: 0.45)) { displayedHP[event.target] = event.hpAfter }
            await pause(480)

        case .stunned:
            SoundFX.play(.denied)
            caption = "\(target) is shocked and can't move!"
            addFloater("STUNNED", on: event.target, color: .yellow)
            await pause(480)

        case .cured:
            SoundFX.play(.heal)
            caption = "\(target) is free of its ailment."
            addFloater("CURED", on: event.target, color: .teal)
            await pause(400)

        case let .item(item):
            SoundFX.play(.purchase)
            caption = "Used \(item.name) on \(target)!"
            await pause(380)

        case let .guts(amount):
            SoundFX.play(.guardUp)
            addFloater("+\(amount) GUTS", on: event.target, color: .orange)
            await pause(380)

        case .knockout:
            SoundFX.play(.knockout)
            if isArenaMatch {
                SoundFX.play(.roar)
                crowdHype += 1
            }
            caption = "\(target) is down!"
            withAnimation(.spring(duration: 0.5)) { displayedHP[event.target] = 0 }
            await pause(650)
        }
    }

    private func pause(_ milliseconds: Int) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    private func flash(_ index: Int) {
        flashing = index
        Task {
            await pause(90)
            withAnimation(.easeOut(duration: 0.2)) { if flashing == index { flashing = nil } }
        }
    }

    private func show(_ newBanner: Banner) {
        withAnimation(.spring(duration: 0.3, bounce: 0.5)) { banner = newBanner }
        Task {
            await pause(800)
            withAnimation(.easeIn(duration: 0.2)) { if banner?.id == newBanner.id { banner = nil } }
        }
    }

    private func addFloater(_ text: String, on combatant: Int, color: Color, large: Bool = false) {
        let floater = Floater(combatant: combatant, text: text, color: color, large: large)
        floaters.append(floater)
        Task {
            await pause(1000)
            floaters.removeAll { $0.id == floater.id }
        }
    }
}

// MARK: - Pieces

private struct Banner: Equatable {
    let id = UUID()
    let text: String
    let color: Color
}

private struct Floater: Identifiable {
    let id = UUID()
    let combatant: Int
    let text: String
    let color: Color
    var large = false
}

/// A damage number (or status word) that pops up and drifts away.
private struct FloatingText: View {
    let floater: Floater
    @State private var risen = false

    var body: some View {
        Text(floater.text)
            .font(floater.large ? .title.weight(.black) : .title3.weight(.heavy))
            .foregroundStyle(floater.color)
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            .scaleEffect(risen ? 1 : 0.5)
            .offset(y: risen ? -60 : -10)
            .opacity(risen ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.95).delay(0.05)) { risen = true }
            }
            .allowsHitTesting(false)
    }
}

/// Name, HP, Guts and ailment for one combatant.
struct CombatantPanel: View {
    let combatant: Combatant
    let displayedHP: Int
    let isLocal: Bool

    private var fraction: Double { Double(max(0, displayedHP)) / Double(max(1, combatant.maxHP)) }

    private var hpColor: Color {
        fraction < 0.25 ? .red : (fraction < 0.5 ? .yellow : .green)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                GameIcon(art: combatant.element.iconArt, symbol: combatant.element.symbol, size: 16)
                    .foregroundStyle(combatant.element.color)
                    .font(.caption)
                Text(combatant.name).font(.caption.bold()).lineLimit(1)
                if isLocal {
                    Text("YOU").font(.caption2.bold()).foregroundStyle(.tint)
                }
                Spacer(minLength: 0)
                if let status = combatant.status {
                    GameIcon(art: status.iconArt, symbol: status.symbol, size: 16)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(status.color, in: .circle)
                        .accessibilityLabel(status.displayName)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.15))
                    Capsule().fill(hpColor.gradient)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 8)
            HStack {
                Text("HP \(max(0, displayedHP))/\(combatant.maxHP)")
                Spacer()
                Text("Guts \(combatant.guts)")
                    .foregroundStyle(.orange)
            }
            .font(.caption2.monospacedDigit())
            ProgressView(value: Double(combatant.guts), total: Double(BattleEngine.maxGuts))
                .tint(.orange)
                .scaleEffect(y: 0.6)
        }
        .padding(8)
        .gamePanel(tint: combatant.element.color, cornerRadius: 12)
        .accessibilityElement(children: .combine)
    }
}

/// A move button's label: element, power, Guts cost and how well it'll land.
/// The chunky button itself comes from `GameButtonStyle`, which also dims unaffordable moves.
private struct MoveButtonLabel: View {
    let move: Move
    let effectiveness: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if move.kind != .guarding, let element = move.element {
                    GameIcon(art: element.iconArt, symbol: element.symbol, size: 18)
                } else {
                    Image(systemName: move.kind == .guarding ? "shield.fill" : "hand.raised.fill")
                }
                Text(move.name).font(.subheadline.bold()).lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(move.kind == .guarding ? "+Guts · halves damage" : "PWR \(move.power) · \(move.gutsCost) Guts")
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.85))
            if move.kind != .guarding && move.element != nil {
                if effectiveness > 1.2 {
                    effectivenessTag("SUPER EFFECTIVE")
                } else if effectiveness < 0.8 {
                    effectivenessTag("RESISTED")
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
    }

    /// A dark pill so the hint stays readable on any element color.
    private func effectivenessTag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.black))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.black.opacity(0.35), in: .capsule)
    }
}

private struct BattleLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    let log: [String]

    var body: some View {
        NavigationStack {
            List(Array(log.enumerated()), id: \.offset) { _, line in
                Text(line).font(.callout)
            }
            .navigationTitle("Battle Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    BattleView(session: .practice(beast: BeastGenerator.generate(fromCode: "BEASTOPIA")))
        .environment(GameStore())
}

extension StatusEffect {
    var color: Color {
        switch self {
        case .burn: .orange
        case .shock: .yellow
        case .blight: .purple
        }
    }
}
