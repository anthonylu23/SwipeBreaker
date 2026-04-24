import SwiftUI

@main
struct SwipeBreakerApp: App {
    var body: some Scene {
#if os(macOS)
        WindowGroup {
            GameView()
                .frame(minWidth: 260, minHeight: 560)
                .background(Theme.dark.background)
        }
        .defaultSize(width: 430, height: 930)
#else
        WindowGroup {
            GameView()
                .ignoresSafeArea()
        }
#endif
    }
}
