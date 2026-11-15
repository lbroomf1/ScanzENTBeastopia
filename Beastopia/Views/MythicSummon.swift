//
//  MythicSummon.swift
//  Beastopia
//

import SwiftUI

extension Species {
    /// A Mythic's title, shown when it awakens.
    var mythicEpithet: String? {
        switch id {
        case "aurorion": "Herald of the Dawn Wind"
        case "chronodrake": "Keeper of Stopped Time"
        case "maelstryx": "Eye of the Storm Sea"
        case "oblivyrn": "The Null Wyrm"
        case "vaporgeist": "Spirit of the Scalding Mist"
        case "sylvanwyrm": "Wyrm of Leaf and Wind"
        case "halostorm": "Crown of Living Thunder"
        case "magmarch": "The Mountain That Walks"
        default: nil
        }
    }
}

/// The Mythic summon: much longer and louder than a normal one. The world goes dark, a golden
/// glyph rises inside a ring of runes (with the two fusion parents spiralling into it), lightning
/// strikes, a pillar of light splits the sky, and the Mythic bursts out in a shockwave of both its
/// elements' colors. Reduce Motion skips straight to the reveal.
struct MythicSummonCutscene: View {
    enum Phase: Int, Comparable {
        case dark, gather, charge, lightning, pillar, revealed

        static func < (lhs: Phase, rhs: Phase) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let beast: Beast
    /// The fusion parents, if this Mythic came from Beast Fusion. They merge into the glyph.
    var parents: [Beast] = []
    var size: CGFloat = 200
    var onRevealed: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(GameSettings.hapticsKey) private var hapticsOn = true
    @State private var phase: Phase = .dark
    @State private var glyphShown = false
    @State private var parentsMerged = false
    @State private var flash = 0.0
    @State private var boltFlash = 0.0
    @State private var pillarHeight: CGFloat = 0
    @State private var shockwave = false
    @State private var titleShown = false
    @State private var revealDate = Date.now

    private var primary: Color { beast.species.element.color }
    private var secondary: Color { beast.species.hiddenElement.color }

    var body: some View {
        ZStack {
            stage
            Color.white.opacity(flash).allowsHitTesting(false)
        }
        .frame(width: size * 1.8, height: size * 2.1)
        .modifier(MythicShake(amount: shakeAmount, animatableData: CGFloat(phase.rawValue) + boltFlash))
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: phase) { hapticsOn && $1 >= .charge }
        .sensoryFeedback(.success, trigger: titleShown) { hapticsOn && $1 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase == .revealed ? "Mythic beast: \(beast.species.name)" : "A Mythic glyph is breaking open")
        .task { await play() }
    }

    private var shakeAmount: CGFloat {
        switch phase {
        case .charge: 3
        case .lightning: 9
        case .pillar: 5
        default: 0
        }
    }

    @ViewBuilder
    private var stage: some View {
        if phase >= .revealed {
            revealed
        } else {
            ZStack {
                runeRing
                if !parents.isEmpty { mergingParents }
                glyph
                if phase >= .lightning { lightning }
                if phase >= .pillar { pillar }
            }
        }
    }

    // MARK: - Before the reveal

    /// A golden glyph that spins faster as it charges.
    private var glyph: some View {
        Image(systemName: "hexagon.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(LinearGradient(colors: [GameTheme.gold, primary], startPoint: .top, endPoint: .bottom))
            .overlay {
                Image(systemName: "seal.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.12)
                    .foregroundStyle(.white.opacity(0.75))
                    .blendMode(.overlay)
            }
            .shadow(color: GameTheme.gold, radius: phase >= .charge ? 30 : 10)
            .frame(width: size * 0.6, height: size * 0.6)
            .scaleEffect(glyphShown ? (phase >= .charge ? 1.25 : 1) : 0.2)
            .opacity(glyphShown ? 1 : 0)
            .phaseAnimator([0.0, 360.0]) { view, angle in
                view.rotationEffect(.degrees(angle))
            } animation: { _ in .linear(duration: phase >= .charge ? 1.2 : 4) }
    }

    /// Eight runes orbiting the glyph.
    private var runeRing: some View {
        let runes = ["sparkle", "moon.stars.fill", "flame.fill", "drop.fill", "bolt.fill", "leaf.fill", "wind", "sun.max.fill"]
        return ZStack {
            Circle()
                .strokeBorder(GameTheme.gold.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [6, 8]))
                .frame(width: size * 1.35, height: size * 1.35)
            ForEach(runes.indices, id: \.self) { index in
                let angle = Double(index) / Double(runes.count) * 2 * .pi
                Image(systemName: runes[index])
                    .font(.system(size: size * 0.1, weight: .bold))
                    .foregroundStyle(index.isMultiple(of: 2) ? primary : secondary)
                    .shadow(color: .white, radius: 4)
                    .offset(x: cos(angle) * size * 0.68, y: sin(angle) * size * 0.68)
            }
        }
        .opacity(glyphShown ? 1 : 0)
        .scaleEffect(phase >= .charge ? 0.85 : 1)
        .phaseAnimator([0.0, -360.0]) { view, angle in
            view.rotationEffect(.degrees(angle))
        } animation: { _ in .linear(duration: phase >= .charge ? 2 : 8) }
    }

    /// The two fusion parents spiral inward and vanish into the glyph.
    private var mergingParents: some View {
        ForEach(Array(parents.prefix(2).enumerated()), id: \.offset) { index, parent in
            let side: CGFloat = index == 0 ? -1 : 1
            BeastPortrait(beast: parent, size: size * 0.45)
                .shadow(color: parent.species.element.color, radius: 12)
                .offset(x: parentsMerged ? 0 : side * size * 0.75, y: parentsMerged ? 0 : -size * 0.3)
                .scaleEffect(parentsMerged ? 0.1 : 1)
                .rotationEffect(.degrees(parentsMerged ? side * 220 : 0))
                .opacity(parentsMerged ? 0 : 1)
        }
    }

    /// Bolts striking the glyph from all sides.
    private var lightning: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                let angle = Double(index) * 72 + 18
                Image(systemName: "bolt.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.22, height: size * 0.5)
                    .foregroundStyle(.white)
                    .shadow(color: secondary, radius: 10)
                    .offset(y: -size * 0.55)
                    .rotationEffect(.degrees(angle))
            }
        }
        .opacity(boltFlash)
    }

    /// A column of light splitting the sky above the glyph.
    private var pillar: some View {
        LinearGradient(colors: [.white, GameTheme.gold, primary.opacity(0)], startPoint: .center, endPoint: .top)
            .frame(width: size * 0.55, height: pillarHeight)
            .blur(radius: 8)
            .offset(y: -pillarHeight / 2 + size * 0.1)
            .blendMode(.plusLighter)
    }

    // MARK: - Reveal

    private var revealed: some View {
        ZStack {
            // Two halos in the Mythic's two element colors, turning against each other.
            Circle()
                .fill(AngularGradient(colors: [primary, GameTheme.gold, secondary, primary], center: .center))
                .frame(width: size * 1.55, height: size * 1.55)
                .blur(radius: 18)
                .opacity(0.8)
                .phaseAnimator([0.0, 360.0]) { view, angle in
                    view.rotationEffect(.degrees(reduceMotion ? 0 : angle))
                } animation: { _ in .linear(duration: 6) }
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .strokeBorder(ring == 1 ? secondary : GameTheme.gold, lineWidth: 4)
                    .frame(width: size, height: size)
                    .scaleEffect(shockwave ? 2.2 + CGFloat(ring) * 0.4 : 0.3)
                    .opacity(shockwave ? 0 : 0.9)
                    .animation(.easeOut(duration: 1.1).delay(Double(ring) * 0.18), value: shockwave)
            }
            embers
            BeastPortrait(beast: beast, size: size * 1.1, isAnimated: true)
                .shadow(color: GameTheme.gold, radius: 24)
                .transition(.scale(scale: 0.2).combined(with: .opacity))
            Text("MYTHIC")
                .font(GameFont.pixel(size: size * 0.2, relativeTo: .largeTitle))
                .foregroundStyle(LinearGradient(colors: [.white, GameTheme.gold], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black, radius: 2, x: 2, y: 2)
                .shadow(color: GameTheme.gold, radius: 12)
                .scaleEffect(titleShown ? 1 : 3)
                .opacity(titleShown ? 1 : 0)
                .offset(y: size * 0.85)
        }
    }

    /// Gold sparks rising around the Mythic, forever.
    private var embers: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let elapsed = context.date.timeIntervalSince(revealDate)
            Canvas { canvas, area in
                for index in 0..<28 {
                    let seed = Double(index) * 1.618
                    let speed = 0.25 + (seed.truncatingRemainder(dividingBy: 1)) * 0.35
                    let progress = (elapsed * speed + seed).truncatingRemainder(dividingBy: 1)
                    let x = area.width / 2 + sin(seed * 7 + elapsed) * area.width * 0.42 * ((seed * 3).truncatingRemainder(dividingBy: 1))
                    let y = area.height * (0.95 - progress * 0.9)
                    let radius = 2 + (1 - progress) * 3
                    let color = index.isMultiple(of: 3) ? secondary : (index.isMultiple(of: 2) ? primary : GameTheme.gold)
                    canvas.opacity = 1 - progress
                    canvas.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)), with: .color(color))
                }
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    // MARK: - Timeline

    private func play() async {
        if reduceMotion {
            revealDate = .now
            phase = .revealed
            titleShown = true
            playRevealSound()
            onRevealed()
            return
        }
        SoundFX.play(.guardUp)
        withAnimation(.spring(duration: 0.8, bounce: 0.3)) { glyphShown = true }
        try? await Task.sleep(for: .milliseconds(500))

        phase = .gather
        withAnimation(.easeIn(duration: 1.3)) { parentsMerged = true }
        if !parents.isEmpty { SoundFX.play(.fuse) }
        try? await Task.sleep(for: .milliseconds(1300))

        withAnimation(.easeInOut(duration: 0.4)) { phase = .charge }
        SoundFX.play(.levelUp)
        try? await Task.sleep(for: .milliseconds(900))

        phase = .lightning
        for strike in 0..<3 {
            SoundFX.play(strike == 2 ? .critical : .hit)
            boltFlash = 1
            flash = 0.5
            withAnimation(.easeOut(duration: 0.25)) {
                boltFlash = 0
                flash = 0
            }
            try? await Task.sleep(for: .milliseconds(300))
        }

        phase = .pillar
        withAnimation(.easeIn(duration: 0.6)) { pillarHeight = size * 2.4 }
        try? await Task.sleep(for: .milliseconds(550))
        withAnimation(.easeIn(duration: 0.3)) { flash = 1 }
        try? await Task.sleep(for: .milliseconds(300))

        revealDate = .now
        playRevealSound()
        withAnimation(.spring(duration: 0.7, bounce: 0.4)) { phase = .revealed }
        shockwave = true
        withAnimation(.easeOut(duration: 0.9)) { flash = 0 }
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(.spring(duration: 0.45, bounce: 0.5)) { titleShown = true }
        SoundFX.play(.roar)
        try? await Task.sleep(for: .milliseconds(400))
        onRevealed()
    }

    private func playRevealSound() {
        if !MusicPlayer.shared.playSting("sting_evolve") { SoundFX.play(.evolve) }
    }
}

/// Shakes the whole stage while the glyph charges and lightning strikes.
private struct MythicShake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(animatableData * .pi * 9),
                                              y: amount * 0.5 * cos(animatableData * .pi * 7)))
    }
}

#Preview("Mythic summon") {
    MythicSummonCutscene(beast: BeastGenerator.opponent(seed: "preview", speciesID: "halostorm", level: 20))
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
}
