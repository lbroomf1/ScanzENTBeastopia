//
//  ArenaView.swift
//  Beastopia
//

import SpriteKit
import SwiftUI

/// The Arena tab: the entrance to the Beast Arena. Walking in opens the Arena Hall.
struct ArenaView: View {
    @Environment(GameStore.self) private var store
    @State private var inHall = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer()
                VStack(spacing: 6) {
                    Text("Beast Arena")
                        .font(.largeTitle.weight(.heavy))
                    Text("Spar with Kade in the ring, raid with a Haven ally, or battle keepers online.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                if let partner = store.partner {
                    BeastPortrait(beast: partner, size: 112, isAnimated: true)
                        .modifier(IdleBob())
                    Text("Fighter: \(partner.displayName) · Lv \(partner.level)")
                        .font(.subheadline.bold())
                }
                Spacer()
                Button {
                    SoundFX.play(.tap)
                    inHall = true
                } label: {
                    Label("Enter the Arena", systemImage: "door.left.hand.open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GameButtonStyle())
                .disabled(store.beasts.isEmpty)
                if store.beasts.isEmpty {
                    Text("Scan a code to awaken a beast before entering the Arena.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .menuBackground("battle_bg_arena", scrim: 0.3)
            .settingsButton()
            .fullScreenCover(isPresented: $inHall) { ArenaHallView().music("music_title") }
        }
    }
}

/// The walkable Arena Hall. Talk to a host to start that kind of match; the market and hot spring
/// work like the ones in story regions. Walk out the bottom door (or tap Leave) to go back.
struct ArenaHallView: View {
    @Environment(GameStore.self) private var store
    @Environment(MultiplayerManager.self) private var multiplayer
    @Environment(\.dismiss) private var dismiss
    @AppStorage("adventure.controlMode") private var controlMode: AdventureScene.ControlMode = .tap

    @State private var scene: AdventureScene?
    @State private var host: AdventureMap.ArenaHost?
    @State private var facility: Facility?
    /// A battle chosen at a host's desk, started once its sheet has closed.
    @State private var pendingBattle: BattleSession?
    @State private var localBattle: BattleSession?
    @State private var onlineBattle: BattleSession?
    /// When the crowd last cheered out loud, so walking past the stands doesn't stack cheers.
    @State private var lastCheer = Date.distantPast

    private let map = AdventureMap.arena
    private var isBusy: Bool { host != nil || facility != nil || localBattle != nil || onlineBattle != nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let scene {
                SpriteView(scene: scene)
                    .ignoresSafeArea()
                    .mapAccessibility(label: "Arena Hall",
                                      value: "Three hosts start matches: Practice, Haven Raid and Online.",
                                      actions: hallActions)
            }
        }
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) { controls }
        .crowdAmbience()
        .onAppear { if scene == nil { buildScene() } }
        .onChange(of: isBusy) { scene?.isInputEnabled = !isBusy }
        .onChange(of: controlMode) { scene?.controlMode = controlMode }
        .onChange(of: store.fieldAbilities) { scene?.abilities = store.fieldAbilities }
        // An online match was found: close the desk, then the battle opens from its onDismiss.
        .onChange(of: multiplayer.session?.id) {
            guard let session = multiplayer.session else { return }
            if host != nil { host = nil } else { onlineBattle = session }
        }
        .sheet(item: $host, onDismiss: startPendingBattle) { host in
            ArenaDeskSheet(host: host) { pendingBattle = $0 }
        }
        .sheet(item: $facility) { FacilitySheet(facility: $0) }
        .fullScreenCover(item: $localBattle) { BattleView(session: $0) }
        .fullScreenCover(item: Binding(
            get: { onlineBattle },
            set: { if $0 == nil { onlineBattle = nil; multiplayer.leave() } }
        )) { BattleView(session: $0) }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button("Leave", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.headline)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text("Beast Arena").font(.footnote.bold())
                Text("Talk to a host to start a match").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
            Spacer()
            if let partner = store.partner {
                BeastPortrait(beast: partner, size: 40)
                    .padding(2)
                    .background(.regularMaterial, in: .circle)
                    .accessibilityLabel("Fighter: \(partner.displayName)")
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var controls: some View {
        if controlMode == .joystick {
            HStack(alignment: .bottom) {
                Joystick(onChange: { primary, secondary in
                    scene?.secondaryDirection = secondary
                    scene?.heldDirection = primary
                }, onStep: { scene?.step($0) })
                Spacer()
                Button {
                    scene?.interactWithNearby()
                } label: {
                    Text("A")
                        .font(.title.bold())
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(Color.accentColor.gradient, in: .circle)
                        .shadow(radius: 4)
                }
                .accessibilityLabel("Talk or interact")
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
        }
    }

    /// VoiceOver actions: walk to each host or station, or leave.
    private var hallActions: [MapAccessibilityAction] {
        var actions = AdventureMap.ArenaHost.allCases.map { host in
            MapAccessibilityAction(name: "Go to \(host.title)") { scene?.walkToInteract(objectiveID: host.rawValue) }
        }
        for (tile, facility) in map.stations.sorted(by: { $0.value.name < $1.value.name }) {
            actions.append(MapAccessibilityAction(name: "Use \(facility.name)") { scene?.walkToStation(at: tile) })
        }
        actions.append(MapAccessibilityAction(name: "Leave the Arena") { dismiss() })
        return actions
    }

    private func buildScene() {
        let styles: [String: AdventureScene.EntityStyle] = [
            AdventureMap.ArenaHost.practice.rawValue: .init(name: "Practice", symbol: "figure.boxing",
                                                            color: .systemOrange, art: "npc_ch3-kade"),
            AdventureMap.ArenaHost.raid.rawValue: .init(name: "Haven Raid", symbol: "person.2.fill",
                                                        color: .systemPurple, art: "npc_ch6-rook"),
            AdventureMap.ArenaHost.online.rawValue: .init(name: "Online", symbol: "globe",
                                                          color: .systemTeal, art: "npc_ch5-wren"),
        ]
        let newScene = AdventureScene(map: map, start: map.start, entityStyles: styles, exitNames: [0: "Leave Arena"])
        newScene.controlMode = controlMode
        if let keeper = store.keeper {
            newScene.playerColor = UIColor(keeper.color.color)
            newScene.playerSymbol = keeper.style.symbol
        }
        newScene.abilities = store.fieldAbilities
        newScene.addArenaAmbience()
        newScene.onInteract = { id in
            SoundFX.play(.tap)
            host = AdventureMap.ArenaHost(rawValue: id)
        }
        newScene.onFacility = { facility in
            SoundFX.play(.tap)
            self.facility = facility
        }
        var wasInRing = false
        newScene.onStep = { [weak newScene] tile, _ in
            if map.exits[tile] != nil { dismiss() }
            let inRing = AdventureScene.isInArenaRing(tile)
            defer { wasInRing = inRing }
            if inRing && !wasInRing {
                // Stepping onto the sand gets the whole crowd on its feet.
                newScene?.cheerCrowd(nearColumn: nil)
                cheer(force: true)
            } else if tile.row <= 4 && (5...14).contains(tile.col) {
                // Walking past the arena building (cols 8–11): the nearby fans cheer you on.
                newScene?.cheerCrowd(nearColumn: tile.col)
                cheer()
            }
        }
        scene = newScene
    }

    /// Plays a crowd cheer, at most every few seconds unless `force` is set.
    private func cheer(force: Bool = false) {
        guard force || Date.now.timeIntervalSince(lastCheer) > 4 else { return }
        lastCheer = .now
        SoundFX.play(.cheer)
    }

    private func startPendingBattle() {
        if let pendingBattle {
            localBattle = pendingBattle
            self.pendingBattle = nil
        } else if let session = multiplayer.session {
            onlineBattle = session
        }
    }
}

extension AdventureMap.ArenaHost: Identifiable {
    var id: String { rawValue }

    var title: String {
        switch self {
        case .practice: "Practice vs. Rival"
        case .raid: "Haven Raid"
        case .online: "Online Matches"
        }
    }
}

/// A host's desk in the Arena Hall: pick a fighter (and ally) and start that kind of match.
struct ArenaDeskSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(MultiplayerManager.self) private var multiplayer
    @Environment(\.dismiss) private var dismiss

    let host: AdventureMap.ArenaHost
    /// Hands the chosen battle to the hall, which opens it after this sheet closes.
    let onBattle: (BattleSession) -> Void

    @State private var selectedBeast: UUID?
    @State private var allyBeast: UUID?
    @State private var showCard = false
    @State private var cardError: String?
    @State private var nfc = ChallengeCardNFC()

    private var beast: Beast? { selectedBeast.flatMap(store.beast) ?? store.partner }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(intro).font(.callout)
                }
                Section("Your Fighter") {
                    BeastPicker(selection: $selectedBeast)
                        .listRowInsets(EdgeInsets())
                        .padding(.vertical, 8)
                }
                switch host {
                case .practice:
                    Section {
                        Button("Start Practice", systemImage: "figure.boxing") {
                            guard let beast else { return }
                            onBattle(.practice(beast: store.battleReady(beast)))
                            dismiss()
                        }
                        .font(.headline)
                    } footer: {
                        Text("Kade's rival beast is matched to within a level or two of your fighter.")
                    }
                case .raid:
                    raidSection
                case .online:
                    onlineSection
                }
            }
            .menuBackground("menu_bg_main")
            .navigationTitle(host.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .onAppear { selectedBeast = selectedBeast ?? store.partner?.id }
        }
        .presentationDetents([.medium, .large])
    }

    private var intro: String {
        switch host {
        case .practice: "Kade: \"Warm-up round? I'll go easy on you. Maybe.\""
        case .raid: "Rook: \"Raids are tough alone. Bring a second beast from your Haven and it'll fight beside you.\""
        case .online: "Wren: \"I carry challenges between keepers all over Beastopia: online, across the room, or on a Challenge Card. How do you want to fight?\""
        }
    }

    @ViewBuilder
    private var raidSection: some View {
        if store.beasts.count < 2 {
            Section {
                Text("You need at least two beasts for a Haven Raid.").foregroundStyle(.secondary)
            }
        } else {
            Section("Your Ally") {
                BeastPicker(selection: $allyBeast, excluding: Set([beast?.id].compactMap { $0 }))
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, 8)
            }
            Section {
                Button("Start Raid", systemImage: "person.2.fill") { startRaid() }
                    .font(.headline)
            } footer: {
                Text("Your ally fights alongside you under AI control against a corrupted apex beast.")
            }
        }
    }

    @ViewBuilder
    private var onlineSection: some View {
        Section {
            switch multiplayer.transport == .gameCenter ? multiplayer.status : .ready {
            case .signedOut:
                Button("Sign In to Game Center", systemImage: "gamecontroller.fill") { multiplayer.authenticate() }
            case .ready, .inBattle:
                if multiplayer.isAuthenticated {
                    ForEach(MultiplayerManager.Mode.allCases) { mode in
                        Button("Find \(mode.title) Match", systemImage: mode == .versus ? "flag.2.crossed.fill" : "shield.lefthalf.filled") {
                            guard let beast else { return }
                            // The peer receives the boosted beast, so both devices simulate the same fight.
                            let fighter = store.battleReady(beast)
                            Task { await multiplayer.findMatch(mode: mode, beast: fighter) }
                        }
                    }
                } else {
                    Button("Sign In to Game Center", systemImage: "gamecontroller.fill") { multiplayer.authenticate() }
                }
            case .searching, .handshaking:
                searchingRow
            case .failed(let message):
                Text(message).foregroundStyle(.red)
                Button("Try Again") { multiplayer.leave(); multiplayer.authenticate() }
            }
        } header: {
            Label("Online · Game Center", systemImage: "globe")
        } footer: {
            Text("Versus: battle another keeper's beast. Co-op Raid: team up against a corrupted apex beast.")
        }

        Section {
            switch multiplayer.transport == .nearby ? multiplayer.status : .ready {
            case .searching, .handshaking:
                searchingRow
            case .failed(let message):
                Text(message).foregroundStyle(.red)
                Button("Try Again") { multiplayer.leave() }
            default:
                ForEach(MultiplayerManager.Mode.allCases) { mode in
                    Button("Nearby \(mode.title)", systemImage: mode == .versus ? "wifi" : "person.2.wave.2.fill") {
                        guard let beast else { return }
                        multiplayer.findNearbyMatch(mode: mode, beast: store.battleReady(beast),
                                                    keeperName: store.keeper?.name ?? "Glyphkeeper")
                    }
                }
            }
        } header: {
            Label("Nearby · Wi-Fi & Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
        } footer: {
            Text("Battle a keeper in the same room, with no internet or Game Center needed. Both of you pick the same match type and you'll connect automatically. You both need the same version of Beastopia.")
        }

        Section {
            Button("Show My Challenge Card", systemImage: "qrcode") { showCard = true }
            if ChallengeCardNFC.isAvailable {
                Button("Tap a Challenge Card (NFC)", systemImage: "wave.3.right") { readNFCCard() }
            }
            if let cardError {
                Text(cardError).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Label("Challenge Cards", systemImage: "rectangle.portrait.on.rectangle.portrait.angled.fill")
        } footer: {
            Text("Share your fighter as a QR code, or write it to an NFC sticker. Anyone who scans it fights an AI ghost of your beast, any time, anywhere. Scan a friend's QR code from the Scan tab.")
        }
        .sheet(isPresented: $showCard) {
            if let beast {
                ChallengeCardSheet(card: ChallengeCard(keeperName: store.keeper?.name ?? "Glyphkeeper",
                                                       beast: store.battleReady(beast)), beast: beast)
            }
        }
    }

    private var searchingRow: some View {
        Group {
            HStack {
                ProgressView()
                Text(multiplayer.status == .searching
                     ? (multiplayer.transport == .nearby ? "Looking for keepers nearby…" : "Searching for keepers…")
                     : "Connecting…")
            }
            Button("Cancel", role: .cancel) { multiplayer.cancelSearch() }
        }
    }

    /// Reads a Challenge Card from an NFC tag and starts the fight against its ghost.
    private func readNFCCard() {
        cardError = nil
        Task {
            do {
                let text = try await nfc.read()
                guard let card = ChallengeCard(payload: text), let beast else {
                    cardError = "That card is damaged or from a newer version."
                    return
                }
                onBattle(.challenge(card, beast: store.battleReady(beast)))
                dismiss()
            } catch ChallengeCardNFC.NFCError.cancelled {
                return
            } catch {
                cardError = error.localizedDescription
            }
        }
    }

    private func startRaid() {
        guard let beast else { return }
        let ally = allyBeast.flatMap(store.beast) ?? store.beasts.first { $0.id != beast.id }
        guard let ally else { return }
        onBattle(.raid(beast: store.battleReady(beast), ally: store.battleReady(ally), allyController: .ai, localFirst: true,
                       seed: .random(in: .min ... .max)))
        dismiss()
    }
}

/// Your fighter as a Challenge Card: a QR code to show or share, and an NFC sticker to write.
struct ChallengeCardSheet: View {
    @Environment(\.dismiss) private var dismiss
    let card: ChallengeCard
    let beast: Beast

    @State private var nfc = ChallengeCardNFC()
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        BeastPortrait(beast: beast, size: 64)
                        VStack(alignment: .leading) {
                            Text(beast.displayName).font(.headline)
                            Text("Lv \(beast.level) · \(beast.species.element.displayName) · \(card.keeperName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    if let image = card.qrImage {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 280)
                            .padding(12)
                            .background(.white, in: .rect(cornerRadius: 16))
                            .accessibilityLabel("Challenge Card QR code for \(beast.displayName)")
                        ShareLink(item: Image(uiImage: image),
                                  preview: SharePreview("\(card.keeperName)'s Challenge Card", image: Image(uiImage: image))) {
                            Label("Share Card", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    if ChallengeCardNFC.isAvailable {
                        Button {
                            write()
                        } label: {
                            Label("Write to NFC Sticker", systemImage: "wave.3.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("Friends scan the QR code in their Scan tab, or tap the NFC sticker at Wren's desk, to fight a ghost of your beast with your Keeper boosts. NFC needs an NTAG215 or larger sticker. The card is a snapshot: make a new one after your beast grows.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Challenge Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func write() {
        message = nil
        Task {
            do {
                try await nfc.write(card)
                message = "Written! Anyone who taps this sticker can challenge \(beast.displayName)."
                SoundFX.play(.purchase)
            } catch ChallengeCardNFC.NFCError.cancelled {
                return
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
