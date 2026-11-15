//
//  BeastAnimation.swift
//  Beastopia
//

import SwiftUI
import UIKit

extension GameArt {
    /// Idle frames `beast_<id>_1`…`_4`. Empty if the species has no animation yet.
    static func beastFrames(_ speciesID: String) -> [UIImage] {
        (1...4).compactMap { UIImage(named: "beast_\(speciesID)_\($0)") }
    }

    static func beastBlink(_ speciesID: String) -> UIImage? {
        UIImage(named: "beast_\(speciesID)_blink")
    }

    /// The light burst behind a summoned beast: Prismatic and Mythic get their own, otherwise the element's.
    static func summonBurst(for beast: Beast) -> UIImage? {
        let name = if beast.isPrismatic {
            "summon_burst_prismatic"
        } else if beast.rarity == .mythic {
            "summon_burst_mythic"
        } else {
            "summon_burst_\(beast.species.element.rawValue)"
        }
        return UIImage(named: name) ?? UIImage(named: "summon_burst")
    }
}

/// Plays a beast's idle frames at 6 fps with a blink every few seconds, like a looping GIF.
/// Falls back to the still portrait when the frames aren't in the catalog, and holds the first
/// frame with Reduce Motion.
struct AnimatedBeastArt: View {
    let frames: [UIImage]
    let blink: UIImage?
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let framesPerSecond = 6.0
    /// One blink every this many ticks (about every 4 seconds).
    private static let blinkEvery = 24

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1 / Self.framesPerSecond)) { context in
            BeastArtImage(image: frame(at: context.date), size: size)
        }
    }

    private func frame(at date: Date) -> UIImage {
        guard !reduceMotion, frames.count > 1 else { return frames[0] }
        let tick = Int(date.timeIntervalSinceReferenceDate * Self.framesPerSecond)
        if let blink, tick % Self.blinkEvery == 0 { return blink }
        return frames[tick % frames.count]
    }
}

/// The summon cutscene: the glyph appears and cracks (`summon_glyph_1`…`_3`), shatters into shards
/// (`summon_shard_1`…`_3`) in a flash, and the beast bursts out in front of its element's light
/// (`summon_burst_<element>`). Each piece falls back to drawn shapes if its art is missing.
struct SummonCutscene: View {
    enum Phase: Int, Comparable {
        case glyph, crack1, crack2, burst, revealed

        static func < (lhs: Phase, rhs: Phase) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let beast: Beast
    var size: CGFloat = 200
    /// Called when the beast appears, so the caller can show its details.
    var onRevealed: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(GameSettings.hapticsKey) private var hapticsOn = true
    @State private var phase: Phase = .glyph
    @State private var glyphShown = false
    @State private var shardsOut = false
    @State private var flash = 0.0

    private var isSpecial: Bool { beast.rarity >= .epic || beast.isPrismatic }

    var body: some View {
        stage
            .frame(width: size * 1.6, height: size * 1.6)
            .sensoryFeedback(.impact(weight: .heavy), trigger: phase) { hapticsOn && Self.didBurst($0, $1) }
            .sensoryFeedback(.impact(weight: .light), trigger: phase) { hapticsOn && Self.didCrack($0, $1) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .task { await play() }
    }

    private var stage: some View {
        let hasBurst = phase >= .burst
        return ZStack {
            if hasBurst {
                burst
                shards
                BeastPortrait(beast: beast, size: size, isAnimated: true)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            } else {
                crackingGlyph
            }
            Color.white
                .opacity(flash)
                .allowsHitTesting(false)
        }
    }

    private var accessibilityText: String {
        phase == .revealed ? beast.species.name : "The glyph is unlocking"
    }

    private static func didBurst(_ old: Phase, _ new: Phase) -> Bool { new == .burst }
    private static func didCrack(_ old: Phase, _ new: Phase) -> Bool { new == .crack1 || new == .crack2 }

    private func play() async {
        if reduceMotion {
            phase = .revealed
            glyphShown = true
            shardsOut = true
            Self.playSummonSound()
            onRevealed()
            return
        }
        withAnimation(.spring(duration: 0.4, bounce: 0.4)) { glyphShown = true }
        try? await Task.sleep(for: .milliseconds(550))
        withAnimation(.linear(duration: 0.35)) { phase = .crack1 }
        try? await Task.sleep(for: .milliseconds(isSpecial ? 600 : 400))
        withAnimation(.linear(duration: 0.35)) { phase = .crack2 }
        try? await Task.sleep(for: .milliseconds(isSpecial ? 700 : 450))

        Self.playSummonSound()
        flash = 1
        withAnimation(.spring(duration: 0.6, bounce: 0.45)) { phase = .burst }
        withAnimation(.easeOut(duration: 0.7)) { shardsOut = true }
        withAnimation(.easeOut(duration: 0.5)) { flash = 0 }
        try? await Task.sleep(for: .milliseconds(350))
        phase = .revealed
        onRevealed()
    }

    private static func playSummonSound() {
        if !MusicPlayer.shared.playSting("sting_summon") { SoundFX.play(.summon) }
    }

    // MARK: - Pieces

    /// The glyph, shaking harder with each crack.
    private var crackingGlyph: some View {
        let amount: CGFloat = switch phase {
        case .crack1: 3
        case .crack2: 6
        default: 0
        }
        return glyph
            .scaleEffect(glyphShown ? 1 : 0.3)
            .opacity(glyphShown ? 1 : 0)
            .modifier(Shake(amount: amount, animatableData: CGFloat(phase.rawValue)))
    }

    private var glyph: some View {
        let stage = min(phase.rawValue, 2) + 1
        return Group {
            if let image = UIImage(named: "summon_glyph_\(stage)") {
                pixelImage(image)
            } else {
                Image(systemName: stage == 1 ? "hexagon.fill" : "hexagon")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(beast.species.element.color.gradient)
                    .padding(size * 0.15)
            }
        }
        .frame(width: size * 0.8, height: size * 0.8)
    }

    /// The element's light, slowly turning behind the beast.
    private var burst: some View {
        Group {
            if let image = GameArt.summonBurst(for: beast) {
                pixelImage(image)
            } else {
                Circle()
                    .fill(RadialGradient(colors: [beast.species.element.color, .clear],
                                         center: .center, startRadius: 0, endRadius: size * 0.8))
            }
        }
        .frame(width: size * 1.5, height: size * 1.5)
        .phaseAnimator([0.0, 360.0]) { view, angle in
            view.rotationEffect(.degrees(reduceMotion ? 0 : angle))
        } animation: { _ in .linear(duration: 12) }
        .opacity(0.85)
        .transition(.scale(scale: 0.1).combined(with: .opacity))
    }

    /// Glyph fragments flying outward from the center and fading.
    private var shards: some View {
        ForEach(0..<8, id: \.self) { index in
            let angle = Double(index) / 8 * 2 * .pi + 0.3
            let distance = shardsOut ? size * 0.75 : size * 0.1
            Group {
                if let image = UIImage(named: "summon_shard_\(index % 3 + 1)") {
                    pixelImage(image)
                } else {
                    Image(systemName: "diamond.fill")
                        .resizable()
                        .foregroundStyle(beast.species.element.color)
                }
            }
            .frame(width: size * 0.14, height: size * 0.14)
            .rotationEffect(.degrees(shardsOut ? Double(index) * 70 : 0))
            .offset(x: cos(angle) * distance, y: sin(angle) * distance)
            .opacity(shardsOut ? 0 : 1)
        }
        .allowsHitTesting(false)
    }

    private func pixelImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(GameArt.isPixelArt(image) ? .none : .high)
            .scaledToFit()
    }
}

/// Horizontal jitter while the glyph cracks.
private struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(animatableData * .pi * 8), y: 0))
    }
}

#Preview("Summon cutscene") {
    SummonCutscene(beast: BeastGenerator.generate(fromCode: "PREVIEW"))
        .padding()
        .background(GameTheme.ink)
}
