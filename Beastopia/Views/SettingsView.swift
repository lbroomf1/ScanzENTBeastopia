//
//  SettingsView.swift
//  Beastopia
//

import SwiftUI

/// Player preferences, stored in `UserDefaults` so `@AppStorage` views and the audio engines share them.
enum GameSettings {
    /// Master sound switch. Kept on the original key so players who muted before Settings existed stay muted.
    nonisolated static let soundKey = SoundFX.enabledKey
    nonisolated static let musicOnKey = "settings.musicOn"
    nonisolated static let musicVolumeKey = "settings.musicVolume"
    nonisolated static let effectsOnKey = "settings.effectsOn"
    nonisolated static let effectsVolumeKey = "settings.effectsVolume"
    nonisolated static let crowdOnKey = "settings.crowdOn"
    nonisolated static let crowdVolumeKey = "settings.crowdVolume"
    nonisolated static let hapticsKey = "settings.haptics"
    /// Turns off screen shake and hit jolts in battle.
    nonisolated static let reduceEffectsKey = "settings.reduceBattleEffects"
    nonisolated static let controlModeKey = "adventure.controlMode"

    /// Tip and tutorial flags cleared by "Show Tips Again".
    private static let tipKeys = ["adventure.tutorialsSeen", "adventure.guideCollapsed", "haven.fusionTipSeen"]

    static var isMusicOn: Bool { flag(soundKey) && flag(musicOnKey) }
    static var areEffectsOn: Bool { flag(soundKey) && flag(effectsOnKey) }
    static var isCrowdOn: Bool { flag(soundKey) && flag(crowdOnKey) }
    static var isHapticsOn: Bool { flag(hapticsKey) }
    static var musicVolume: Float { volume(musicVolumeKey) }
    static var effectsVolume: Float { volume(effectsVolumeKey) }
    static var crowdVolume: Float { volume(crowdVolumeKey) }

    static func resetTips() {
        for key in tipKeys { UserDefaults.standard.removeObject(forKey: key) }
    }

    /// Tells the audio engines to pick up new values.
    static func applyAudio() {
        MusicPlayer.shared.settingsChanged()
        SoundFX.shared.settingsChanged()
    }

    /// Switches default to on until the player changes them.
    private static func flag(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    /// Volumes are 0…1 multipliers on each channel's normal level, defaulting to full.
    private static func volume(_ key: String) -> Float {
        Float(UserDefaults.standard.object(forKey: key) as? Double ?? 1)
    }
}

/// The Settings sheet, opened from the gear on each main tab.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(GameSettings.soundKey) private var soundOn = true
    @AppStorage(GameSettings.musicOnKey) private var musicOn = true
    @AppStorage(GameSettings.musicVolumeKey) private var musicVolume = 1.0
    @AppStorage(GameSettings.effectsOnKey) private var effectsOn = true
    @AppStorage(GameSettings.effectsVolumeKey) private var effectsVolume = 1.0
    @AppStorage(GameSettings.crowdOnKey) private var crowdOn = true
    @AppStorage(GameSettings.crowdVolumeKey) private var crowdVolume = 1.0
    @AppStorage(GameSettings.hapticsKey) private var hapticsOn = true
    @AppStorage(GameSettings.reduceEffectsKey) private var reduceEffects = false
    @AppStorage(GameSettings.controlModeKey) private var controlMode: AdventureScene.ControlMode = .tap

    @State private var didResetTips = false

    var body: some View {
        NavigationStack {
            Form {
                soundSection
                Section {
                    Picker("Map Movement", selection: $controlMode) {
                        ForEach(AdventureScene.ControlMode.allCases) { Text($0.displayName).tag($0) }
                    }
                } header: {
                    Text("Controls")
                } footer: {
                    Text("Tap to Walk: tap where you want to go. Joystick: hold the on-screen stick and use the A button to talk.")
                }
                Section {
                    Toggle("Vibration", systemImage: "iphone.radiowaves.left.and.right", isOn: $hapticsOn)
                    Toggle("Reduce Battle Effects", systemImage: "sparkles", isOn: $reduceEffects)
                } header: {
                    Text("Haptics & Motion")
                } footer: {
                    Text("Reduce Battle Effects turns off screen shake and hit jolts. Beasts still move to show who's acting.")
                }
                Section("Game Data & Tips") {
                    Button("Show Tips Again", systemImage: "lightbulb") {
                        GameSettings.resetTips()
                        didResetTips = true
                        SoundFX.play(.tap)
                    }
                    if didResetTips {
                        Text("Tutorials and tips will show again.").font(.footnote).foregroundStyle(.secondary)
                    }
                    LabeledContent("Version", value: Self.appVersion)
                }
            }
            .menuBackground("menu_bg_main")
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .onChange(of: audioState) { GameSettings.applyAudio() }
        }
        .presentationDetents([.large])
    }

    private var soundSection: some View {
        Section("Sound") {
            Toggle("Sound", systemImage: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill", isOn: $soundOn)
            Group {
                channel("Music", systemImage: "music.note", isOn: $musicOn, volume: $musicVolume)
                channel("Sound Effects", systemImage: "speaker.wave.1.fill", isOn: $effectsOn, volume: $effectsVolume) {
                    SoundFX.play(.tap)
                }
                channel("Arena Crowd", systemImage: "person.3.fill", isOn: $crowdOn, volume: $crowdVolume) {
                    SoundFX.play(.cheer)
                }
            }
            .disabled(!soundOn)
        }
    }

    /// A channel's on/off switch, with its volume slider underneath while it's on.
    /// `preview` plays a sample when the player lets go of the slider.
    @ViewBuilder
    private func channel(_ title: String, systemImage: String, isOn: Binding<Bool>, volume: Binding<Double>,
                         preview: @escaping () -> Void = {}) -> some View {
        Toggle(title, systemImage: systemImage, isOn: isOn)
        if isOn.wrappedValue {
            Slider(value: volume, in: 0...1) {
                Text("\(title) Volume")
            } minimumValueLabel: {
                Image(systemName: "speaker.fill").accessibilityHidden(true)
            } maximumValueLabel: {
                Image(systemName: "speaker.wave.3.fill").accessibilityHidden(true)
            } onEditingChanged: { editing in
                if !editing { preview() }
            }
            .accessibilityValue(volume.wrappedValue.formatted(.percent.precision(.fractionLength(0))))
        }
    }

    /// Everything the audio engines read, so one `onChange` can push updates to them.
    private var audioState: [Double] {
        [soundOn, musicOn, effectsOn, crowdOn].map { $0 ? 1 : 0 } + [musicVolume, effectsVolume, crowdVolume]
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

private struct SettingsButton: ViewModifier {
    @State private var isShowing = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape.fill") {
                        SoundFX.play(.tap)
                        isShowing = true
                    }
                }
            }
            .sheet(isPresented: $isShowing) { SettingsView() }
    }
}

extension View {
    /// Adds the Settings gear to a main tab's navigation bar. Apply inside the tab's `NavigationStack`.
    func settingsButton() -> some View {
        modifier(SettingsButton())
    }
}

#Preview {
    SettingsView()
}
