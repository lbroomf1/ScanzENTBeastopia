//
//  RegionView.swift
//  Beastopia
//

import SwiftUI

/// A story region: its quest log and the actions for the current quest step.
struct RegionView: View {
    @Environment(GameStore.self) private var store
    let region: Region

    @State private var selectedBeast: UUID?
    @State private var battle: BattleSession?
    @State private var battleObjective: Objective?
    @State private var conversation: Objective?
    @State private var isExploring = false

    private var chapter: Chapter { region.chapter }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GameLabel(chapter.region, art: chapter.element.iconArt, symbol: chapter.element.symbol)
                    .font(.headline)
                    .foregroundStyle(chapter.element.color)
                Text(region.description).font(.callout).foregroundStyle(.secondary)
                Text(chapter.intro).font(.body)

                ElementBriefingCard(briefing: region.briefing,
                                    glyphClaimed: region.briefing.glyph.map(store.hasClaimed) ?? false)

                if let map = AdventureMap.map(for: region) {
                    Button("Explore \(chapter.region)", systemImage: "figure.walk") { isExploring = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .fullScreenCover(isPresented: $isExploring) {
                            AdventureView(region: region, map: map)
                        }
                }

                questLog

                if let objective = store.activeObjective(in: region) {
                    Divider()
                    clueCard(for: objective)
                    action(for: objective)
                } else if store.completedChapters.contains(chapter.id) {
                    Divider()
                    Text(chapter.outro).font(.body.italic())
                }
            }
            .padding()
        }
        .navigationTitle(chapter.title)
        .onAppear { selectedBeast = selectedBeast ?? store.partner?.id }
        .sheet(item: $conversation) { objective in
            if case let .talk(npc, dialogue) = objective.kind {
                DialogueView(npc: npc, dialogue: dialogue) {
                    store.completeObjective(objective, in: region)
                }
            }
        }
        .fullScreenCover(item: $battle) { session in
            BattleView(session: session) { won in
                if won, let objective = battleObjective {
                    store.completeObjective(objective, in: region)
                }
                battleObjective = nil
            }
        }
    }

    // MARK: - Quest log

    private var questLog: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quest").font(.title3.bold())
            let active = store.activeObjective(in: region)
            ForEach(region.objectives) { objective in
                let done = store.isComplete(objective, in: region)
                let isActive = objective.id == active?.id
                HStack(spacing: 10) {
                    Image(systemName: done ? "checkmark.circle.fill" : (isActive ? "circle.circle" : "circle"))
                        .foregroundStyle(done ? .green : (isActive ? chapter.element.color : .secondary))
                    Image(systemName: icon(for: objective)).foregroundStyle(.secondary).frame(width: 20)
                    // Future steps stay hidden so the story unfolds as you play.
                    Text(done || isActive ? objective.summary : "???")
                        .font(isActive ? .body.bold() : .body)
                        .foregroundStyle(done ? .secondary : .primary)
                        .strikethrough(done)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }

    /// Mission help: where to look, plus battle prep for fights.
    private func clueCard(for objective: Objective) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(QuestGuide.clue(for: objective), systemImage: "lightbulb.fill")
                .font(.callout)
            ForEach(QuestGuide.battleAdvice(for: objective, in: region, partner: store.partner), id: \.self) { tip in
                Label(tip, systemImage: "shield.lefthalf.filled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.12), in: .rect(cornerRadius: 14))
    }

    private func icon(for objective: Objective) -> String {
        switch objective.kind {
        case .talk: "bubble.left.fill"
        case .defeat: "pawprint.fill"
        case .boss: "crown.fill"
        }
    }

    // MARK: - Current step

    @ViewBuilder
    private func action(for objective: Objective) -> some View {
        switch objective.kind {
        case let .talk(npc, _):
            HStack(spacing: 12) {
                NPCAvatar(npc: npc, tint: chapter.element.color)
                VStack(alignment: .leading) {
                    Text(npc.name).font(.headline)
                    Text(npc.title).font(.caption).foregroundStyle(.secondary)
                }
            }
            Button("Talk to \(npc.name)", systemImage: "bubble.left.and.bubble.right.fill") {
                conversation = objective
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)

        case let .defeat(encounter):
            battleSection(objective, opponent: encounter.opponent, name: encounter.name, level: encounter.level) { beast in
                .encounter(encounter, chapterID: chapter.id, beast: beast)
            }

        case .boss:
            battleSection(objective, opponent: chapter.opponent, name: chapter.opponentName, level: chapter.opponentLevel) { beast in
                .story(chapter, beast: beast)
            }
        }
    }

    @ViewBuilder
    private func battleSection(_ objective: Objective, opponent: Beast, name: String, level: Int,
                               makeSession: @escaping (Beast) -> BattleSession) -> some View {
        HStack {
            BeastPortrait(beast: opponent, size: 64)
            VStack(alignment: .leading) {
                Text(name).font(.headline)
                Text("Lv \(level) · \(opponent.species.element.displayName)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }

        if store.beasts.isEmpty {
            Text("You need a beast first. Scan a code to awaken one!").foregroundStyle(.secondary)
        } else {
            Text("Choose your beast").font(.headline)
            BeastPicker(selection: $selectedBeast).padding(.horizontal, -16)
            Button("Battle!") {
                if let beast = selectedBeast.flatMap(store.beast) ?? store.partner {
                    battleObjective = objective
                    battle = makeSession(store.battleReady(beast))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
    }
}

/// What a region's element means: its matchups, its mechanic, the boss's weaknesses and the glyph.
struct ElementBriefingCard: View {
    let briefing: RegionBriefing
    let glyphClaimed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GameLabel("\(briefing.element.displayName) Region", art: briefing.element.iconArt, symbol: briefing.element.symbol)
                    .font(.headline)
                    .foregroundStyle(briefing.element.color)
                Spacer()
            }
            Text(briefing.element.blurb).font(.callout)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("Strong vs").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(briefing.strongAgainstText).font(.caption)
                }
                GridRow {
                    Text("Weak to").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(briefing.weakToText).font(.caption)
                }
                GridRow {
                    Text("Boss").font(.caption.bold()).foregroundStyle(.secondary)
                    Text("\(briefing.bossName) (\(briefing.bossElement.displayName)). Bring \(briefing.countersText).")
                        .font(.caption)
                }
            }
            Divider()
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(briefing.mechanicTitle).font(.subheadline.bold())
                    Text(briefing.mechanicText).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(briefing.element.color)
            }
            if let glyph = briefing.glyphText {
                Label {
                    Text(glyphClaimed
                         ? "Element Glyph awakened: you have \(glyph)."
                         : "An Element Glyph hides here, holding \(glyph). It's strong against the boss.")
                        .font(.caption)
                } icon: {
                    Image(systemName: glyphClaimed ? "checkmark.seal.fill" : "hexagon.fill")
                        .foregroundStyle(glyphClaimed ? .green : GameTheme.gold)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .gamePanel(tint: briefing.element.color)
        .accessibilityElement(children: .combine)
    }
}

struct NPCAvatar: View {
    let npc: NPC
    var tint: Color = .accentColor
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let portrait = UIImage(named: npc.portraitArt) {
                Image(uiImage: portrait)
                    .resizable()
                    .interpolation(GameArt.isPixelArt(portrait) ? .none : .high)
                    .scaledToFit()
                    .padding(size * 0.06)
            } else {
                Image(systemName: npc.symbol)
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .background(tint.gradient, in: .circle)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}
