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
        RealityView { content, attachments in
            // ==========================================
            // 空間写真をImagePresentationComponentで表示
            // ==========================================
            let imageEntity = Entity()
            imageEntity.name = "SpatialPhotoEntity"
            imageEntity.position = [0, 1.5, -2.5]

            // ImagePresentationComponent で空間写真を読み込む
            // ※ Bundle直参照のためには Xcode で .HEIC をバンドルリソースとして追加する必要がある
            // （xcassetsから外して直接ドラッグ追加：File → Add Files to "ImmersiveCard"）
            let possibleURLs: [URL?] = [
                // バンドルリソースとして直接追加した場合
                Bundle.main.url(forResource: "Picture2", withExtension: "HEIC"),
                Bundle.main.url(forResource: "Picture",  withExtension: "HEIC"),
            ]

            var loaded = false
            for case let url? in possibleURLs {
                if let imageComp = try? await ImagePresentationComponent(contentsOf: url) {
                    var comp = imageComp
                    // spatialStereo が使える（＝空間写真として認識された）場合に要求
                    if comp.availableViewingModes.contains(.spatialStereo) {
                        comp.desiredViewingMode = .spatialStereo
                    }
                    await MainActor.run {
                        imageEntity.components.set(comp)
                    }
                    loaded = true
                    break
                }
            }

            // 上記が失敗した場合は TextureResource でフォールバック表示
            if !loaded {
                await fallbackDisplay(imageEntity: imageEntity)
            }

            content.add(imageEntity)

            // ==========================================
            // 「現実に戻る」ボタン（RealityView attachments）
            // ==========================================
            if let returnPanel = attachments.entity(for: "returnButton") {
                returnPanel.position = [0, 0.3, -1.5]
                content.add(returnPanel)
            }

        } attachments: {
            Attachment(id: "returnButton") {
                Button {
                    Task { @MainActor in
                        await dismissImmersiveSpace()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.title2)
                        Text("現実に戻る")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
                .glassBackgroundEffect()
            }
        }
        // 写真アプリと同じ暗転演出：パススルーカメラを暗くして空間写真を浮かび上がらせる
        .preferredSurroundingsEffect(.systemDark)
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
