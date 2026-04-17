//
//  AppModel.swift
//  ImmersiveCard
//
//  Created by Yuki Hamaguchi on 2026/04/13.
//

import SwiftUI

/// アプリ全体の状態を管理するクラス
/// WindowGroupとImmersiveSpace間で表示モードを共有する
@MainActor
@Observable
class AppModel {
    // MARK: - 表示モード

    /// 現在の表示状態を表す列挙型
    enum DisplayMode {
        case windowed   // 通常のカード表示（ウィンドウ内）
        case immersive  // イマーシブ空間で写真を表示中
    }

    /// WindowとImmersiveSpace間で共有する表示モード
    var displayMode: DisplayMode = .windowed

    // MARK: - ImmersiveSpace ID

    /// 既存のイマーシブ空間ID（テスト用）
    let immersiveSpaceID = "ImmersiveSpace"

    /// カード空間のID（空間写真表示先）
    let cardSpaceID = "CardSpace"

    // MARK: - 状態管理

    /// ImmersiveSpaceの開閉状態
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed
}
