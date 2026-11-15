//
//  ArenaBattleEffects.swift
//  Beastopia
//

import SwiftUI

// Presentation used only by Arena matches (practice, raids and online): the announcer's intro card,
// the crowd in the stands behind the fighters, and the victory confetti.

/// The announcer's "tale of the tape" before an Arena match: both sides' beasts, a VS slam and a line
/// from the announcer. Closes by itself after a few seconds, or on tap.
struct ArenaIntroCard: View {
    let allies: [Combatant]
    let enemies: [Combatant]
    let announcement: String
    let onFinish: () -> Void

    @State private var isRevealed = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            // A spotlight cone falling on the fighters.
            RadialGradient(colors: [GameTheme.gold.opacity(0.35), .clear], center: .center, startRadius: 10, endRadius: 260)
                .ignoresSafeArea()
                .opacity(isRevealed ? 1 : 0)

            VStack(spacing: 22) {
                Text("BEAST ARENA")
                    .font(.headline.weight(.black))
                    .tracking(6)
                    .foregroundStyle(GameTheme.gold)
                HStack(alignment: .center, spacing: 8) {
                    side(allies)
                        .offset(x: isRevealed ? 0 : -260)
                    Text("VS")
                        .font(.system(size: 52, weight: .black))
                        .foregroundStyle(Color.red.gradient)
                        .shadow(color: .black, radius: 0, x: 3, y: 3)
                        .scaleEffect(isRevealed ? 1 : 3)
                        .opacity(isRevealed ? 1 : 0)
                    side(enemies)
                        .offset(x: isRevealed ? 0 : 260)
                }
                Text(announcement)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .opacity(isRevealed ? 1 : 0)
                Text("Tap to begin")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
        }
        .contentShape(.rect)
        .onTapGesture(perform: onFinish)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(announcement)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Starts the match.")
        .onAppear {
            SoundFX.play(.roar)
            AccessibilityNotification.Announcement(announcement).post()
            withAnimation(.spring(duration: 0.55, bounce: 0.35)) { isRevealed = true }
        }
        .task {
            try? await Task.sleep(for: .seconds(3.2))
            onFinish()
        }
    }

    private func side(_ combatants: [Combatant]) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: -16) {
                ForEach(combatants) { combatant in
                    if let species = SpeciesDatabase.species(combatant.speciesID) {
                        BeastPortrait(species: species, hue: combatant.hue, isPrismatic: combatant.isPrismatic,
                                      size: combatants.count > 1 ? 72 : 96)
                    }
                }
            }
            Text(combatants.map(\.name).formatted(.list(type: .and)))
                .font(.subheadline.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Silhouettes of the crowd along the top of the battle, like distant stands. Each time `hype`
/// changes they jump in a ripple and a few camera flashes pop.
struct ArenaCrowdStrip: View {
    let hype: Int

    private static let count = 22
    /// Fixed heights and jump delays so the crowd looks varied but doesn't reshuffle between redraws.
    private static let figures: [(height: CGFloat, delay: Double)] = (0..<count).map { index in
        let wobble = Double((index * 37) % 11) / 10
        return (height: 22 + CGFloat((index * 53) % 9), delay: wobble * 0.25)
    }
    private static let flashSpots: [UnitPoint] = [
        UnitPoint(x: 0.12, y: 0.3), UnitPoint(x: 0.38, y: 0.5), UnitPoint(x: 0.61, y: 0.2), UnitPoint(x: 0.86, y: 0.45),
    ]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Self.figures.indices, id: \.self) { index in
                let figure = Self.figures[index]
                Image(systemName: hype % 2 == 1 && index.isMultiple(of: 2) ? "figure.arms.open" : "person.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(height: figure.height)
                    .frame(maxWidth: .infinity)
                    .keyframeAnimator(initialValue: 0.0, trigger: hype) { content, lift in
                        content.offset(y: -lift)
                    } keyframes: { _ in
                        KeyframeTrack {
                            LinearKeyframe(0, duration: figure.delay)
                            CubicKeyframe(9, duration: 0.12)
                            CubicKeyframe(0, duration: 0.14)
                            CubicKeyframe(6, duration: 0.12)
                            CubicKeyframe(0, duration: 0.14)
                        }
                    }
            }
        }
        .foregroundStyle(.black.opacity(0.45))
        .overlay {
            GeometryReader { proxy in
                ForEach(Self.flashSpots.indices, id: \.self) { index in
                    let spot = Self.flashSpots[index]
                    Circle()
                        .fill(.white)
                        .frame(width: 10, height: 10)
                        .blur(radius: 3)
                        .position(x: proxy.size.width * spot.x, y: proxy.size.height * spot.y)
                        .keyframeAnimator(initialValue: 0.0, trigger: hype) { content, brightness in
                            content.opacity(brightness).scaleEffect(0.6 + brightness)
                        } keyframes: { _ in
                            KeyframeTrack {
                                LinearKeyframe(0, duration: 0.05 + Double(index) * 0.09)
                                LinearKeyframe(1, duration: 0.04)
                                LinearKeyframe(0, duration: 0.25)
                            }
                        }
                }
            }
        }
        .frame(height: 40)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Confetti showering down over an Arena victory.
struct ConfettiBurst: View {
    private struct Piece: Identifiable {
        let id: Int
        let x: CGFloat
        let drift: CGFloat
        let size: CGSize
        let color: Color
        let spin: Double
        let duration: Double
        let delay: Double
    }

    private let pieces: [Piece] = (0..<70).map { id in
        Piece(id: id, x: .random(in: 0...1), drift: .random(in: -60...60),
              size: CGSize(width: .random(in: 6...10), height: .random(in: 10...16)),
              color: [.red, .orange, .yellow, .green, .mint, .blue, .purple, .pink, GameTheme.gold].randomElement() ?? .yellow,
              spin: .random(in: 360...1080) * (Bool.random() ? 1 : -1),
              duration: .random(in: 2.2...3.4), delay: .random(in: 0...0.6))
    }

    @State private var hasFallen = false

    var body: some View {
        GeometryReader { proxy in
            ForEach(pieces) { piece in
                RoundedRectangle(cornerRadius: 2)
                    .fill(piece.color)
                    .frame(width: piece.size.width, height: piece.size.height)
                    .rotation3DEffect(.degrees(hasFallen ? piece.spin : 0), axis: (x: 1, y: 0.4, z: 0.2))
                    .position(x: proxy.size.width * piece.x + (hasFallen ? piece.drift : 0),
                              y: hasFallen ? proxy.size.height + 30 : -30)
                    .opacity(hasFallen ? 0.2 : 1)
                    .animation(.easeIn(duration: piece.duration).delay(piece.delay), value: hasFallen)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { hasFallen = true }
    }
}
