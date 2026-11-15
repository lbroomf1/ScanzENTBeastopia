//
//  ContentView.swift
//  Beastopia
//

import SwiftUI

struct ContentView: View {
    @Environment(GameStore.self) private var store
    @State private var showingIntro = true

    var body: some View {
        ZStack {
            TabView {
                Tab("Haven", systemImage: "house.fill") { HavenView().music("music_haven") }
                    // Counts beasts that can evolve, so the player notices from any tab.
                    .badge(store.readyToEvolve.count)
                Tab("Scan", systemImage: "qrcode.viewfinder") { ScanView().music("music_title") }
                Tab("Story", systemImage: "book.fill") { StoryView().music("music_title") }
                Tab("Arena", systemImage: "figure.fencing") { ArenaView().music("music_title") }
                Tab("Beastdex", systemImage: "square.grid.3x3.fill") { BeastdexView().music("music_title") }
            }
            // New players (and saves from before characters) make their keeper first,
            // once the loading sequence has finished.
            .fullScreenCover(isPresented: .constant(!showingIntro && store.keeper == nil)) {
                KeeperCreationView()
                    .interactiveDismissDisabled()
                    .music("music_title")
            }

            if showingIntro {
                LoadingSequenceView {
                    withAnimation(.easeOut(duration: 0.4)) { showingIntro = false }
                }
                .transition(.opacity)
                .zIndex(1)
                .music("music_title")
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(GameStore())
        .environment(MultiplayerManager())
}
