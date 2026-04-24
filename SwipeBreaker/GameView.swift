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

    var body: some View {
        SpriteView(
            scene: controller.scene,
            options: [.ignoresSiblingOrder]
        )
        .background(Color.black)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                controller.scene.persistCompletedTurn()
            }
        }
    }
}
