//
//  AppModel.swift
//  ImmersiveCard
//
//  Created by Yuki Hamaguchi on 2026/04/13.
//

import SwiftUI
import RealityKit
import PhotosUI
import AVFoundation

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

    // MARK: - Scene IDs (UnityのScene切り分けに相当)

    /// メニュー用ウィンドウID (Sec 1, 2, 3)
    let menuWindowID = "MenuWindow"

    /// カード遊び用ウィンドウID (Sec 4)
    let cardWindowID = "CardWindow"

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

    // MARK: - 選択されたメディアの種別管理

    /// 選択されたメディアの種別
    enum MediaType {
        case photo  // 静止画（HEIC等）
        case video  // 動画（MP4等）
    }

    /// 現在選択されているメディアの種別（nil = 未選択）
    var selectedMediaType: MediaType?

    /// ユーザーが選択した写真のローカルURL（一時ファイル）
    var selectedPhotoURL: URL?

    /// ユーザーが選択した動画のローカルURL（一時ファイルにコピー済み）
    var selectedVideoURL: URL?

    /// 動画再生用のAVPlayer（フェーズ4でVideoPlayerComponentに渡す）
    var videoPlayer: AVPlayer?

    /// 動画の実際のアスペクト比（幅 / 高さ）- メッシュサイズ計算に使用
    var videoAspectRatio: Float = 16.0 / 9.0

    /// ユーザーが選択したPhotosPickerItemを処理し、画像か動画かを判別してアプリ内に保持する
    func updatePhoto(from item: PhotosPickerItem?) async {
        guard let item = item else { return }

        // --- 動画の場合 ---
        // PhotosPickerItem が動画かどうかは contentType で判別する
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) || $0.identifier.contains("video") }) {
            await loadVideo(from: item)
            return
        }

        // --- 静止画の場合 ---
        await loadPhoto(from: item)
    }

    /// 静止画（HEIC等）を一時ファイルに保存し、空間写真としてロードする
    private func loadPhoto(from item: PhotosPickerItem) async {
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

            self.selectedPhotoURL = tempURL
            self.selectedVideoURL = nil
            self.videoPlayer = nil
            self.selectedMediaType = .photo

            // 空間写真としての事前ロード
            await loadSpatialPhoto(from: tempURL)

            print("[AppModel] 写真を更新しました: \(tempURL.lastPathComponent)")

        } catch {
            print("[AppModel] 写真の更新中にエラーが発生しました: \(error)")
        }
    }

    /// 動画をアプリの一時ディレクトリにコピーし、AVPlayerを生成して保持する
    private func loadVideo(from item: PhotosPickerItem) async {
        do {
            // PhotosKit の AVAsset transferable を使って動画URLを取得する
            // Transferable として URL を直接取得できないため、AVAsset経由で処理する
            guard let videoData = try await item.loadTransferable(type: Data.self) else {
                print("[AppModel] 動画データの取得に失敗しました")
                return
            }

            // 一時ディレクトリに MP4 として保存
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")

            try videoData.write(to: tempURL)

            // AVAsset から動画トラックの実際のサイズを取得してアスペクト比を算出する
            // 空間ビデオは横長（例: 5760x2880）なのでそのまま width/height を使う
            let asset = AVAsset(url: tempURL)
            var aspectRatio: Float = 16.0 / 9.0
            if let track = try? await asset.loadTracks(withMediaType: .video).first {
                let naturalSize  = try? await track.load(.naturalSize)
                let preferredTransform = try? await track.load(.preferredTransform)
                if let size = naturalSize {
                    // preferredTransform で回転が加わる場合（縦動画等）を考慮
                    let txSize = size.applying(preferredTransform ?? .identity)
                    let w = abs(txSize.width)
                    let h = abs(txSize.height)
                    if h > 0 { aspectRatio = Float(w / h) }
                }
            }

            let player = AVPlayer(url: tempURL)

            // 動画終了時にループ再生するための通知を登録
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in
                player.seek(to: .zero)
                player.play()
            }

            self.selectedVideoURL  = tempURL
            self.selectedPhotoURL  = nil
            self.imagePresentationComponent = nil
            self.isSpatialPhotoLoaded = false
            self.videoPlayer       = player
            self.videoAspectRatio  = aspectRatio
            self.selectedMediaType = .video

            print("[AppModel] 動画を更新しました: \(tempURL.lastPathComponent)")

        } catch {
            print("[AppModel] 動画の更新中にエラーが発生しました: \(error)")
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
