import SwiftUI

@main
struct ImmersiveCardApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        // Scene 1: メニュー画面 (Sec 1, 2, 3) - 専用の2Dウィンドウ
        WindowGroup(id: "MenuWindow") {
            HomeMenuView()
                .environment(appModel)
        }
        .windowStyle(.plain)

        // Scene 2: カード表示 (Sec 4) - 聖域であるVolumetricウィンドウ
        WindowGroup(id: "CardWindow") {
            CardPlayView()
                .environment(appModel)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.8, height: 0.8, depth: 0.8, in: .meters)

        // カード空間 (イマーシブ)
        ImmersiveSpace(id: "CardSpace") {
            CardSpaceView()
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                    appModel.displayMode = .immersive
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                    appModel.displayMode = .windowed
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
     }
}
