//
//  MultiplayerManager.swift
//  Beastopia
//

import GameKit
import MultipeerConnectivity
import Observation
import UIKit

/// Live Beast Arena matches, online over Game Center or nearby over Wi-Fi and Bluetooth.
///
/// Uses deterministic lockstep: both peers exchange their beast and a random nonce,
/// derive the same battle seed, then only send move choices each turn. Each device
/// runs `BattleEngine` locally and arrives at identical results. The two transports
/// carry exactly the same messages.
@Observable
final class MultiplayerManager: NSObject {
    enum Mode: Int, Codable, CaseIterable, Identifiable {
        case versus = 1, coop = 2
        var id: Int { rawValue }
        var title: String { self == .versus ? "Versus" : "Co-op Raid" }
    }

    /// How the two devices are connected.
    enum Transport: Equatable {
        /// Matchmaking with keepers anywhere, over the internet.
        case gameCenter
        /// Peer-to-peer with a keeper in the same room, over Wi-Fi or Bluetooth. No internet
        /// or Game Center account needed.
        case nearby
    }

    enum Status: Equatable {
        case signedOut
        case ready
        case searching
        case handshaking
        case inBattle
        case failed(String)
    }

    /// Wire format. Remote data is untrusted and is validated on receipt.
    private enum Message: Codable {
        case hello(beast: Beast, nonce: UInt64)
        case action(turn: Int, move: Int)
        case forfeit
    }

    private(set) var status: Status = .signedOut
    private(set) var session: BattleSession?
    private(set) var opponentName = ""

    private var match: GKMatch?
    private(set) var transport: Transport = .gameCenter
    private var mode: Mode = .versus
    // Nearby play (MultipeerConnectivity).
    private var nearbySession: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    /// A random token in our advertisement. When two keepers find each other, the lower token invites,
    /// so they don't both invite at once.
    private var nearbyToken = ""

    /// Bonjour service type. Must match `NSBonjourServices` in the Info.plist.
    static let nearbyServiceType = "bstopia-arena"

    /// Devices only pair with the same build, because lockstep battles need identical battle math.
    private static var buildID: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "0")-\(info?["CFBundleVersion"] as? String ?? "0")"
    }
    private var localBeast: Beast?
    private var localNonce: UInt64 = 0
    private var hasEchoedHello = false
    private var remoteIndex: Int?

    var isAuthenticated: Bool { GKLocalPlayer.local.isAuthenticated }

    // MARK: - Authentication

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                guard let self else { return }
                if let viewController {
                    Self.topViewController()?.present(viewController, animated: true)
                } else if GKLocalPlayer.local.isAuthenticated {
                    if self.status == .signedOut { self.status = .ready }
                } else {
                    self.status = .failed(error?.localizedDescription ?? "Sign in to Game Center to play online.")
                }
            }
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    // MARK: - Matchmaking

    func findMatch(mode: Mode, beast: Beast) async {
        guard isAuthenticated else {
            status = .failed("Sign in to Game Center to play online.")
            return
        }
        leave()
        transport = .gameCenter
        self.mode = mode
        localBeast = beast
        localNonce = .random(in: .min ... .max)
        status = .searching

        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        // Keep versus and co-op players in separate matchmaking pools.
        request.playerGroup = mode.rawValue

        do {
            let match = try await GKMatchmaker.shared().findMatch(for: request)
            self.match = match
            match.delegate = self
            status = .handshaking
            sendHello()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Looks for a keeper nearby who picked the same match type, and connects automatically.
    func findNearbyMatch(mode: Mode, beast: Beast, keeperName: String) {
        leave()
        transport = .nearby
        self.mode = mode
        localBeast = beast
        localNonce = .random(in: .min ... .max)
        nearbyToken = UUID().uuidString

        let peer = MCPeerID(displayName: String((keeperName.isEmpty ? "Glyphkeeper" : keeperName).prefix(30)))
        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        nearbySession = session

        let info = ["mode": "\(mode.rawValue)", "build": Self.buildID, "token": nearbyToken]
        let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: info, serviceType: Self.nearbyServiceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.nearbyServiceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
        status = .searching
    }

    func cancelSearch() {
        if transport == .nearby {
            stopNearby()
        } else {
            GKMatchmaker.shared().cancel()
        }
        status = isAuthenticated ? .ready : .signedOut
    }

    /// Whether a keeper can look for a nearby match: always, since it needs no account.
    var canSearchNearby: Bool {
        switch status {
        case .searching, .handshaking: false
        default: true
        }
    }

    private func stopNearby() {
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
        nearbySession?.delegate = nil
        nearbySession?.disconnect()
        nearbySession = nil
    }

    func leave() {
        if session?.isOver == false { sendToPeer(.forfeit) }
        match?.delegate = nil
        match?.disconnect()
        match = nil
        stopNearby()
        session = nil
        remoteIndex = nil
        hasEchoedHello = false
        if status != .signedOut { status = isAuthenticated ? .ready : .signedOut }
    }

    // MARK: - Messaging

    private func sendHello() {
        guard let localBeast else { return }
        sendToPeer(.hello(beast: localBeast, nonce: localNonce))
    }

    /// Sends over whichever transport is connected.
    private func sendToPeer(_ message: Message) {
        if let match {
            send(message, over: match)
        } else if let nearbySession, !nearbySession.connectedPeers.isEmpty {
            do {
                let data = try JSONEncoder().encode(message)
                try nearbySession.send(data, toPeers: nearbySession.connectedPeers, with: .reliable)
            } catch {
                status = .failed("Connection error: \(error.localizedDescription)")
            }
        }
    }

    private func send(_ message: Message, over match: GKMatch) {
        do {
            let data = try JSONEncoder().encode(message)
            try match.sendData(toAllPlayers: data, with: .reliable)
        } catch {
            status = .failed("Connection error: \(error.localizedDescription)")
        }
    }

    private func handle(_ data: Data, from playerID: String, displayName: String) {
        guard data.count < 16_384, let message = try? JSONDecoder().decode(Message.self, from: data) else { return }

        switch message {
        case let .hello(beast, nonce):
            // Echo once in case our first hello arrived before the peer was listening.
            if !hasEchoedHello {
                hasEchoedHello = true
                sendHello()
            }
            guard session == nil else { return }
            opponentName = displayName
            startBattle(remoteBeast: Self.sanitized(beast), remoteNonce: nonce, remotePlayerID: playerID)
        case let .action(turn, move):
            guard let session, let remoteIndex else { return }
            session.receive(turn: turn, moveIndex: move, from: remoteIndex)
        case .forfeit:
            session?.peerDisconnected = true
        }
    }

    /// Clamps a peer-supplied beast to legal values. Internal so tests can check it.
    static func sanitized(_ beast: Beast) -> Beast {
        var clean = beast
        if SpeciesDatabase.species(beast.speciesID) == nil {
            clean.speciesID = SpeciesDatabase.rookiePool[0].id
        }
        for kind in StatKind.allCases {
            // Decoding fills `Stats` directly and skips its clamping setter, so clamp here.
            clean.stats[kind] = min(max(beast.stats[kind], 1), Stats.cap)
        }
        clean.level = min(max(beast.level, 1), 99)
        clean.nickname = String(beast.nickname.prefix(20))
        return clean
    }

    private func startBattle(remoteBeast: Beast, remoteNonce: UInt64, remotePlayerID: String) {
        guard let localBeast else { return }
        // Both peers sort by player ID so they agree on combatant order, and XOR
        // the nonces so they agree on the seed without trusting either side alone.
        // Nearby peers have no player IDs, so they compare nonces instead.
        let localFirst = transport == .nearby
            ? Self.isLocalFirst(localNonce: localNonce, remoteNonce: remoteNonce)
            : GKLocalPlayer.local.gamePlayerID < remotePlayerID
        let seed = localNonce ^ remoteNonce

        let newSession: BattleSession
        switch mode {
        case .versus:
            let first = localFirst ? localBeast : remoteBeast
            let second = localFirst ? remoteBeast : localBeast
            let combatants = [
                Combatant(index: 0, beast: first, side: 0, controller: localFirst ? .local : .remote),
                Combatant(index: 1, beast: second, side: 1, controller: localFirst ? .remote : .local),
            ]
            newSession = BattleSession(kind: .online, title: transport == .nearby ? "Nearby Versus" : "Beast Arena: Versus",
                                       engine: BattleEngine(combatants: combatants, seed: seed),
                                       localIndex: localFirst ? 0 : 1, localBeastID: localBeast.id,
                                       opponentLevel: remoteBeast.level)
        case .coop:
            newSession = BattleSession.raid(beast: localBeast, ally: remoteBeast, allyController: .remote,
                                            localFirst: localFirst, seed: seed)
        }

        remoteIndex = localFirst ? 1 : 0
        newSession.sendChoice = { [weak self] turn, move in
            self?.sendToPeer(.action(turn: turn, move: move))
        }
        session = newSession
        status = .inBattle
    }
}

// MARK: - Nearby (MultipeerConnectivity)

extension MultiplayerManager: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    /// Who goes first in a nearby match. Both devices get opposite answers from the same two nonces.
    static func isLocalFirst(localNonce: UInt64, remoteNonce: UInt64) -> Bool {
        localNonce < remoteNonce
    }

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let name = peerID.displayName
        Task { @MainActor in
            guard session === self.nearbySession else { return }
            switch state {
            case .connected:
                // One opponent is enough: stop looking and say hello.
                self.advertiser?.stopAdvertisingPeer()
                self.browser?.stopBrowsingForPeers()
                self.opponentName = name
                self.status = .handshaking
                self.sendHello()
            case .notConnected:
                if let battle = self.session {
                    battle.peerDisconnected = true
                } else if self.status == .handshaking {
                    self.status = .failed("\(name) disconnected before the battle began.")
                }
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let name = peerID.displayName
        Task { @MainActor in
            guard session === self.nearbySession else { return }
            self.handle(data, from: name, displayName: name)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String,
                             fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {}

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        nonisolated(unsafe) let handler = invitationHandler
        let invitedMode = context.flatMap { String(data: $0, encoding: .utf8) }
        Task { @MainActor in
            // Only join a keeper looking for the same match, on the same build, while still searching.
            let expected = "\(self.mode.rawValue)|\(Self.buildID)"
            guard let session = self.nearbySession, self.status == .searching, invitedMode == expected,
                  session.connectedPeers.isEmpty else {
                handler(false, nil)
                return
            }
            handler(true, session)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.status = .failed("Couldn't look for nearby keepers: \(message)") }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        nonisolated(unsafe) let peer = peerID
        Task { @MainActor in
            guard let session = self.nearbySession, self.status == .searching, session.connectedPeers.isEmpty,
                  info?["mode"] == "\(self.mode.rawValue)", info?["build"] == Self.buildID,
                  let token = info?["token"], token > self.nearbyToken else { return }
            // The keeper with the lower token sends the invite; the other one accepts it.
            let context = Data("\(self.mode.rawValue)|\(Self.buildID)".utf8)
            browser.invitePeer(peer, to: session, withContext: context, timeout: 20)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.status = .failed("Couldn't look for nearby keepers: \(message)") }
    }
}

// MARK: - GKMatchDelegate

extension MultiplayerManager: GKMatchDelegate {
    nonisolated func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        let playerID = player.gamePlayerID
        let name = player.displayName
        Task { @MainActor in
            self.handle(data, from: playerID, displayName: name)
        }
    }

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        guard state == .disconnected else { return }
        Task { @MainActor in
            self.session?.peerDisconnected = true
            if self.session == nil { self.status = .failed("Your opponent left before the battle began.") }
        }
    }

    nonisolated func match(_ match: GKMatch, didFailWithError error: (any Error)?) {
        let message = error?.localizedDescription ?? "The match ended unexpectedly."
        Task { @MainActor in
            self.status = .failed(message)
        }
    }
}
