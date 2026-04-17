//
//  AppModel.swift
//  ImmersiveCard
//
//  Created by Yuki Hamaguchi on 2026/04/13.
//

import SwiftUI
import RealityKit

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

    // MARK: - 空間写真のデータ管理

    /// 空間写真を表示するためのコンポーネント
    var imagePresentationComponent: ImagePresentationComponent?
    var isSpatialPhotoLoaded: Bool = false
    var spatialPhotoLoadError: String?

    /// バンドル内の空間写真（Testアセット等）を非同期で読み込む
    /// RealityViewの中で重い処理を行わないための設計
    func loadSpatialPhoto() async {
        guard !isSpatialPhotoLoaded else { return }
        
        let possibleFilenames = ["SpatialPhoto", "Picture2", "Picture"]
        var targetURL: URL? = nil
        
        // BundleからファイルURLを安全に取得
        for filename in possibleFilenames {
            if let url = Bundle.main.url(forResource: filename, withExtension: "HEIC") {
                targetURL = url
                break
            }
        }
        
        guard let url = targetURL else {
            spatialPhotoLoadError = "空間写真ファイルが見つかりません"
            print("[AppModel] \(spatialPhotoLoadError!)")
            return
        }
        
        do {
            // RealityKitのAPIを使用して、URLから直接ImagePresentationComponentを作成
            var comp = try await ImagePresentationComponent(contentsOf: url)
            
            // [CRITICAL] 没入モードの適用
            // 自動的なパススルー・ディミング、スケール調整、境界線のソフトエッジ処理を再現するため
            comp.desiredViewingMode = .spatialStereoImmersive
            
            self.imagePresentationComponent = comp
            self.isSpatialPhotoLoaded = true
            print("[AppModel] 空間写真の読み込みに成功しました: \(url.lastPathComponent)")
            
        } catch {
            spatialPhotoLoadError = error.localizedDescription
            print("[AppModel] 空間写真の読み込みに失敗しました: \(error)")
        }
    }
}
