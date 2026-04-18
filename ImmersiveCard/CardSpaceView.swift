//
//  CardSpaceView.swift
//  ImmersiveCard
//
//  カード内部のイマーシブ空間ビュー
//  選択したメディア（空間写真 or 動画）をイマーシブ表示する
//

import SwiftUI
import RealityKit
import RealityKitContent
import AVFoundation

struct CardSpaceView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        RealityView { content in
            // メディア種別によって表示内容を切り替える
            if appModel.selectedMediaType == .video, let player = appModel.videoPlayer {
                // ==========================================
                // [動画モード] 空間ビデオ（Spatial Video）としてイマーシブ表示
                // VideoMaterial だけでは 2D 平面表示にしかならない。
                // VideoPlayerComponent の desiredViewingMode を .spatialStereoImmersive に
                // 設定することで Vision Pro がステレオ奥行きを持った空間ビデオとして再生する。
                // ==========================================
                let videoMaterial = VideoMaterial(avPlayer: player)

                // アスペクト比を保って画面サイズを決定（高さ 2.25m を基準）
                let screenHeight: Float = 2.25
                let screenWidth:  Float = screenHeight * appModel.videoAspectRatio

                let videoScreen = ModelEntity(
                    mesh: .generatePlane(width: screenWidth, height: screenHeight, cornerRadius: 0.05),
                    materials: [videoMaterial]
                )
                videoScreen.name = "VideoScreen"

                // VideoPlayerComponent で空間ビデオのステレオ表示と没入モードを有効にする
                var videoComp = VideoPlayerComponent(avPlayer: player)
                videoComp.desiredViewingMode = .stereo
                videoComp.desiredSpatialVideoMode = .spatial
                videoComp.desiredImmersiveViewingMode = .full
                videoScreen.components.set(videoComp)

                // 目線の高さ・正面に配置、少し遠くから手前にアニメーション
                videoScreen.position = [0, 1.6, -3.2]
                videoScreen.scale    = [0.85, 0.85, 0.85]

                content.add(videoScreen)

                // 登場アニメーション: 0.6秒かけて本来の位置・サイズへ
                videoScreen.move(
                    to: Transform(
                        scale: .one,
                        rotation: .init(angle: 0, axis: [0, 1, 0]),
                        translation: [0, 1.6, -2.5]
                    ),
                    relativeTo: nil,
                    duration: 0.6,
                    timingFunction: .easeOut
                )

                // 停止していれば再生を開始（CardPlayView で play 済みだが念のため）
                player.play()

            } else {
                // ==========================================
                // [写真モード] ImagePresentationComponent で空間写真を表示
                // ==========================================
                let imageEntity = Entity()
                imageEntity.name = "SpatialPhotoEntity"

                // 最初は少し遠くに配置してアニメーションで手前に持ってくる
                let targetPosition: SIMD3<Float> = [0, 1.7, -2.5]
                imageEntity.position = [0, 1.7, -3.0]
                imageEntity.scale = [0.8, 0.8, 0.8]

                content.add(imageEntity)

                // 既にロード済みの場合はコンポーネントをセット
                if let comp = appModel.imagePresentationComponent {
                    imageEntity.components.set(comp)
                }

                // 登場アニメーション: 0.6秒かけて本来の位置・サイズへ
                imageEntity.move(
                    to: Transform(scale: .one, rotation: .init(angle: 0, axis: [0, 1, 0]), translation: targetPosition),
                    relativeTo: nil,
                    duration: 0.6,
                    timingFunction: .easeOut
                )
            }
        } update: { content in
            // 写真モードのみ: AppModel の非同期読み込み状態を監視してUIを更新
            guard appModel.selectedMediaType != .video else { return }

            if let imageEntity = content.entities.first(where: { $0.name == "SpatialPhotoEntity" }) {
                // ロードが完了しコンポーネントが用意された場合
                if let comp = appModel.imagePresentationComponent {
                    imageEntity.components.set(comp)

                    // フォールバック用の平面Entityが表示されていれば破棄する
                    if !imageEntity.children.isEmpty {
                        imageEntity.children.removeAll()
                    }
                }
                // エラーが発生してまだフォールバックも表示されていない場合
                else if appModel.spatialPhotoLoadError != nil && imageEntity.children.isEmpty {
                    Task { @MainActor in
                        await fallbackDisplay(imageEntity: imageEntity)
                    }
                }
            }
        }
        // 写真アプリと同じ暗転演出：パススルーカメラを暗くして空間写真を浮かび上がらせる
        .preferredSurroundingsEffect(.systemDark)
        .task {
            // 動画モードの場合はここでの処理は不要（AVPlayerで制御済み）
            guard appModel.selectedMediaType != .video else { return }

            // imagePresentationComponent が既にロード済みの場合は再読み込み不要
            // （写真選択フェーズで事前にロードされているはず）
            guard appModel.imagePresentationComponent == nil else {
                print("[CardSpaceView] 既存の imagePresentationComponent を使用します")
                return
            }

            // 未ロードの場合は selectedPhotoURL を優先し、なければデフォルトを探す
            await appModel.loadSpatialPhoto(from: appModel.selectedPhotoURL)
        }
    }   // body

    // MARK: - フォールバック表示

    /// xcassetsからTextureResourceで読み込んで平面表示（立体感なし）
    private func fallbackDisplay(imageEntity: Entity) async {
        // 4:3 横長で表示（縦長の空間に合わせてサイズ調整）
        let picWidth: Float  = 2.4
        let picHeight: Float = 1.8

        let pictureModel = ModelEntity(
            mesh: .generateBox(size: [picWidth, picHeight, 0.001]),
            materials: [SimpleMaterial(color: .white, isMetallic: false)]
        )

        if let tex = try? await TextureResource(named: "Picture") {
            var mat = UnlitMaterial()
            mat.color = .init(texture: .init(tex))
            await MainActor.run {
                pictureModel.model?.materials = [mat]
            }
        }

        await MainActor.run {
            imageEntity.addChild(pictureModel)
        }
    }
}

#Preview(immersionStyle: .mixed) {
    CardSpaceView()
        .environment(AppModel())
}
