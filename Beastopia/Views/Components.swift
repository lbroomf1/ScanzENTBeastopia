//
//  Components.swift
//  Beastopia
//

import SwiftUI

/// One image of beast art, fitted into a `size` × `size` box. Pixel art is drawn at a whole number of
/// screen pixels per art pixel (e.g. 32 px art in a 104 pt box at 3× draws at 9 px each, 96 pt), so
/// every pixel is the same size instead of some being a pixel wider than others.
struct BeastArtImage: View {
    let image: UIImage
    let size: CGFloat

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let isPixelArt = GameArt.isPixelArt(image)
        Image(uiImage: image)
            .resizable()
            .interpolation(isPixelArt ? .none : .high)
            .scaledToFit()
            .frame(width: isPixelArt ? pixelSnappedSize : nil, height: isPixelArt ? pixelSnappedSize : nil)
            .frame(width: size, height: size)
    }

    private var pixelSnappedSize: CGFloat {
        let artPixels = max(image.size.width * image.scale, image.size.height * image.scale)
        guard artPixels > 0, displayScale > 0 else { return size }
        let screenPixelsPerArtPixel = max(1, (size * displayScale / artPixels).rounded(.down))
        return screenPixelsPerArtPixel * artPixels / displayScale
    }
}

/// A beast's portrait. Uses final art from the asset catalog (`beast_<speciesID>`) when it
/// exists; otherwise draws a procedural medallion where element sets the palette, the
/// scanned code's hue shifts it, and stage adds rings.
struct BeastPortrait: View {
    let species: Species
    var hue: Double = 0
    var isPrismatic = false
    var isSilhouette = false
    var size: CGFloat = 96
    /// Plays the idle frames (`beast_<id>_1`…`_4` and `_blink`) when they exist.
    var isAnimated = false

    private static let rainbow: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .red]

    var body: some View {
        Group {
            if isAnimated, !isSilhouette, case let frames = GameArt.beastFrames(species.id), !frames.isEmpty {
                decorated(AnimatedBeastArt(frames: frames, blink: GameArt.beastBlink(species.id), size: size))
            } else if let art = GameArt.beast(species.id) {
                artwork(art)
            } else {
                medallion
            }
        }
        .hueRotation(.degrees(hue))
        .colorMultiply(isSilhouette ? .black : .white)
        .frame(width: size, height: size)
        .accessibilityLabel(isSilhouette ? "Undiscovered beast" : species.name)
    }

    /// Final illustrated art, with a rainbow aura for prismatic variants.
    private func artwork(_ image: UIImage) -> some View {
        decorated(BeastArtImage(image: image, size: size))
    }

    private func decorated(_ art: some View) -> some View {
        art
            .shadow(color: isPrismatic ? .white : .black.opacity(0.3), radius: isPrismatic ? 6 : 3, y: isPrismatic ? 0 : 3)
            .background {
                if isPrismatic {
                    Circle()
                        .fill(AngularGradient(colors: Self.rainbow, center: .center))
                        .blur(radius: size * 0.12)
                        .opacity(0.6)
                }
            }
    }

    /// Placeholder art: a glossy element-colored gem with the species symbol embossed on it.
    private var medallion: some View {
        let color = species.element.color
        return ZStack {
            Circle()
                .fill(color.mix(with: .black, by: 0.45))
            Circle()
                .fill(RadialGradient(colors: [color.mix(with: .white, by: 0.4), color, color.mix(with: .black, by: 0.3)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.6))
                .padding(size * 0.045)
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.62, height: size * 0.32)
                .offset(y: -size * 0.25)
            if isPrismatic {
                Circle()
                    .strokeBorder(AngularGradient(colors: Self.rainbow, center: .center), lineWidth: size * 0.05)
            }
            ForEach(0..<(species.stage.rawValue - 1), id: \.self) { ring in
                Circle()
                    .strokeBorder(.white.opacity(0.45), lineWidth: 1.5)
                    .padding(size * (0.1 + CGFloat(ring) * 0.06))
            }
            Image(systemName: species.symbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .shadow(color: color.mix(with: .black, by: 0.6).opacity(0.7), radius: 0, y: size * 0.025)
                .padding(size * 0.25)
        }
    }
}

extension BeastPortrait {
    init(beast: Beast, size: CGFloat = 96, isAnimated: Bool = false) {
        self.init(species: beast.species, hue: beast.hue, isPrismatic: beast.isPrismatic, size: size,
                  isAnimated: isAnimated)
    }
}

struct ElementBadge: View {
    let element: Element
    var hidden = false

    var body: some View {
        GameLabel(hidden ? "Hidden: \(element.displayName)" : element.displayName, art: element.iconArt, symbol: element.symbol)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(element.color.opacity(hidden ? 0.15 : 0.25), in: .capsule)
            .foregroundStyle(element.color)
    }
}

struct RarityBadge: View {
    let rarity: Rarity

    var body: some View {
        Text(rarity.displayName)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(rarity.color.opacity(0.2), in: .capsule)
            .foregroundStyle(rarity.color)
    }
}

struct MeterBar: View {
    let label: String
    let value: Int
    let maximum: Int
    var tint: Color = .accentColor

    var body: some View {
        HStack {
            Text(label)
                .font(.caption.monospaced().bold())
                .frame(width: 40, alignment: .leading)
            ProgressView(value: Double(min(value, maximum)), total: Double(max(maximum, 1)))
                .tint(tint)
            Text("\(value)")
                .font(.caption.monospacedDigit())
                .frame(width: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Lets the player pick one of their beasts.
struct BeastPicker: View {
    @Environment(GameStore.self) private var store
    @Binding var selection: UUID?
    var excluding: Set<UUID> = []

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(store.beasts.filter { !excluding.contains($0.id) }) { beast in
                    Button {
                        selection = beast.id
                        SoundFX.play(.tap)
                    } label: {
                        VStack(spacing: 4) {
                            BeastPortrait(beast: beast, size: 64)
                            Text(beast.displayName).font(.caption.bold()).lineLimit(1)
                            Text("Lv \(beast.level)").font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(width: 84)
                        .padding(6)
                        .background(selection == beast.id ? Color.accentColor.opacity(0.2) : .clear,
                                    in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
    }
}
