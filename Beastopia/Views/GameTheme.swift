//
//  GameTheme.swift
//  Beastopia
//

import CoreText
import SwiftUI
import UIKit

/// Shared colors for the game's own look, so screens stop reading as stock iOS.
enum GameTheme {
    static let ink = Color(red: 0.1, green: 0.08, blue: 0.18)
    static let gold = Color(red: 1, green: 0.76, blue: 0.28)
    static let panelTop = Color(red: 0.2, green: 0.17, blue: 0.32)
    static let panelBottom = Color(red: 0.12, green: 0.1, blue: 0.2)
}

/// Optional final art from the asset catalog. Add an image set with a matching name to
/// Assets.xcassets and it replaces the procedural placeholder without any code changes:
///
/// - `beast_<speciesID>` for a beast portrait (transparent PNG)
/// - `tile_<theme>_<terrain>` or `tile_<terrain>` for map tiles, e.g. `tile_meadow_grass`
/// - `player`, `npc_<objectiveID>`, `chest`, `chest_open` for map sprites
enum GameArt {
    static func beast(_ speciesID: String) -> UIImage? {
        UIImage(named: "beast_\(speciesID)")
    }

    /// Small images are treated as pixel art and scaled without smoothing so they stay crisp.
    static func isPixelArt(_ image: UIImage) -> Bool {
        max(image.size.width, image.size.height) <= 128
    }

    static let coinIcon = "currency_coin"
    static let shardIcon = "currency_shard"
}

/// The game's bundled pixel font (`Fonts/BeastopiaPixel.ttf`).
enum GameFont {
    static let pixelName = "Beastopia-Pixel"

    /// Registers the bundled font for this process. Call once at launch, before any map is drawn.
    static func register() {
        guard let url = Bundle.main.url(forResource: "BeastopiaPixel", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    /// Font for map labels: the pixel font if it loaded, otherwise the system's bold rounded look.
    static var mapLabelName: String {
        UIFont(name: pixelName, size: 12) != nil ? pixelName : "AvenirNext-Bold"
    }

    /// The pixel font for SwiftUI text, scaling with Dynamic Type. Falls back to bold monospaced.
    static func pixel(size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        UIFont(name: pixelName, size: size) != nil
            ? .custom(pixelName, size: size, relativeTo: style)
            : .system(size: size, weight: .bold, design: .monospaced)
    }
}

/// A retro RPG text box: pixel font on a dark panel with a chunky double border, text typed out
/// letter by letter, and a blinking arrow when the player can tap to continue.
/// Used for map messages, tutorials and region title cards so they read as part of the 2D world.
struct PixelTextBox: View {
    let text: String
    var title: String?
    /// Shows the blinking "tap to continue" arrow once the text has finished typing.
    var showsContinue = false
    var tint: Color = GameTheme.gold

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var typed = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(verbatim: title.uppercased())
                    .font(GameFont.pixel(size: 12, relativeTo: .caption))
                    .foregroundStyle(tint)
            }
            // The full text sits underneath, invisible, so the box keeps its size while typing.
            ZStack(alignment: .topLeading) {
                Text(verbatim: text).hidden()
                Text(verbatim: String(text.prefix(typed)))
            }
            .font(GameFont.pixel(size: 14))
            .foregroundStyle(.white)
            .lineSpacing(5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, showsContinue ? 22 : 14)
        .background(GameTheme.ink.opacity(0.95))
        // Square corners and stacked borders give the classic handheld dialog-box look.
        .overlay(Rectangle().strokeBorder(.white.opacity(0.9), lineWidth: 2).padding(4))
        .overlay(Rectangle().strokeBorder(tint, lineWidth: 4))
        .overlay(alignment: .bottomTrailing) {
            if showsContinue && typed >= text.count {
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.caption)
                    .foregroundStyle(tint)
                    .phaseAnimator([1.0, 0.15]) { arrow, opacity in
                        arrow.opacity(opacity)
                    } animation: { _ in .easeInOut(duration: 0.45) }
                    .padding(10)
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.5), radius: 0, x: 4, y: 4)
        .task(id: text) {
            if reduceMotion {
                typed = text.count
                return
            }
            typed = 0
            while typed < text.count {
                try? await Task.sleep(for: .milliseconds(16))
                if Task.isCancelled { return }
                typed += 1
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, text].compactMap(\.self).joined(separator: ". "))
    }
}

/// Shows a short message in a `PixelTextBox` along the bottom of the screen, then clears it.
/// Menus use this for feedback like "Pebblit happily munches away." so it matches the map's text boxes.
struct PixelToast: ViewModifier {
    @Binding var message: String?
    var seconds: Double = 2.5
    var tint: Color = GameTheme.gold

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    PixelTextBox(text: message, tint: tint)
                        .frame(maxWidth: 360)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .animation(.spring(duration: 0.3), value: message)
            .task(id: message) {
                guard let shown = message else { return }
                AccessibilityNotification.Announcement(shown).post()
                try? await Task.sleep(for: .seconds(seconds))
                // A newer message restarts the timer instead of being cleared early.
                if !Task.isCancelled { message = nil }
            }
    }
}

extension View {
    func pixelToast(_ message: Binding<String?>, seconds: Double = 2.5, tint: Color = GameTheme.gold) -> some View {
        modifier(PixelToast(message: message, seconds: seconds, tint: tint))
    }
}

/// A region name card in the pixel font, shown when the keeper arrives somewhere new.
struct PixelTitleCard: View {
    let title: String
    var tint: Color = GameTheme.gold

    var body: some View {
        Text(verbatim: "~ \(title.uppercased()) ~")
            .font(GameFont.pixel(size: 18, relativeTo: .title3))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(GameTheme.ink.opacity(0.85))
            .overlay(Rectangle().frame(height: 3).foregroundStyle(tint), alignment: .top)
            .overlay(Rectangle().frame(height: 3).foregroundStyle(tint), alignment: .bottom)
            .shadow(color: .black.opacity(0.5), radius: 0, x: 3, y: 3)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A full-screen 1290×2796 pixel-art image, scaled to fill and cropped at the sides on other aspect ratios.
struct FullScreenArt: View {
    let name: String

    var body: some View {
        Color.clear
            .overlay {
                Image(name)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
            }
            .clipped()
            .ignoresSafeArea()
    }
}

/// Puts screen art (e.g. `menu_bg_main`) behind a List, Form or ScrollView and switches the screen to
/// dark appearance so text stays readable on the dark art. Does nothing if the image isn't in the catalog.
struct MenuBackground: ViewModifier {
    let art: String
    /// Darkens lighter art (like the Haven's sunset) so white text keeps its contrast.
    var scrim: Double = 0

    func body(content: Content) -> some View {
        if UIImage(named: art) != nil {
            content
                .scrollContentBackground(.hidden)
                .background {
                    FullScreenArt(name: art)
                        .overlay { Color.black.opacity(scrim).ignoresSafeArea() }
                }
                .environment(\.colorScheme, .dark)
                .toolbarColorScheme(.dark, for: .navigationBar)
        } else {
            content
        }
    }
}

extension View {
    func menuBackground(_ art: String, scrim: Double = 0) -> some View {
        modifier(MenuBackground(art: art, scrim: scrim))
    }
}

/// An icon that shows final art from the asset catalog (e.g. `item_berry`) when it exists,
/// and falls back to an SF Symbol otherwise. Art keeps its own colors, so `foregroundStyle`
/// only affects the fallback symbol.
struct GameIcon: View {
    let art: String
    let symbol: String
    /// Point size for art. Defaults to a size that tracks Dynamic Type, roughly matching body text.
    var size: CGFloat?
    @ScaledMetric private var scaledSize: CGFloat = 20

    var body: some View {
        if let image = UIImage(named: art) {
            Image(uiImage: image)
                .resizable()
                .interpolation(GameArt.isPixelArt(image) ? .none : .high)
                .scaledToFit()
                .frame(width: size ?? scaledSize, height: size ?? scaledSize)
        } else {
            Image(systemName: symbol)
        }
    }
}

/// A label whose icon is a `GameIcon`.
struct GameLabel: View {
    let title: String
    let art: String
    let symbol: String

    init(_ title: String, art: String, symbol: String) {
        self.title = title
        self.art = art
        self.symbol = symbol
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            GameIcon(art: art, symbol: symbol)
        }
    }
}

/// A chunky, tactile button: a colored face that presses down onto a darker lip.
struct GameButtonStyle: ButtonStyle {
    var tint: Color = GameTheme.gold
    var cornerRadius: CGFloat = 14
    @Environment(\.isEnabled) private var isEnabled

    private static let depth: CGFloat = 4

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        configuration.label
            .font(.headline.weight(.heavy))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 0, y: 1.5)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .offset(y: pressed ? Self.depth : 0)
            .background {
                ZStack {
                    shape.fill(tint.mix(with: .black, by: 0.4))
                        .offset(y: Self.depth)
                    shape.fill(LinearGradient(colors: [tint.mix(with: .white, by: 0.2), tint.mix(with: .black, by: 0.08)],
                                              startPoint: .top, endPoint: .bottom))
                        .overlay(alignment: .top) {
                            // Glossy highlight along the top edge.
                            Capsule()
                                .fill(.white.opacity(0.28))
                                .frame(height: 6)
                                .padding(.horizontal, cornerRadius * 0.6)
                                .padding(.top, 3)
                        }
                        .overlay(shape.strokeBorder(.black.opacity(0.25), lineWidth: 1))
                        .offset(y: pressed ? Self.depth : 0)
                }
            }
            .padding(.bottom, Self.depth)
            .saturation(isEnabled ? 1 : 0.2)
            .opacity(isEnabled ? 1 : 0.55)
            .contentShape(.rect)
            .animation(.spring(duration: 0.12), value: pressed)
    }
}

/// A framed, dark game panel with a colored border, used for dialogue, stats and rewards.
struct GamePanel: ViewModifier {
    var tint: Color = GameTheme.gold
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        content
            .environment(\.colorScheme, .dark)
            .background(LinearGradient(colors: [GameTheme.panelTop, GameTheme.panelBottom],
                                       startPoint: .top, endPoint: .bottom), in: shape)
            .overlay(shape.strokeBorder(tint.opacity(0.9), lineWidth: 2))
            .overlay(
                RoundedRectangle(cornerRadius: max(cornerRadius - 3, 0))
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    .padding(3)
            )
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
    }
}

extension View {
    func gamePanel(tint: Color = GameTheme.gold, cornerRadius: CGFloat = 16) -> some View {
        modifier(GamePanel(tint: tint, cornerRadius: cornerRadius))
    }
}

/// A painted battle arena: an element-tinted sky over the enemy, the ally's ground below,
/// a glowing horizon, drifting motes and a vignette. Region art (`battle_bg_<theme>`) replaces it when present.
struct BattleBackdrop: View {
    let skyColor: Color
    let groundColor: Color
    var art: String?

    var body: some View {
        if let art, UIImage(named: art) != nil {
            FullScreenArt(name: art)
                .overlay { Color.black.opacity(0.15).ignoresSafeArea() }
                .allowsHitTesting(false)
        } else {
            painted
        }
    }

    private var painted: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(colors: [skyColor.mix(with: GameTheme.ink, by: 0.7), skyColor.mix(with: .white, by: 0.1)],
                               startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [groundColor.mix(with: .white, by: 0.05), groundColor.mix(with: GameTheme.ink, by: 0.75)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: size.height * 0.58)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                Ellipse()
                    .fill(.white.opacity(0.3))
                    .frame(width: size.width * 1.3, height: 70)
                    .blur(radius: 28)
                    .position(x: size.width / 2, y: size.height * 0.42)
                Canvas { context, canvasSize in
                    // Deterministic "random" motes so the scene doesn't flicker between redraws.
                    var seed: UInt64 = 0x9E37_79B9
                    func next() -> CGFloat {
                        seed = seed &* 6_364_136_223_846_793_005 &+ 1
                        return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
                    }
                    for _ in 0..<36 {
                        let radius = 1 + next() * 2.5
                        let rect = CGRect(x: next() * canvasSize.width, y: next() * canvasSize.height,
                                          width: radius * 2, height: radius * 2)
                        context.fill(Circle().path(in: rect), with: .color(.white.opacity(0.08 + next() * 0.22)))
                    }
                }
                RadialGradient(colors: [.clear, .black.opacity(0.5)], center: .center,
                               startRadius: size.width * 0.35, endRadius: max(size.width, size.height) * 0.75)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The glowing pedestal a beast stands on in battle.
struct BattlePlatform: View {
    let color: Color
    let width: CGFloat

    var body: some View {
        ZStack {
            Ellipse()
                .fill(.black.opacity(0.35))
                .offset(y: 5)
                .blur(radius: 3)
            Ellipse()
                .fill(LinearGradient(colors: [color.mix(with: .white, by: 0.35), color.mix(with: .black, by: 0.35)],
                                     startPoint: .top, endPoint: .bottom))
            Ellipse()
                .strokeBorder(.white.opacity(0.4), lineWidth: 1.5)
        }
        .frame(width: width, height: width * 0.3)
    }
}

/// A gentle bob so beasts feel alive while they wait for orders.
///
/// It only moves the beast, in whole-point steps. Scaling or sub-point offsets would resample the
/// pixel art (the portrait is flattened by its shadow and color filters), which stretches and blurs it.
struct IdleBob: ViewModifier {
    var isActive = true

    func body(content: Content) -> some View {
        content.phaseAnimator([false, true]) { view, up in
            view.modifier(PixelSnappedOffset(y: isActive && up ? -3 : 0))
        } animation: { _ in
            .easeInOut(duration: 1.1)
        }
    }
}

/// A vertical offset that animates smoothly but is drawn rounded to whole points.
private struct PixelSnappedOffset: ViewModifier, Animatable {
    var y: CGFloat

    var animatableData: CGFloat {
        get { y }
        set { y = newValue }
    }

    func body(content: Content) -> some View {
        content.offset(y: y.rounded())
    }
}
