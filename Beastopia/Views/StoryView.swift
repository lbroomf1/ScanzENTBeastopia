//
//  StoryView.swift
//  Beastopia
//

import SwiftUI

/// The main campaign, "The Silent Lattice", explored as a world map of regions.
struct StoryView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DisclosureGroup("Prologue") {
                        Text(StoryCampaign.prologue)
                            .font(.callout)
                            .padding(.top, 8)
                    }
                    .font(.headline)

                    NavigationLink {
                        LoreArchiveView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Lattice Archive").font(.headline)
                                Text("\(store.unlockedLoreCount) of \(LoreArchive.entries.count) pages · lore, episodes and Fusion Rumors")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "book.pages.fill").font(.title2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.thinMaterial, in: .rect(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)

                    WorldMapView()

                    currentQuestCard
                }
                .padding()
            }
            .menuBackground("menu_bg_main")
            .navigationTitle("World Map")
            .settingsButton()
            .navigationDestination(for: Chapter.self) { chapter in
                if let region = WorldMap.region(for: chapter) {
                    RegionView(region: region)
                }
            }
        }
    }

    @ViewBuilder
    private var currentQuestCard: some View {
        if let chapter = store.nextChapter, let region = WorldMap.region(for: chapter) {
            NavigationLink(value: chapter) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.title2)
                        .foregroundStyle(chapter.element.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current Quest · \(chapter.title)").font(.headline)
                        Text(store.activeObjective(in: region)?.summary ?? chapter.region)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let objective = store.activeObjective(in: region) {
                            Label(QuestGuide.clue(for: objective), systemImage: "lightbulb.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .padding()
                .background(.thinMaterial, in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        } else {
            Label("The Lattice sings again. Campaign complete!", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
        }
    }
}

/// An illustrated map of Beastopia. Regions unlock in story order and are joined by trails.
struct WorldMapView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                trails(in: size)
                ForEach(WorldMap.regions) { region in
                    regionNode(region)
                        .position(x: region.x * size.width, y: region.y * size.height)
                }
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .background(
            LinearGradient(colors: [.indigo.opacity(0.35), .teal.opacity(0.25), .green.opacity(0.25)],
                           startPoint: .top, endPoint: .bottom),
            in: .rect(cornerRadius: 24)
        )
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.2)))
    }

    /// Trails between consecutive regions: solid once travelled, dashed while still ahead.
    private func trails(in size: CGSize) -> some View {
        let regions = WorldMap.regions
        return ForEach(Array(zip(regions, regions.dropFirst())), id: \.0.id) { from, to in
            let travelled = store.completedChapters.contains(from.id)
            Path { path in
                path.move(to: CGPoint(x: from.x * size.width, y: from.y * size.height))
                path.addLine(to: CGPoint(x: to.x * size.width, y: to.y * size.height))
            }
            .stroke(.white.opacity(travelled ? 0.8 : 0.35),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: travelled ? [] : [6, 6]))
        }
    }

    private func regionNode(_ region: Region) -> some View {
        let chapter = region.chapter
        let unlocked = store.isUnlocked(chapter)
        let completed = store.completedChapters.contains(chapter.id)
        let isCurrent = store.nextChapter?.id == chapter.id
        let symbol = completed ? "checkmark" : (unlocked ? chapter.element.symbol : "lock.fill")

        return NavigationLink(value: chapter) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(unlocked ? chapter.element.color.gradient : Color.gray.gradient)
                    if unlocked && !completed {
                        GameIcon(art: chapter.element.iconArt, symbol: symbol, size: 32)
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: symbol)
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 48, height: 48)
                .overlay {
                    if isCurrent {
                        Circle()
                            .strokeBorder(.white, lineWidth: 3)
                            .padding(-5)
                    }
                }
                .shadow(radius: 4)

                Text(chapter.region)
                    .font(.caption2.bold())
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: .capsule)
                    .fixedSize()
            }
            .opacity(unlocked ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(chapter.region)
        .accessibilityValue(completed ? "Completed" : (unlocked ? "Available" : "Locked"))
    }
}

#Preview {
    StoryView()
        .environment(GameStore())
}
