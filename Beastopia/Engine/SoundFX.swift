//
//  SoundFX.swift
//  Beastopia
//

import AVFoundation
import OSLog
import SwiftUI
import UIKit

/// Short sound effects with matching haptics, played the moment the player acts.
/// Every sound is synthesized in code, so the game ships without audio assets.
@MainActor
final class SoundFX {
    enum Cue: CaseIterable {
        case tap, train, feed, rest, levelUp, evolve, purchase, denied
        case primary, release, summon, fuse
        case hit, critical, miss, guardUp, heal, knockout, victory, defeat
        /// Arena crowd reactions: a short cheer, and a long roar for knockouts and wins.
        case cheer, roar
    }

    nonisolated static let enabledKey = "soundEnabled"
    static let shared = SoundFX()

    static func play(_ cue: Cue) { shared.play(cue) }

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
    /// A small pool so overlapping sounds (e.g. a hit right after a level-up) don't cut each other off.
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [Cue: AVAudioPCMBuffer] = [:]
    /// Loops the Arena crowd's murmur under the music, separate from the one-shot pool.
    private let crowdPlayer = AVAudioPlayerNode()
    private var crowdHolds = 0
    private var crowdLoop: AVAudioPCMBuffer?
    /// Crowd sounds are seconds of filtered noise, too slow to synthesize on the main thread, so they're
    /// rendered in the background when the crowd first starts. Until then they're skipped rather than waited on.
    private var isPreparingCrowd = false
    private static let crowdCues: [Cue] = [.cheer, .roar]

    private static let crowdBaseVolume: Float = 0.5

    private init() {
        // Ambient: respects the silent switch and mixes with the player's music.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        guard let format else { return }
        for _ in 0..<4 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        engine.attach(crowdPlayer)
        engine.connect(crowdPlayer, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.6
        applyVolumes()
    }

    /// Call after a sound setting changes.
    func settingsChanged() {
        applyVolumes()
        updateCrowd()
    }

    private func applyVolumes() {
        for player in players { player.volume = GameSettings.effectsVolume }
        crowdPlayer.volume = Self.crowdBaseVolume * GameSettings.crowdVolume
    }

    /// The Arena crowd has its own setting; every other cue follows Sound Effects.
    private func isEnabled(_ cue: Cue) -> Bool {
        Self.crowdCues.contains(cue) ? GameSettings.isCrowdOn : GameSettings.areEffectsOn
    }

    /// Starts the Arena crowd murmur. Holds nest, so the Arena Hall and an Arena battle on top of it
    /// can both ask for it; it stops once every holder has called `stopCrowd()`.
    func startCrowd() {
        crowdHolds += 1
        prepareCrowdSounds()
        updateCrowd()
    }

    private func prepareCrowdSounds() {
        guard crowdLoop == nil, !isPreparingCrowd, let format else { return }
        isPreparingCrowd = true
        let loopTones = Self.crowdMurmur()
        let cueTones = Self.crowdCues.map { ($0, tones(for: $0)) }
        Task {
            let rendered = await Task.detached(priority: .utility) {
                (loop: Self.render(loopTones, format: format),
                 cues: cueTones.compactMap { cue, tones in Self.render(tones, format: format).map { (cue, $0) } })
            }.value
            crowdLoop = rendered.loop
            for (cue, buffer) in rendered.cues { buffers[cue] = buffer }
            isPreparingCrowd = false
            updateCrowd()
        }
    }

    func stopCrowd() {
        crowdHolds = max(0, crowdHolds - 1)
        updateCrowd()
    }

    private func updateCrowd() {
        let wanted = crowdHolds > 0 && GameSettings.isCrowdOn
        guard wanted != crowdPlayer.isPlaying else { return }
        if wanted {
            guard let crowdLoop, startIfNeeded() else { return }
            crowdPlayer.scheduleBuffer(crowdLoop, at: nil, options: .loops)
            crowdPlayer.play()
        } else {
            crowdPlayer.stop()
        }
    }

    func play(_ cue: Cue) {
        haptic(for: cue)
        guard isEnabled(cue), !players.isEmpty, let buffer = buffer(for: cue), startIfNeeded() else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.scheduleBuffer(buffer)
        player.play()
    }

    private func startIfNeeded() -> Bool {
        if engine.isRunning { return true }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            return true
        } catch {
            Logger(subsystem: "Beastopia", category: "Audio").error("Audio unavailable: \(error, privacy: .private)")
            return false
        }
    }

    // MARK: - Haptics

    private func haptic(for cue: Cue) {
        guard GameSettings.isHapticsOn else { return }
        switch cue {
        case .tap, .primary:
            UISelectionFeedbackGenerator().selectionChanged()
        case .train, .feed:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .rest, .release, .heal:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .hit:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .critical:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .guardUp, .knockout:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .levelUp, .evolve, .purchase, .summon, .fuse, .victory:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .denied, .defeat:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .miss, .cheer, .roar:
            break
        }
    }

    // MARK: - Synthesis

    /// `murmur` is low-passed noise with a slow wobble, like many voices blurred together.
    /// Its frequency is the filter cutoff rather than a pitch.
    private nonisolated enum Wave: Sendable { case sine, square, triangle, noise, murmur }

    /// `pluck` hits and decays (most cues), `swell` rises and falls (crowd cheers), `steady` holds (loops).
    private nonisolated enum Envelope: Sendable { case pluck, swell, steady }

    /// One voice in a cue. Frequency glides from `from` to `to` over its duration.
    private nonisolated struct Tone: Sendable {
        var start: Double
        var duration: Double
        var from: Double
        var to: Double?
        var wave: Wave = .sine
        var volume: Double = 0.4
        var envelope: Envelope = .pluck
    }

    private func buffer(for cue: Cue) -> AVAudioPCMBuffer? {
        if let cached = buffers[cue] { return cached }
        guard !Self.crowdCues.contains(cue), let format,
              let rendered = Self.render(tones(for: cue), format: format) else { return nil }
        buffers[cue] = rendered
        return rendered
    }

    private nonisolated static func render(_ tones: [Tone], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let length = tones.map { $0.start + $0.duration }.max() ?? 0
        let frameCount = AVAudioFrameCount(length * rate)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount
        for i in 0..<Int(frameCount) { samples[i] = 0 }

        for tone in tones {
            let first = Int(tone.start * rate)
            let count = Int(tone.duration * rate)
            var phase = 0.0
            // Murmur state. A cheap LCG stands in for `Double.random`, which is slow over seconds of noise.
            var filtered = 0.0
            var noiseSeed = UInt64.random(in: 1 ... .max)
            let wobbleRate = Double.random(in: 0.5...1.4), wobbleOffset = Double.random(in: 0...1)
            for n in 0..<count where first + n < Int(frameCount) {
                let t = Double(n) / rate
                let progress = t / tone.duration
                let frequency = tone.from + ((tone.to ?? tone.from) - tone.from) * progress
                phase += frequency / rate
                phase -= phase.rounded(.down)

                let value: Double
                switch tone.wave {
                case .sine: value = sin(2 * .pi * phase)
                case .square: value = phase < 0.5 ? 0.6 : -0.6
                case .triangle: value = 4 * abs(phase - 0.5) - 1
                case .noise: value = Double.random(in: -1...1)
                case .murmur:
                    // One-pole low-pass, then scaled back up so volumes stay comparable to the other waves.
                    // 2πf/rate is close to the exact 1 − e^(−2πf/rate) at these low cutoffs.
                    let smoothing = min(1, 2 * .pi * frequency / rate)
                    noiseSeed = noiseSeed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                    let noise = Double(noiseSeed >> 11) / Double(1 << 52) - 1
                    filtered += smoothing * (noise - filtered)
                    let wobble = 0.7 + 0.3 * sin(2 * .pi * (wobbleRate * t + wobbleOffset))
                    value = filtered * sqrt((2 - smoothing) / smoothing) * wobble
                }
                let envelope: Double
                switch tone.envelope {
                case .pluck:
                    // Quick attack avoids clicks; the decay gives each note a plucky, game-like feel.
                    envelope = min(1, t / 0.005) * pow(1 - progress, 1.6)
                case .swell:
                    envelope = min(1, progress / 0.25, (1 - progress) / 0.4)
                case .steady:
                    envelope = 1
                }
                samples[first + n] += Float(value * envelope * tone.volume)
            }
        }
        for i in 0..<Int(frameCount) { samples[i] = max(-1, min(1, samples[i])) }
        return buffer
    }

    private func tones(for cue: Cue) -> [Tone] {
        // Note frequencies (Hz).
        let c4 = 261.63, eb4 = 311.13, f4 = 349.23, g4 = 392.0
        let c5 = 523.25, d5 = 587.33, e5 = 659.25, g5 = 783.99, a5 = 880.0, b5 = 987.77
        let c6 = 1046.5, e6 = 1318.5, g6 = 1568.0

        switch cue {
        case .tap:
            return [Tone(start: 0, duration: 0.05, from: a5, wave: .triangle, volume: 0.3)]
        case .train:
            return [Tone(start: 0, duration: 0.08, from: c5, wave: .square, volume: 0.25),
                    Tone(start: 0.07, duration: 0.12, from: g5, wave: .square, volume: 0.25)]
        case .feed:
            return (0..<3).map { Tone(start: Double($0) * 0.09, duration: 0.05, from: 0, wave: .noise, volume: 0.25) }
                + [Tone(start: 0.28, duration: 0.12, from: e5, to: g5, volume: 0.3)]
        case .rest:
            return [Tone(start: 0, duration: 0.3, from: g5, volume: 0.25),
                    Tone(start: 0.22, duration: 0.3, from: e5, volume: 0.25),
                    Tone(start: 0.44, duration: 0.5, from: c5, volume: 0.25)]
        case .levelUp:
            return zip([c5, e5, g5, c6], 0...).map { note, i in
                Tone(start: Double(i) * 0.08, duration: i == 3 ? 0.35 : 0.1, from: note, wave: .square, volume: 0.22)
            }
        case .evolve:
            return [Tone(start: 0, duration: 0.7, from: 200, to: 1200, wave: .triangle, volume: 0.3)]
                + zip([c5, e5, g5, c6, e6, g6], 0...).map { note, i in
                    Tone(start: 0.6 + Double(i) * 0.07, duration: i == 5 ? 0.6 : 0.12, from: note, volume: 0.3)
                }
        case .purchase:
            return [Tone(start: 0, duration: 0.07, from: b5, wave: .square, volume: 0.22),
                    Tone(start: 0.07, duration: 0.3, from: e6, wave: .square, volume: 0.22)]
        case .denied:
            return [Tone(start: 0, duration: 0.1, from: 150, wave: .square, volume: 0.3),
                    Tone(start: 0.13, duration: 0.14, from: 140, wave: .square, volume: 0.3)]
        case .primary:
            return [Tone(start: 0, duration: 0.15, from: g5, volume: 0.35),
                    Tone(start: 0.1, duration: 0.35, from: d5 * 2, volume: 0.35)]
        case .release:
            return [Tone(start: 0, duration: 0.6, from: e5, to: c4, volume: 0.25)]
        case .summon:
            return [Tone(start: 0, duration: 0.5, from: 300, to: 1500, wave: .triangle, volume: 0.25)]
                + zip([g5, c6, e6, g6], 0...).map { note, i in
                    Tone(start: 0.45 + Double(i) * 0.06, duration: 0.3, from: note, volume: 0.25)
                }
        case .fuse:
            return [Tone(start: 0, duration: 0.6, from: 900, to: 150, wave: .triangle, volume: 0.3),
                    Tone(start: 0, duration: 0.6, from: 150, to: 900, wave: .triangle, volume: 0.3),
                    Tone(start: 0.55, duration: 0.15, from: 0, wave: .noise, volume: 0.3)]
        case .hit:
            return [Tone(start: 0, duration: 0.08, from: 0, wave: .noise, volume: 0.35),
                    Tone(start: 0, duration: 0.15, from: 220, to: 60, wave: .square, volume: 0.35)]
        case .critical:
            return [Tone(start: 0, duration: 0.12, from: 0, wave: .noise, volume: 0.45),
                    Tone(start: 0, duration: 0.22, from: 260, to: 50, wave: .square, volume: 0.45),
                    Tone(start: 0.05, duration: 0.25, from: e6, volume: 0.25)]
        case .miss:
            return [Tone(start: 0, duration: 0.2, from: 900, to: 300, volume: 0.15),
                    Tone(start: 0, duration: 0.2, from: 0, wave: .noise, volume: 0.08)]
        case .guardUp:
            return [Tone(start: 0, duration: 0.25, from: e5, wave: .triangle, volume: 0.3),
                    Tone(start: 0, duration: 0.25, from: b5, wave: .triangle, volume: 0.2)]
        case .heal:
            return [Tone(start: 0, duration: 0.4, from: 440, to: 880, volume: 0.25),
                    Tone(start: 0.15, duration: 0.4, from: 660, to: 1320, volume: 0.2)]
        case .knockout:
            return [Tone(start: 0, duration: 0.5, from: 400, to: 70, wave: .square, volume: 0.3)]
        case .victory:
            return [Tone(start: 0, duration: 0.12, from: g4, wave: .square, volume: 0.22),
                    Tone(start: 0.12, duration: 0.12, from: c5, wave: .square, volume: 0.22),
                    Tone(start: 0.24, duration: 0.12, from: e5, wave: .square, volume: 0.22),
                    Tone(start: 0.36, duration: 0.5, from: g5, wave: .square, volume: 0.22),
                    Tone(start: 0.36, duration: 0.5, from: c5, wave: .triangle, volume: 0.2)]
        case .defeat:
            return zip([g4, f4, eb4, c4], 0...).map { note, i in
                Tone(start: Double(i) * 0.2, duration: i == 3 ? 0.6 : 0.22, from: note, wave: .triangle, volume: 0.3)
            }
        case .cheer:
            return crowdCheer(length: 1.4, volume: 0.32, whistles: 1)
        case .roar:
            return crowdCheer(length: 2.6, volume: 0.45, whistles: 3)
        }
    }

    /// A crowd swelling up: voices brightening as they get louder, scattered claps and a few whistles.
    private func crowdCheer(length: Double, volume: Double, whistles: Int) -> [Tone] {
        var tones = [
            Tone(start: 0, duration: length, from: 600, to: 1500, wave: .murmur, volume: volume, envelope: .swell),
            Tone(start: 0, duration: length, from: 280, wave: .murmur, volume: volume * 0.6, envelope: .swell),
        ]
        for _ in 0..<Int(length * 14) {
            tones.append(Tone(start: .random(in: 0.1...(length * 0.8)), duration: 0.02, from: 0, wave: .noise,
                              volume: .random(in: 0.05...0.12)))
        }
        for i in 0..<whistles {
            let start = 0.15 + Double(i) * length / Double(whistles + 1)
            let pitch = Double.random(in: 1800...2400)
            tones.append(Tone(start: start, duration: 0.5, from: pitch, to: pitch * 1.3, volume: 0.05, envelope: .swell))
        }
        return tones
    }

    /// The Arena's background crowd: a few murmur layers held steady so the buffer loops without a dip.
    private static func crowdMurmur() -> [Tone] {
        [
            Tone(start: 0, duration: 6, from: 350, wave: .murmur, volume: 0.16, envelope: .steady),
            Tone(start: 0, duration: 6, from: 750, wave: .murmur, volume: 0.1, envelope: .steady),
            Tone(start: 0, duration: 6, from: 1300, wave: .murmur, volume: 0.05, envelope: .steady),
        ]
    }
}

private struct CrowdAmbience: ViewModifier {
    let isActive: Bool
    @State private var isHolding = false

    func body(content: Content) -> some View {
        content
            .onAppear { hold(isActive) }
            .onChange(of: isActive) { _, active in hold(active) }
            .onDisappear { hold(false) }
    }

    private func hold(_ wanted: Bool) {
        guard wanted != isHolding else { return }
        isHolding = wanted
        if wanted { SoundFX.shared.startCrowd() } else { SoundFX.shared.stopCrowd() }
    }
}

extension View {
    /// Plays the Arena crowd's murmur while this view is on screen and `isActive` is true.
    func crowdAmbience(_ isActive: Bool = true) -> some View {
        modifier(CrowdAmbience(isActive: isActive))
    }
}
