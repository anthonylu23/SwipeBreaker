import SpriteKit
import SwiftUI

@MainActor
final class GameController: ObservableObject {
    let scene: GameScene

    init() {
        let store = SaveStore()
        scene = GameScene(store: store)
        scene.scaleMode = .resizeFill
    }
}

struct GameView: View {
    @StateObject private var controller = GameController()
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLoaded = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            SpriteView(
                scene: controller.scene,
                options: [.ignoresSiblingOrder]
            )
            .ignoresSafeArea()
            .opacity(isLoaded ? 1 : 0)

            if !isLoaded {
                LoadingOverlay()
                    .transition(.opacity)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                withAnimation(.easeOut(duration: 0.45)) {
                    isLoaded = true
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                controller.scene.persistCompletedTurn()
            }
        }
    }
}

private struct LoadingOverlay: View {
    @State private var dotPhase = 0
    @State private var glowOpacity = 0.4

    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.07, blue: 0.13),
                    Color(red: 0.012, green: 0.012, blue: 0.022)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("SWIPE")
                    .font(.system(size: 44, weight: .heavy, design: .monospaced))
                    .tracking(6)
                    .foregroundStyle(Color.white.opacity(0.95))
                Text("BREAKER")
                    .font(.system(size: 44, weight: .heavy, design: .monospaced))
                    .tracking(6)
                    .foregroundStyle(Color(red: 0.55, green: 0.85, blue: 1.0))
                    .shadow(color: Color(red: 0.55, green: 0.85, blue: 1.0).opacity(glowOpacity), radius: 12)

                Text(loadingText)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(Color.white.opacity(0.55))
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
