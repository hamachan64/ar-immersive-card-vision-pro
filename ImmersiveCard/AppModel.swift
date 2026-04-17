//
//  AppModel.swift
//  ImmersiveCard
//
//  Created by Yuki Hamaguchi on 2026/04/13.
//

import SwiftUI
import RealityKit
import PhotosUI

/// アプリ全体の状態を管理するクラス
/// WindowGroupとImmersiveSpace間で表示モードを共有する
@MainActor
@Observable
class AppModel {
    // MARK: - アプリの進行フェーズ

    /// アプリの進行状態を表す列挙型
    enum AppPhase {
        case title          // 1: タイトル（ImmersiveCard）
        case photoSelection // 2: 写真を選択
        case paint          // 3: ペイントデコレーション
        case cardPlay       // 4: カード遊び
    }

    /// 現在の進行フェーズ
    var phase: AppPhase = .title

    /// 次のフェーズへ進む
    func nextPhase() {
        switch phase {
        case .title:
            phase = .photoSelection
        case .photoSelection:
            phase = .paint
        case .paint:
            phase = .cardPlay
        case .cardPlay:
            // 遊び終わったら最初に戻る（あるいは現状維持）
            phase = .title
        }
    }

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

    // MARK: - 選択された写真の管理

    /// ユーザーが選択した写真のローカルURL（一時ファイル）
    var selectedPhotoURL: URL?

    /// ユーザーが選択したPhotosPickerItemを処理し、アプリ内で扱えるURLに変換する
    func updatePhoto(from item: PhotosPickerItem?) async {
        guard let item = item else { return }

        do {
            // データを取得（空間写真の場合はHEIC形式を期待）
            guard let data = try await item.loadTransferable(type: Data.self) else {
                print("[AppModel] 写真データの取得に失敗しました")
                return
            }

            // 一時ファイルとして保存
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("HEIC")

            try data.write(to: tempURL)

            // URLを更新（これによりContentView側が検知可能）
            self.selectedPhotoURL = tempURL
            
            // 重要: 空間写真としての読み込み（事前ロード）
            await loadSpatialPhoto(from: tempURL)

            print("[AppModel] 写真を更新しました: \(tempURL.lastPathComponent)")

        } catch {
            print("[AppModel] 写真の更新中にエラーが発生しました: \(error)")
        }
    }

    // MARK: - 空間写真のデータ管理

    /// 空間写真を表示するためのコンポーネント
    var imagePresentationComponent: ImagePresentationComponent?
    var isSpatialPhotoLoaded: Bool = false
    var spatialPhotoLoadError: String?

    /// 空間写真（または外部URL）を非同期で読み込む
    func loadSpatialPhoto(from externalURL: URL? = nil) async {
        // externalURLが指定されていればそれを使用、なければバンドル内のデフォルトを探す
        var targetURL: URL? = externalURL
        
        if targetURL == nil {
            let possibleFilenames = ["SpatialPhoto", "Picture2", "Picture"]
            // BundleからファイルURLを安全に取得
            for filename in possibleFilenames {
                if let url = Bundle.main.url(forResource: filename, withExtension: "HEIC") {
                    targetURL = url
                    break
                }
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
