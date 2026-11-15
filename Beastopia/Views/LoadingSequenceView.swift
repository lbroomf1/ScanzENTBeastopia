//
//  LoadingSequenceView.swift
//  Beastopia
//

import SwiftUI

/// The boot sequence: the SCANZ ent studio card revealed behind a teal scan line, a dissolve to the
/// BEASTOPIA title with a filling loading bar and a bouncing Cindrop, then the game. Tap to skip.
///
/// Art (all optional; missing pieces are skipped): `loading_scanz`, `loading_beastopia_clean`,
/// `loading_beast_1`…`_4`, `ui_guts_bar`, `ui_guts_bar_fill`.
struct LoadingSequenceView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showTitle = false
    /// How far the scan line has swept down the studio card, 0...1.
    @State private var reveal: CGFloat = 0
    @State private var progress: CGFloat = 0
    @State private var finished = false

    /// Full-screen art is 1290×2796 (215×466 pixel art at 6×).
    private static let artAspect: CGFloat = 1290.0 / 2796.0
    private static let scanTeal = Color(red: 0.36, green: 0.9, blue: 0.82)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            studioCard
                .opacity(showTitle ? 0 : 1)
            titleCard
                .opacity(showTitle ? 1 : 0)
        }
        .contentShape(.rect)
        .onTapGesture(perform: finish)
        .statusBarHidden()
        .accessibilityElement()
        .accessibilityLabel("Loading Beastopia")
        .accessibilityHint("Double-tap to skip")
        .accessibilityAddTraits(.isButton)
        .task { await run() }
    }

    // MARK: - Timeline

    /// About seven seconds end to end, matching the reference GIF.
    private func run() async {
        // 1. SCANZ ent: sweep the scan line down, then hold (about 2.5 s in total).
        if reduceMotion {
            reveal = 1
        } else {
            withAnimation(.linear(duration: 1.2)) { reveal = 1 }
        }
        guard await pause(2.5) else { return }

        // 2. Dissolve to the title.
        withAnimation(.easeInOut(duration: 0.7)) { showTitle = true }
        guard await pause(0.7) else { return }

        // 3. Fill the loading bar while Cindrop bounces.
        withAnimation(.easeInOut(duration: 2.8)) { progress = 1 }
        guard await pause(3.1) else { return }
        finish()
    }

    /// Sleeps, returning `false` if the sequence was skipped or cancelled meanwhile.
    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled && !finished
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinished()
    }

    // MARK: - Cards

    private var studioCard: some View {
        artCanvas("loading_scanz") { size in
            // The card is revealed top to bottom, with a glowing teal line at the leading edge.
            Rectangle()
                .fill(.black)
                .frame(height: size.height * (1 - reveal))
                .frame(maxHeight: .infinity, alignment: .bottom)
            if reveal > 0 && reveal < 1 {
                Rectangle()
                    .fill(Self.scanTeal)
                    .frame(height: 3)
                    .shadow(color: Self.scanTeal, radius: 8)
                    .position(x: size.width / 2, y: size.height * reveal)
            }
        }
    }

    private var titleCard: some View {
        artCanvas("loading_beastopia_clean") { size in
            // Positions and sizes are measured from the finished mock-up (`loading_beastopia`):
            // both sprites are drawn at 12 image pixels per sprite pixel.
            let beastWidth = size.width * 384 / 1290
            BouncingMascot()
                .frame(width: beastWidth, height: beastWidth * 36 / 32)
                .position(x: size.width * 0.502, y: size.height * 0.384)

            let barWidth = size.width * 768 / 1290
            LoadingBar(progress: progress)
                .frame(width: barWidth, height: barWidth * 8 / 64)
                .position(x: size.width * 0.497, y: size.height * 0.897)
        }
    }

    /// Full-screen art scaled to fill (cropping the sides on other aspect ratios), with `overlay`
    /// laid out in the art's own coordinate space so sprites line up with the painted scene.
    private func artCanvas<Overlay: View>(_ name: String,
                                          @ViewBuilder overlay: @escaping (CGSize) -> Overlay) -> some View {
        Color.clear
            .overlay {
                Image(name)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(Self.artAspect, contentMode: .fill)
                    .overlay {
                        GeometryReader { proxy in
                            overlay(proxy.size)
                        }
                    }
            }
            .clipped()
            .ignoresSafeArea()
    }
}

/// Cindrop's four-frame bounce at about 8 frames per second.
private struct BouncingMascot: View {
    private static let frames = (1...4).map { "loading_beast_\($0)" }.filter { UIImage(named: $0) != nil }

    var body: some View {
        if !Self.frames.isEmpty {
            TimelineView(.periodic(from: .now, by: 0.125)) { context in
                let tick = Int(context.date.timeIntervalSinceReferenceDate * 8)
                Image(Self.frames[tick % Self.frames.count])
                    .resizable()
                    .interpolation(.none)
            }
        }
    }
}

/// The guts bar frame with its fill growing from the left. The fill sits 2 px inside the 64×8 frame.
private struct LoadingBar: View {
    let progress: CGFloat

    var body: some View {
        if UIImage(named: "ui_guts_bar") != nil {
            GeometryReader { proxy in
                let pixel = proxy.size.width / 64
                ZStack(alignment: .topLeading) {
                    Image("ui_guts_bar")
                        .resizable()
                        .interpolation(.none)
                    Image("ui_guts_bar_fill")
                        .resizable()
                        .interpolation(.none)
                        .frame(width: pixel * 60, height: pixel * 4)
                        // Reveal the fill rather than squash it, so its pixels keep their shape.
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: pixel * 60 * progress)
                        }
                        .offset(x: pixel * 2, y: pixel * 2)
                }
            }
        }
    }
}

#Preview {
    LoadingSequenceView {}
}
