//
//  BeastopiaApp.swift
//  Beastopia
//
//  Created by LB on 11/4/26.
//

import SwiftUI

@main
struct BeastopiaApp: App {
    @State private var store = GameStore()
    @State private var multiplayer = MultiplayerManager()

    init() {
        GameFont.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(multiplayer)
                .fontDesign(.rounded)
        }
    }
}
