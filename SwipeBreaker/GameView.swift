import SpriteKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class GameController: ObservableObject {
    let scene: GameScene
    @Published var isGameOver: Bool = false
    @Published var score: Int = 0
    @Published var best: Int = 0
    @Published var turn: Int = 1

    init() {
        let store = SaveStore()
        scene = GameScene(store: store)
        scene.scaleMode = .resizeFill
        scene.onGameOverChange = { [weak self] gameOver in
            guard let self else { return }
            self.refreshScoreboard()
            withAnimation(Theme.viewTransition) {
                self.isGameOver = gameOver
            }
        }
        refreshScoreboard()
    }

    func refreshScoreboard() {
        score = scene.currentScore
        best = scene.currentBestScore
        turn = scene.currentTurn
    }

    func restart() {
        scene.restartGame()
        refreshScoreboard()
    }
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var appearance: AppearancePreference {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    @Published var audioEnabled: Bool {
        didSet { AudioManager.shared.isEnabled = audioEnabled }
    }

    @Published var audioVolume: Double {
        didSet { AudioManager.shared.volume = Float(audioVolume) }
    }

    private static let appearanceKey = "swipebreaker.appearance"

    init() {
        let rawAppearance = UserDefaults.standard.string(forKey: Self.appearanceKey)
        appearance = AppearancePreference(rawValue: rawAppearance ?? "") ?? .system
        audioEnabled = AudioManager.shared.isEnabled
        audioVolume = Double(AudioManager.shared.volume)
    }

    func resolvedColorScheme(systemScheme: ColorScheme) -> ColorScheme {
        switch appearance {
        case .system: return systemScheme
        case .dark: return .dark
        case .light: return .light
        }
    }

    func preferredColorScheme() -> ColorScheme? {
        switch appearance {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

struct GameView: View {
    @StateObject private var controller = GameController()
    @StateObject private var settings = AppSettings()
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLoaded = true
    @State private var isShowingSettings = false

    private var resolvedColorScheme: ColorScheme {
        settings.resolvedColorScheme(systemScheme: systemColorScheme)
    }

    private var palette: Theme.Palette {
        Theme.palette(for: resolvedColorScheme)
    }

    var body: some View {
        GeometryReader { proxy in
            let viewportSize = resolvedViewportSize(proxy)
            ZStack(alignment: .topLeading) {
                palette.background
                    .ignoresSafeArea(.all)

#if os(macOS)
                SpriteView(
                    scene: controller.scene,
                    options: [.ignoresSiblingOrder]
                )
                .aspectRatio(390.0 / 844.0, contentMode: .fit)
                .frame(width: viewportSize.width, height: viewportSize.height, alignment: .topLeading)
                .opacity(isLoaded ? 1 : 0)
#else
                FullScreenSpriteView(scene: controller.scene)
                .frame(width: viewportSize.width, height: viewportSize.height, alignment: .topLeading)
                .ignoresSafeArea()
                .opacity(isLoaded ? 1 : 0)
#endif

                if !isLoaded {
                    LoadingOverlay(palette: palette)
                        .transition(.opacity)
                }

                VStack {
                    HStack {
                        Spacer()
                        Button {
                            isShowingSettings = true
                        } label: {
                            Image(systemName: "gear")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(palette.textPrimary)
                                .frame(width: 44, height: 44)
                        }
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel("Settings")
                    }
                    Spacer()
                }
                .padding(.top, overlayTopPadding)
                .padding(.horizontal, 14)

                if controller.isGameOver {
                    GameOverOverlay(
                        score: controller.score,
                        best: controller.best,
                        turn: controller.turn,
                        palette: palette,
                        onRestart: { controller.restart() }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(50)
                }

                if isShowingSettings {
                    SettingsOverlay(
                        settings: settings,
                        palette: palette,
                        onClose: { isShowingSettings = false }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
                }
            }
            .frame(width: viewportSize.width, height: viewportSize.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .preferredColorScheme(settings.preferredColorScheme())
        .onAppear {
            applySettingsToScene()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                controller.scene.persistCompletedTurn()
            }
        }
        .onChange(of: settings.appearance) { _, _ in
            applySettingsToScene()
        }
        .onChange(of: systemColorScheme) { _, _ in
            applySettingsToScene()
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isShowingSettings)
    }

    private func applySettingsToScene() {
        controller.scene.setLightAppearance(resolvedColorScheme == .light)
    }

    private func resolvedViewportSize(_ proxy: GeometryProxy) -> CGSize {
#if canImport(UIKit)
        return CGSize(
            width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
            height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
        )
#else
        return proxy.size
#endif
    }

    private var overlayTopPadding: CGFloat {
#if canImport(UIKit)
        return 80
#else
        return 12
#endif
    }
}

#if canImport(UIKit)
private final class FittingSKView: SKView {
    override func layoutSubviews() {
        super.layoutSubviews()
        scene?.size = bounds.size
    }
}

private struct FullScreenSpriteView: UIViewRepresentable {
    let scene: SKScene

    func makeUIView(context: Context) -> SKView {
        let view = FittingSKView(frame: .zero)
        view.backgroundColor = .clear
        view.ignoresSiblingOrder = true
        view.contentMode = .scaleToFill
        scene.scaleMode = .resizeFill
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        if view.scene !== scene {
            view.presentScene(scene)
        }
        view.ignoresSiblingOrder = true
        scene.size = view.bounds.size
    }
}
#endif

// MARK: - Loading

private struct LoadingOverlay: View {
    let palette: Theme.Palette

    @State private var dotPhase = 0
    @State private var glowOpacity = 0.4

    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            VStack(spacing: 18) {
                Text("SWIPE")
                    .font(Theme.Fonts.mono(42, weight: .bold))
                    .tracking(6)
                    .foregroundStyle(palette.textPrimary)
                Text("BREAKER")
                    .font(Theme.Fonts.mono(42, weight: .bold))
                    .tracking(6)
                    .foregroundStyle(palette.primary)
                    .shadow(color: palette.glow.opacity(glowOpacity), radius: 16)

                Text(loadingText)
                    .font(Theme.Fonts.mono(12, weight: .medium))
                    .tracking(4)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, 28)
            }
        }
        .onReceive(timer) { _ in
            dotPhase = (dotPhase + 1) % 4
            withAnimation(.easeInOut(duration: 0.35)) {
                glowOpacity = glowOpacity > 0.5 ? 0.3 : 0.7
            }
        }
    }

    private var loadingText: String {
        "LOADING" + String(repeating: ".", count: dotPhase) + String(repeating: " ", count: 3 - dotPhase)
    }
}

// MARK: - Settings

private struct SettingsOverlay: View {
    @ObservedObject var settings: AppSettings
    let palette: Theme.Palette
    let onClose: () -> Void

    @GestureState private var dragOffset: CGFloat = 0
    private let dismissThreshold: CGFloat = 80

    var body: some View {
        ZStack(alignment: .bottom) {
            // Scrim
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            // Sheet
            VStack(spacing: 0) {
                // Drag handle
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(palette.textSecondary.opacity(0.35))
                    .frame(width: 36, height: 5)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                // Header
                HStack {
                    Text("Settings")
                        .font(Theme.Fonts.mono(20, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                            .frame(width: 32, height: 32)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Close settings")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

                Divider()
                    .background(palette.border.opacity(0.4))

                VStack(spacing: 24) {
                    appearanceSection
                    audioSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 12)

                // Safe area spacer
                Color.clear.frame(height: 24)
            }
            .frame(maxWidth: .infinity)
            .glassEffect(
                in: .rect(
                    topLeadingRadius: Theme.radius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: Theme.radius
                )
            )
            .offset(y: max(0, dragOffset))
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation.height
                    }
                    .onEnded { value in
                        if value.translation.height > dismissThreshold {
                            onClose()
                        }
                    }
            )
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var appearanceSection: some View {
        settingsGroup("Appearance", icon: "circle.lefthalf.filled") {
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(AppearancePreference.allCases) { preference in
                    Text(preference.label).tag(preference)
                }
            }
            .pickerStyle(.segmented)
            .tint(palette.primary)
        }
    }

    private var audioSection: some View {
        settingsGroup("Audio", icon: "speaker.wave.2.fill") {
            VStack(spacing: 16) {
                Toggle(isOn: $settings.audioEnabled) {
                    Text("Sound effects")
                        .font(Theme.Fonts.mono(13, weight: .medium))
                        .foregroundStyle(palette.textPrimary)
                }
                .toggleStyle(.switch)
                .tint(palette.primary)

                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                    Slider(value: $settings.audioVolume, in: 0...1)
                        .tint(palette.primary)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                    Button {
                        AudioManager.shared.preview()
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.primary)
                            .frame(width: 30, height: 30)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                }
                .opacity(settings.audioEnabled ? 1 : 0.45)
                .disabled(!settings.audioEnabled)
            }
        }
    }

    @ViewBuilder
    private func settingsGroup<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.primary)
                Text(title.uppercased())
                    .font(Theme.Fonts.mono(11, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(palette.textSecondary)
            }
            content()
        }
    }
}
