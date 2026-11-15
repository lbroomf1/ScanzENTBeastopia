//
//  DialogueView.swift
//  Beastopia
//

import SwiftUI

/// Plays a conversation line by line, then offers the player's choices (if any).
/// The choice is only recorded when the player taps Continue, so dismissing early changes nothing.
struct DialogueView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let npc: NPC
    let dialogue: Dialogue
    let onComplete: () -> Void

    @State private var revealed = 1
    @State private var chosen: DialogueChoice?

    private var lines: [DialogueLine] {
        dialogue.lines.filter { $0.isVisible(with: store.storyFlags) }
    }

    private var finishedLines: Bool { revealed >= lines.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(lines.prefix(revealed).enumerated()), id: \.offset) { _, line in
                        bubble(line.text, speaker: line.speaker ?? npc.name, isPlayer: line.speaker == "You")
                    }
                    if let chosen {
                        bubble(chosen.text, speaker: "You", isPlayer: true)
                        bubble(chosen.reply, speaker: npc.name, isPlayer: false)
                        if chosen.coinReward > 0 {
                            GameLabel("+\(chosen.coinReward) coins", art: GameArt.coinIcon, symbol: "dollarsign.circle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.yellow)
                        }
                    }
                }
                .padding()
                .animation(.default, value: revealed)
                .animation(.default, value: chosen?.id)
            }
            .safeAreaInset(edge: .bottom) { controls.padding() }
            .navigationTitle(npc.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack {
                        NPCAvatar(npc: npc, size: 28)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(npc.name).font(.headline)
                            Text(npc.title).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var controls: some View {
        if !finishedLines {
            Button("Next") { revealed += 1 }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        } else if chosen == nil && !dialogue.choices.isEmpty {
            VStack(spacing: 8) {
                ForEach(dialogue.choices) { choice in
                    Button(choice.text) { chosen = choice }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }
            }
        } else {
            Button("Continue") {
                if let chosen { store.choose(chosen) }
                onComplete()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
    }

    private func bubble(_ text: String, speaker: String, isPlayer: Bool) -> some View {
        VStack(alignment: isPlayer ? .trailing : .leading, spacing: 2) {
            HStack(spacing: 6) {
                if isPlayer, let keeper = store.keeper { KeeperAvatar(keeper: keeper, size: 22) }
                Text(isPlayer ? store.keeper?.name ?? speaker : speaker)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            Text(text.personalized(for: store.keeper))
                .padding(10)
                .background(isPlayer ? (store.keeper?.color.color ?? .accentColor).opacity(0.25) : Color.secondary.opacity(0.15),
                            in: .rect(cornerRadius: 14))
        }
        .frame(maxWidth: .infinity, alignment: isPlayer ? .trailing : .leading)
    }
}
