//
//  ImmersiveCardApp.swift
//  ImmersiveCard
//
//  Created by Yuki Hamaguchi on 2026/04/13.
//

import SwiftUI

@main
struct ImmersiveCardApp: App {

    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.8, height: 0.8, depth: 0.8, in: .meters) // 回転時にはみ出ないように大きめのサイズを確保

        // 既存のイマーシブ空間（テスト用）
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)

        // カード空間 — .mixed + systemDark で写真アプリと同じ暗転演出を実現
        ImmersiveSpace(id: appModel.cardSpaceID) {
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
