//
//  CardSpaceView.swift
//  ImmersiveCard
//
//  カード内部のイマーシブ空間ビュー
//  iPhoneで撮影した空間写真をImagePresentationComponentでステレオ表示する
//

import SwiftUI
import RealityKit
import RealityKitContent

struct CardSpaceView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        RealityView { content in
            // ==========================================
            // 空間写真を設定するためのホストEntity
            // (状態管理はAppModelに委譲し、View側には重い処理を書かない設計)
            // ==========================================
            let imageEntity = Entity()
            imageEntity.name = "SpatialPhotoEntity"
            imageEntity.position = [0, 1.5, -2.5]
            
            content.add(imageEntity)

            // 既にロード済みの場合は初期時にコンポーネントをセット
            if let comp = appModel.imagePresentationComponent {
                imageEntity.components.set(comp)
            }
        } update: { content in
            // ==========================================
            // AppModelの非同期読み込み状態を監視してUIを更新
            // ==========================================
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
            // アセットの非同期読み込みを実行（重い処理をモデルに分離）
            await appModel.loadSpatialPhoto()
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
