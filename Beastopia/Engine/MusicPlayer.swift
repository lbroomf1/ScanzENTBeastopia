//
//  MusicPlayer.swift
//  Beastopia
//

import AVFoundation
import SwiftUI

/// Background music and stings, from the `.m4a` files in `Audio/`.
///
/// Screens ask for a track with `.music("music_haven")`. Requests stack: the newest screen on top
/// wins, and when it goes away (a battle sheet closing, a tab switching) the track underneath
/// comes back. Changing track crossfades. Follows the same Sound setting as `SoundFX`.
@MainActor
final class MusicPlayer {
    static let shared = MusicPlayer()

    private static let baseVolume: Float = 0.55
    private static let fade: TimeInterval = 0.8

    private var requests: [(id: UUID, track: String)] = []
    private var current: (track: String, player: AVAudioPlayer)?
    private var sting: AVAudioPlayer?

    /// Music and stings follow the Music setting (and the master Sound switch).
    private var isEnabled: Bool { GameSettings.isMusicOn }
    private var volume: Float { Self.baseVolume * GameSettings.musicVolume }

    private init() {}

    /// Adds or replaces the track a screen wants.
    func request(_ track: String, id: UUID) {
        if let index = requests.firstIndex(where: { $0.id == id }) {
            requests[index].track = track
        } else {
            requests.append((id, track))
        }
        update()
    }

    func release(id: UUID) {
        requests.removeAll { $0.id == id }
        update()
    }

    /// Call after a sound setting changes.
    func settingsChanged() {
        update()
        current?.player.setVolume(volume, fadeDuration: 0.2)
    }

    /// Plays a one-shot sting over the music, ducking it meanwhile.
    /// Returns `false` if the sting isn't available, so the caller can fall back to a synthesized cue.
    @discardableResult
    func playSting(_ name: String) -> Bool {
        guard isEnabled, let player = Self.player(for: name) else { return false }
        sting = player
        player.volume = GameSettings.musicVolume
        player.play()
        if let music = current?.player {
            music.setVolume(volume * 0.25, fadeDuration: 0.2)
            Task {
                try? await Task.sleep(for: .seconds(player.duration))
                // Only restore if the same track is still playing.
                if current?.player === music { music.setVolume(volume, fadeDuration: Self.fade) }
            }
        }
        return true
    }

    private func update() {
        let wanted = isEnabled ? requests.last?.track : nil
        guard wanted != current?.track else { return }

        if let old = current?.player {
            old.setVolume(0, fadeDuration: Self.fade)
            Task {
                try? await Task.sleep(for: .seconds(Self.fade))
                old.stop()
            }
        }
        current = nil

        guard let wanted, let player = Self.player(for: wanted) else { return }
        player.numberOfLoops = -1
        player.volume = 0
        player.play()
        player.setVolume(volume, fadeDuration: Self.fade)
        current = (wanted, player)
    }

    private static func player(for name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a") else { return nil }
        return try? AVAudioPlayer(contentsOf: url)
    }
}

extension MapTheme {
    /// The region's music track.
    var musicTrack: String {
        switch self {
        case .meadow: "music_haven"
        case .volcano: "music_caldera"
        case .coast: "music_coast"
        case .forest: "music_wilds"
        case .peaks: "music_skyreach"
        case .quarry: "music_quarry"
        case .marsh: "music_voltmarsh"
        case .spire: "music_spire"
        case .interior: "music_haven"
        }
    }
}

private struct MusicRequest: ViewModifier {
    let track: String
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { MusicPlayer.shared.request(track, id: id) }
            .onChange(of: track) { _, new in MusicPlayer.shared.request(new, id: id) }
            .onDisappear { MusicPlayer.shared.release(id: id) }
    }
}

extension View {
    /// Plays `track` while this view is on screen (see `MusicPlayer`).
    func music(_ track: String) -> some View {
        modifier(MusicRequest(track: track))
    }
}
