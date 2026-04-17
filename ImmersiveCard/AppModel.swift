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
    
    /// 画像の横縦比（デフォルトは3:4の縦長を想定して0.75）
    var imageAspectRatio: Float = 0.75

    /// バンドル内の空間写真（Testアセット等）を非同期で読み込む
    /// RealityViewの中で重い処理を行わないための設計
    func loadSpatialPhoto() async {
        guard !isSpatialPhotoLoaded else { return }
        
        var targetURL: URL? = nil
        var is2DImage = false
        
        // 1. Assets.xcassets等に登録された "Picture" をUIImageとして読み込み、一時ファイル化するアプローチ（2D/PNG用）
        if let uiImage = UIImage(named: "Picture"), let pngData = uiImage.pngData() {
            // 比率を保存 (width / height)
            self.imageAspectRatio = Float(uiImage.size.width / uiImage.size.height)
            
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Picture.png")
            do {
                try pngData.write(to: tempURL)
                targetURL = tempURL
                is2DImage = true
            } catch {
                print("[AppModel] 一時ファイルへの保存に失敗しました: \(error)")
            }
        }
        
        // 2. UIImageから取得できなかった場合は、バンドル内のHEICファイル等を探す
        if targetURL == nil {
            let possibleFilenames = ["Picture", "Picture2", "SpatialPhoto"]
            for filename in possibleFilenames {
                if let url = Bundle.main.url(forResource: filename, withExtension: "png") {
                    targetURL = url
                    is2DImage = true
                    break
                } else if let url = Bundle.main.url(forResource: filename, withExtension: "HEIC") {
                    targetURL = url
                    is2DImage = false
                    break
                }
            }
        }
        
        guard let url = targetURL else {
            spatialPhotoLoadError = "画像ファイルが見つかりません"
            print("[AppModel] \(spatialPhotoLoadError!)")
            return
        }
        
        do {
            if is2DImage {
                // 1. 画像を読み込む
                let spatial3DImage = try await ImagePresentationComponent.Spatial3DImage(contentsOf: url)
                
                // 2. モードを 3DImmersive に設定
                var comp = ImagePresentationComponent(spatial3DImage: spatial3DImage)
                comp.desiredViewingMode = .spatial3DImmersive
                
                // 3. AIに3D空間を生成させる（数秒かかる）
                print("[AppModel] AIによる3D空間の生成を開始します...")
                try await spatial3DImage.generate()
                print("[AppModel] 3D空間の生成が完了しました！")
                
                self.imagePresentationComponent = comp
                self.isSpatialPhotoLoaded = true
            } else {
                // HEIC（既存の空間写真）の場合
                var comp = try await ImagePresentationComponent(contentsOf: url)
                comp.desiredViewingMode = .spatialStereoImmersive
                
                self.imagePresentationComponent = comp
                self.isSpatialPhotoLoaded = true
                print("[AppModel] 空間写真の読み込みに成功しました: \(url.lastPathComponent)")
            }
            
        } catch {
            spatialPhotoLoadError = error.localizedDescription
            print("[AppModel] 画像の読み込みまたは3D化に失敗しました: \(error)")
        }
    }
}
