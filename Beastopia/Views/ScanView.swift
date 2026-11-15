//
//  ScanView.swift
//  Beastopia
//

import AVFoundation
import OSLog
import SwiftUI
import VisionKit

/// The Lattice Lens: scan any QR code or barcode to awaken the beast sealed inside.
struct ScanView: View {
    @Environment(GameStore.self) private var store
    @State private var isScanning = true
    @State private var isTorchOn = false
    @State private var showTips = false
    @State private var showHelp = false
    @State private var manualCode = ""
    @State private var revealed: Beast?
    @State private var alertMessage: String?
    /// A scanned Challenge Card waiting for the keeper to accept.
    @State private var challenge: ChallengeCard?
    @State private var challengeBattle: BattleSession?

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if scannerAvailable {
                    CodeScanner(isScanning: $isScanning, isTorchOn: isTorchOn, onCode: summon)
                        .overlay { ScanViewfinder() }
                        .overlay(alignment: .top) {
                            PixelTextBox(text: "Fit the code inside the frame")
                                .fixedSize()
                                .padding()
                        }
                        .overlay(alignment: .bottom) {
                            if showTips {
                                ScanTipsCard { showHelp = true }
                                    .padding()
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            Button {
                                isTorchOn.toggle()
                            } label: {
                                Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(.ultraThinMaterial, in: .circle)
                            }
                            .accessibilityLabel(isTorchOn ? "Turn light off" : "Turn light on")
                            .padding(.top, 60)
                            .padding(.trailing)
                        }
                        .clipShape(.rect(cornerRadius: 24))
                        // If nothing scans for a while, offer tips instead of leaving the player stuck.
                        .task(id: isScanning) {
                            showTips = false
                            guard isScanning else { return }
                            try? await Task.sleep(for: .seconds(8))
                            withAnimation { showTips = true }
                        }
                        .onDisappear { isTorchOn = false }
                } else {
                    ContentUnavailableView("Lattice Lens Unavailable",
                                           systemImage: "camera.viewfinder",
                                           description: Text("Camera scanning isn't available here. Enter any code below — product numbers, ticket codes, anything."))
                }

                HStack {
                    TextField("Enter a code or episode code", text: $manualCode)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit(summonManual)
                    Button("Summon", action: summonManual)
                        .buttonStyle(.borderedProminent)
                        .disabled(manualCode.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding()
            .menuBackground("menu_bg_main")
            .navigationTitle("Scan")
            .settingsButton()
            .toolbar {
                Button("Scanning Help", systemImage: "questionmark.circle") { showHelp = true }
            }
            .sheet(isPresented: $showHelp) { ScanHelpView() }
            .sheet(item: $revealed, onDismiss: { isScanning = true }) { beast in
                SummonRevealView(beast: beast)
            }
            .alert("Challenge Card", isPresented: Binding(get: { challenge != nil }, set: { if !$0 { challenge = nil } }),
                   presenting: challenge) { card in
                Button("Fight!") { accept(card) }
                Button("Not Now", role: .cancel) { isScanning = true }
            } message: { card in
                let ghost = card.ghost
                Text("\(card.keeperName) challenges you: \(ghost.species.name), Lv \(ghost.level). Fight with \(store.partner?.displayName ?? "your beast")?")
            }
            .fullScreenCover(item: $challengeBattle, onDismiss: { isScanning = true }) { BattleView(session: $0) }
            .alert("Lattice Lens", isPresented: .constant(alertMessage != nil)) {
                Button("OK") {
                    alertMessage = nil
                    isScanning = true
                }
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private func summonManual() {
        summon(manualCode)
        manualCode = ""
    }

    private func accept(_ card: ChallengeCard) {
        challenge = nil
        guard let partner = store.partner else {
            alertMessage = "You need a beast to accept a challenge. Scan a code to awaken one!"
            return
        }
        challengeBattle = .challenge(card, beast: store.battleReady(partner))
    }

    private func summon(_ code: String) {
        guard !code.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isScanning = false
        // Challenge Cards start a battle instead of summoning.
        if ChallengeCard.isCard(code) {
            if let card = ChallengeCard(payload: code) {
                challenge = card
            } else {
                SoundFX.play(.denied)
                alertMessage = "This Challenge Card is damaged or from a newer version of Beastopia."
            }
            return
        }
        switch store.claim(code: code) {
        case .discovered(let beast):
            revealed = beast
        case .alreadyClaimed:
            SoundFX.play(.denied)
            alertMessage = "The beast sealed in this code has already answered your call. Try another code!"
        case .havenFull:
            SoundFX.play(.denied)
            alertMessage = "Your Beast Haven is full (\(store.havenCapacity) beasts). Release or fuse some beasts to make room."
        }
    }
}

/// Dramatic reveal of a newly awakened beast. Mythics get their own, much bigger cutscene.
struct SummonRevealView: View {
    @Environment(\.dismiss) private var dismiss
    let beast: Beast
    /// Why this beast appeared, e.g. an Element Glyph's banner.
    var note: String? = nil
    /// The fusion parents, when this beast came from Beast Fusion.
    var parents: [Beast] = []
    @State private var isRevealed = false

    /// Set when the beast came from a YouTube episode's code.
    private var episode: Episode? {
        EpisodeCatalog.episodes.first { $0.originTag == beast.originTag }
    }

    private var isMythic: Bool { beast.rarity == .mythic }

    var body: some View {
        Group {
            if isMythic { mythicReveal } else { standardReveal }
        }
        .presentationDetents([.large])
        // The cutscene plays out first; the player can't skip past an unrevealed beast by accident.
        .interactiveDismissDisabled(!isRevealed)
    }

    private var standardReveal: some View {
        VStack(spacing: 20) {
            Text(isRevealed ? "A beast awakens!" : "The glyph is unlocking…")
                .font(.title2.bold())
                .contentTransition(.opacity)

            SummonCutscene(beast: beast, size: 180) {
                withAnimation(.spring(duration: 0.6, bounce: 0.3)) { isRevealed = true }
            }

            if isRevealed {
                details
                    .transition(.opacity.combined(with: .move(edge: .bottom)))

                Button("Welcome to the Haven") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding()
    }

    /// Black and gold, the full cutscene, then the Mythic's title and both its elements.
    private var mythicReveal: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(isRevealed ? "A MYTHIC BEAST AWAKENS" : (parents.isEmpty ? "The Lattice trembles…" : "The Lattice resonates…"))
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(GameTheme.gold)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)

                MythicSummonCutscene(beast: beast, parents: parents, size: 170) {
                    withAnimation(.spring(duration: 0.8, bounce: 0.3)) { isRevealed = true }
                }

                if isRevealed {
                    VStack(spacing: 8) {
                        Text(beast.species.name)
                            .font(.system(size: 44, weight: .black))
                            .foregroundStyle(LinearGradient(colors: [.white, GameTheme.gold], startPoint: .top, endPoint: .bottom))
                        if let epithet = beast.species.mythicEpithet {
                            Text(epithet)
                                .font(.title3.italic())
                                .foregroundStyle(GameTheme.gold.opacity(0.9))
                        }
                        HStack {
                            ElementBadge(element: beast.species.element)
                            Image(systemName: "plus").font(.caption.bold()).foregroundStyle(.white.opacity(0.6))
                            ElementBadge(element: beast.species.hiddenElement)
                        }
                        HStack(spacing: 18) {
                            mythicStat("Power", "×\(beast.rarity.statBoost.formatted(.number.precision(.fractionLength(2))))")
                            mythicStat("Stats", "\(beast.stats.total)")
                            mythicStat("Signature", beast.species.signature.name)
                        }
                        .padding(.vertical, 6)
                        details
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))

                    Button("Welcome, \(beast.species.name)") { dismiss() }
                        .buttonStyle(GameButtonStyle())
                        .padding(.horizontal, 24)
                }
            }
            .padding()
        }
        .background {
            ZStack {
                Color.black
                RadialGradient(colors: [beast.species.element.color.opacity(isRevealed ? 0.45 : 0.15), .clear],
                               center: .center, startRadius: 10, endRadius: 420)
            }
            .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
    }

    private func mythicStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            Text(label.uppercased()).font(.caption2.bold()).foregroundStyle(GameTheme.gold)
        }
    }

    /// Name, badges, trait and lore, plus any episode, glyph or archive banners.
    private var details: some View {
        VStack(spacing: 8) {
            if let episode {
                Label("Episode \(episode.number): \(episode.title)", systemImage: "play.rectangle.fill")
                    .font(.headline)
                    .foregroundStyle(GameTheme.gold)
            }
            if let note {
                Label(note, systemImage: "hexagon.fill")
                    .font(.headline)
                    .foregroundStyle(beast.species.element.color)
                    .multilineTextAlignment(.center)
            }
            if !isMythic {
                Text(beast.species.name).font(.largeTitle.bold())
                HStack {
                    ElementBadge(element: beast.species.element)
                    RarityBadge(rarity: beast.rarity)
                    if beast.isPrismatic {
                        Label("Prismatic", systemImage: "sparkles").font(.caption.bold())
                    }
                }
            } else if beast.isPrismatic {
                Label("Prismatic", systemImage: "sparkles").font(.caption.bold())
            }
            Text("\(beast.trait.displayName) · \(beast.originTag.hasPrefix("#") ? "Glyph " : "")\(beast.originTag)\(beast.level > 1 ? " · Lv \(beast.level)" : "")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(beast.species.lore)
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if let episode, let entry = LoreArchive.entry(episode.loreID) {
                Label("Lattice Archive page unlocked: \(entry.title)", systemImage: "book.pages.fill")
                    .font(.callout.bold())
                    .foregroundStyle(.tint)
            }
        }
    }
}

// MARK: - Scanner guidance

/// Size of the square scan window, as a fraction of the camera view's shorter side.
/// Shared by the on-screen viewfinder and the scanner's region of interest so they line up.
private let scanWindowFraction: CGFloat = 0.7

private func scanWindow(in bounds: CGRect) -> CGRect {
    let side = min(bounds.width, bounds.height) * scanWindowFraction
    return CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
}

/// Dims everything outside the scan window and draws corner brackets with a sweeping line,
/// so players know exactly where to put the code.
struct ScanViewfinder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds for one pass of the line, top to bottom.
    private static let sweepDuration = 1.8

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let window = scanWindow(in: bounds)
            ZStack {
                Path { path in
                    path.addRect(bounds)
                    path.addRoundedRect(in: window, cornerSize: CGSize(width: 20, height: 20))
                }
                .fill(.black.opacity(0.45), style: FillStyle(eoFill: true))

                if let frame = UIImage(named: "scan_frame") {
                    // The Lattice Lens frame art, stretched pixel-crisp over the scan window.
                    Image(uiImage: frame)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: window.width, height: window.height)
                        .position(x: window.midX, y: window.midY)
                } else {
                    ViewfinderCorners()
                        .stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        .frame(width: window.width, height: window.height)
                        .position(x: window.midX, y: window.midY)
                }

                // Driven by the clock rather than a repeating animation, so the line is always placed
                // from the current window. A repeating animation also caught the camera view's layout
                // changes and left the sweep stuck off-center, low in the window.
                TimelineView(.animation(paused: reduceMotion)) { context in
                    let elapsed = context.date.timeIntervalSinceReferenceDate / Self.sweepDuration
                    // Eases 0 → 1 → 0, slowing at the top and bottom like the old ease-in-out sweep.
                    let progress = reduceMotion ? 0.5 : (1 - cos(elapsed * .pi)) / 2
                    let inset: CGFloat = 16
                    Capsule()
                        .fill(Color.accentColor.gradient)
                        .frame(width: window.width * 0.85, height: 3)
                        .shadow(color: .accentColor, radius: 6)
                        .position(x: window.midX,
                                  y: window.minY + inset + (window.height - inset * 2) * progress)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ViewfinderCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let length = rect.width * 0.18
        var path = Path()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
            (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
        ]
        for (corner, dx, dy) in corners {
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy * length))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x + dx * length, y: corner.y))
        }
        return path
    }
}

/// Shown after a few seconds without a successful scan.
struct ScanTipsCard: View {
    let onMoreHelp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Having trouble?", systemImage: "lightbulb.fill").font(.headline)
            Text("Hold your phone about a hand-length away (15–30 cm), keep the whole code in the frame, and hold still for a second.")
                .font(.callout)
            Button("More tips", action: onMoreHelp).font(.callout.bold())
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
}

struct ScanHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let tips: [(symbol: String, title: String, detail: String)] = [
        ("arrow.up.and.down", "Step back a little",
         "Phones can't focus very close up. Hold the code 15–30 cm away — the lens is already zoomed in to help."),
        ("viewfinder", "Fill the frame",
         "Line the code up inside the white corners. Barcodes work best held sideways, across the frame."),
        ("hand.raised.fill", "Hold still",
         "\"Slow down\" means the camera is moving too much. Steady your hands for a second."),
        ("flashlight.on.fill", "Add light",
         "Dim room? Tap the flashlight button. Shiny packaging? Tilt it slightly to avoid glare."),
        ("plus.magnifyingglass", "Pinch to zoom",
         "Small or faraway codes can be zoomed in with two fingers."),
        ("keyboard", "Type it instead",
         "Still stuck? Enter the numbers printed under the barcode in the box below the camera."),
        ("play.rectangle.fill", "Episode codes",
         "Each Beastopia episode on YouTube shows a code that awakens a special beast. Scan it from another screen, or type it in. Capitals, spaces and dashes don't matter."),
    ]

    var body: some View {
        NavigationStack {
            List(tips, id: \.title) { tip in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tip.title).font(.headline)
                        Text(tip.detail).font(.callout).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: tip.symbol).foregroundStyle(.tint)
                }
            }
            .navigationTitle("Scanning Tips")
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Camera scanner

/// Wraps VisionKit's live data scanner for QR codes and all supported barcode symbologies.
struct CodeScanner: UIViewControllerRepresentable {
    @Binding var isScanning: Bool
    var isTorchOn = false
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.scanner.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {
        context.coordinator.onCode = onCode
        controller.wantsTorch = isTorchOn
        controller.wantsScanning = isScanning
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems where handle(item, in: dataScanner) { return }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            _ = handle(item, in: dataScanner)
        }

        private func handle(_ item: RecognizedItem, in dataScanner: DataScannerViewController) -> Bool {
            guard case .barcode(let barcode) = item,
                  let payload = barcode.payloadStringValue, !payload.isEmpty else { return false }
            dataScanner.stopScanning()
            SoundFX.play(.tap)
            onCode(payload)
            return true
        }
    }
}

/// Hosts the data scanner so it can be configured once its view is on screen:
/// scanning starts only after the view appears, the scan area matches the viewfinder,
/// and the camera zooms in so players can hold the phone far enough away to focus.
final class ScannerController: UIViewController {
    let scanner = DataScannerViewController(
        recognizedDataTypes: [.barcode()],
        qualityLevel: .accurate,
        recognizesMultipleItems: false,
        isHighFrameRateTrackingEnabled: false,
        isPinchToZoomEnabled: true,
        // The app shows its own viewfinder and tips instead of the system's "Slow down" text.
        isGuidanceEnabled: false,
        isHighlightingEnabled: true
    )

    var wantsScanning = false { didSet { applyScanningState() } }
    var wantsTorch = false { didSet { applyTorch() } }

    private var isOnScreen = false
    private var hasSetInitialZoom = false

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(scanner)
        scanner.view.frame = view.bounds
        scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scanner.view)
        scanner.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scanner.regionOfInterest = scanWindow(in: scanner.view.bounds)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isOnScreen = true
        applyScanningState()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isOnScreen = false
        applyScanningState()
    }

    private func applyScanningState() {
        guard isViewLoaded else { return }
        if wantsScanning, isOnScreen, !scanner.isScanning {
            do {
                try scanner.startScanning()
            } catch {
                Logger(subsystem: "Beastopia", category: "Scan").error("Scanner failed to start: \(error, privacy: .private)")
                return
            }
            if !hasSetInitialZoom {
                // Close-up codes are blurry on cameras with a long minimum focus distance.
                // Zooming in lets the player hold the phone back where the lens can focus.
                scanner.zoomFactor = min(max(2.0, scanner.minZoomFactor), scanner.maxZoomFactor)
                hasSetInitialZoom = true
            }
            applyTorch()
        } else if (!wantsScanning || !isOnScreen), scanner.isScanning {
            scanner.stopScanning()
        }
    }

    private func applyTorch() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        let mode: AVCaptureDevice.TorchMode = wantsTorch && scanner.isScanning ? .on : .off
        guard device.torchMode != mode else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = mode
            device.unlockForConfiguration()
        } catch {
            Logger(subsystem: "Beastopia", category: "Scan").error("Couldn't change the flashlight: \(error, privacy: .private)")
        }
    }
}
