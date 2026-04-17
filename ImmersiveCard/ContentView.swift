import SwiftUI
import RealityKit
import RealityKitContent

// MARK: - カードの基本サイズ定数（make/update closure 間で共有）
private let kCardWidth:  Float = 0.3
private let kCardHeight: Float = 0.4

// MARK: - ECS: ドラッグ回転用コンポーネントとシステム

/// カードをドラッグで回転させるためのコンポーネント
public struct RotationComponent: Component {
    public var speed: Float
    public var axis: SIMD3<Float>
    public init(speed: Float = 1.0, axis: SIMD3<Float> = [0, 1, 0]) {
        self.speed = speed
        self.axis = axis
    }
}

/// 毎フレーム呼び出され、RotationComponentを持つEntityを回転させるシステム
public class RotationSystem: System {
    private static let query = EntityQuery(where: .has(RotationComponent.self))
    public required init(scene: RealityKit.Scene) {}
    public func update(context: SceneUpdateContext) {
        for entity in context.scene.performQuery(Self.query) {
            guard let comp = entity.components[RotationComponent.self] else { continue }
            let deltaRot = simd_quatf(angle: comp.speed * Float(context.deltaTime), axis: comp.axis)
            entity.transform.rotation = entity.transform.rotation * deltaRot
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    // ドラッグ回転状態
    @State private var dragRotation: simd_quatf = .init(angle: 0, axis: [0, 1, 0])
    @State private var baseRotation: simd_quatf = .init(angle: 0, axis: [0, 1, 0])

    // 各 Entity への参照（表示制御に使用）
    @State private var cardRootEntity:    Entity?
    @State private var spatialPhotoEntity: Entity?      // 空間写真（立体表示）
    @State private var framePlaneEntity:  ModelEntity?  // フレーム装飾（非表示対象）
    @State private var backPlaneEntity:   ModelEntity?  // カード裏面（非表示対象）
    @State private var portalPlaneEntity: ModelEntity?  // ポータル窓（非表示対象）

    init() {
        RotationComponent.registerComponent()
        RotationSystem.registerSystem()
    }

    var body: some View {
        RealityView { content in
            let cardCornerRadius: Float = 0.03
            let cardDepth: Float = 0.002

            // ==========================================
            // カードルート（回転・インタラクション用）
            // ==========================================
            let cardRoot = Entity()
            cardRoot.name = "CardFrame"
            cardRoot.components.set(InputTargetComponent())
            cardRoot.components.set(CollisionComponent(
                shapes: [.generateBox(size: [kCardWidth, kCardHeight, cardDepth])]
            ))

            // ==========================================
            // ポータルの向こう側の世界（WorldEntity）
            // ==========================================
            let worldEntity = Entity()
            worldEntity.components.set(WorldComponent())

            // ==========================================
            // 空間写真エンティティ（ImagePresentationComponent）
            // Portalの向こう側に置くことで、3:4にはみ出た写真をクロップ＆遮蔽する
            // ==========================================
            let photoEntity = Entity()
            photoEntity.name = "SpatialPhoto"
            photoEntity.position = [0, 0, 0]

            // Bundle からHEICファイルのURLを探す
            // ※ xcassetsではなく直接バンドルリソースとして追加されている場合に有効
            let candidateURLs: [URL?] = [
                Bundle.main.url(forResource: "Picture2", withExtension: "HEIC"),
                Bundle.main.url(forResource: "Picture",  withExtension: "HEIC"),
            ]

            var usedImagePresentation = false
            for case let url? in candidateURLs {
                if var imageComp = try? await ImagePresentationComponent(contentsOf: url) {
                    // spatialStereo が使えるなら立体表示を要求
                    if imageComp.availableViewingModes.contains(.spatialStereo) {
                        imageComp.desiredViewingMode = .spatialStereo
                    }
                    // カードの高さに合わせてスクリーンサイズを明示指定（0.4m）
                    // 幅は画像のアスペクト比から自動計算される
                    imageComp.screenHeight = kCardHeight
                    await MainActor.run {
                        photoEntity.components.set(imageComp)
                    }
                    usedImagePresentation = true
                    break
                }
            }

            // フォールバック：TextureResource でフラット表示（立体なし）
            if !usedImagePresentation {
                let imageAspect: Float = 4.0 / 3.0
                let picWidth = kCardHeight * imageAspect    // 4:3 比率でメッシュを作成
                let fallbackModel = ModelEntity(
                    mesh: .generateBox(size: [picWidth, kCardHeight, 0.0001], cornerRadius: cardCornerRadius),
                    materials: [SimpleMaterial(color: .white, isMetallic: false)]
                )
                if let tex = try? await TextureResource(named: "Picture") {
                    var mat = UnlitMaterial()
                    mat.color = .init(texture: .init(tex))
                    mat.blending = .transparent(opacity: .init(scale: 1.0))
                    await MainActor.run { fallbackModel.model?.materials = [mat] }
                }
                await MainActor.run { photoEntity.addChild(fallbackModel) }
            }

            worldEntity.addChild(photoEntity)
            cardRoot.addChild(worldEntity)

            // ==========================================
            // ポータル（窓）
            // 写真をカードサイズにクロップするためのコンポーネント
            // ==========================================
            let portalPlane = ModelEntity(
                mesh: .generateBox(size: [kCardWidth, kCardHeight, 0.0001], cornerRadius: cardCornerRadius),
                materials: [PortalMaterial()]
            )
            portalPlane.position = [0, 0, 0]
            portalPlane.components.set(PortalComponent(target: worldEntity))
            cardRoot.addChild(portalPlane)

            // ==========================================
            // カードフレーム（透過PNG → 写真の上に重ねる窓枠）
            // イマーシブ移行時にこれが「溶けて消える」対象
            // ==========================================
            let framePlane = ModelEntity(
                mesh: .generateBox(size: [kCardWidth, kCardHeight, 0.001], cornerRadius: cardCornerRadius),
                materials: [SimpleMaterial(color: .white, isMetallic: false)]
            )
            // 空間写真エンティティより少し手前に配置して重なるようにする
            framePlane.position = [0, 0, 0.002]
            Task {
                if let texture = try? await TextureResource(named: "Frame") {
                    var mat = UnlitMaterial()
                    mat.blending = .transparent(opacity: .init(scale: 1.0))
                    mat.color = .init(texture: .init(texture))
                    await MainActor.run { framePlane.model?.materials = [mat] }
                }
            }
            cardRoot.addChild(framePlane)

            // ==========================================
            // カード裏面
            // イマーシブ移行時に非表示にする
            // ==========================================
            let backPlane = ModelEntity(
                mesh: .generateBox(size: [kCardWidth, kCardHeight, 0.001], cornerRadius: cardCornerRadius),
                materials: [SimpleMaterial(color: .white, isMetallic: false)]
            )
            backPlane.position = [0, 0, -0.001]
            backPlane.transform.rotation = simd_quatf(angle: .pi, axis: [0, 1, 0])
            Task {
                if let texture = try? await TextureResource(named: "Back") {
                    var mat = UnlitMaterial()
                    mat.color = .init(texture: .init(texture))
                    await MainActor.run { backPlane.model?.materials = [mat] }
                }
            }
            cardRoot.addChild(backPlane)

            // シーンに追加して各参照を保持
            content.add(cardRoot)
            self.cardRootEntity     = cardRoot
            self.spatialPhotoEntity = photoEntity
            self.framePlaneEntity   = framePlane
            self.backPlaneEntity    = backPlane
            self.portalPlaneEntity  = portalPlane

        } update: { content in
            guard appModel.displayMode == .windowed else { return }

            // ドラッグ回転をカードルートに反映
            if let cardFrame = content.entities.first(where: { $0.name == "CardFrame" }) {
                cardFrame.transform.rotation = dragRotation * baseRotation
            }
        }
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    guard appModel.displayMode == .windowed else { return }
                    let h = simd_quatf(angle: Float(value.translation.width)  * 0.01, axis: [0, 1, 0])
                    let v = simd_quatf(angle: Float(value.translation.height) * 0.01, axis: [1, 0, 0])
                    dragRotation = h * v
                }
                .onEnded { _ in
                    guard appModel.displayMode == .windowed else { return }
                    baseRotation = dragRotation * baseRotation
                    dragRotation = .init(angle: 0, axis: [0, 1, 0])
                }
        )
        .onChange(of: appModel.displayMode) { _, newValue in
            if newValue == .immersive {
                // イマーシブへ移行: フレームと写真・ポータルを非表示
                framePlaneEntity?.isEnabled   = false
                backPlaneEntity?.isEnabled    = false
                portalPlaneEntity?.isEnabled  = false
                spatialPhotoEntity?.isEnabled = false
            } else {
                // Window に戻る: すべて再表示してリセット
                framePlaneEntity?.isEnabled   = true
                backPlaneEntity?.isEnabled    = true
                portalPlaneEntity?.isEnabled  = true
                spatialPhotoEntity?.isEnabled = true
                resetCardTransform()
            }
        }
        // 「空間に入る / 現実に戻る」ボタン (トグル)
        .ornament(attachmentAnchor: .scene(.bottom)) {
            Button {
                Task { @MainActor in
                    if appModel.immersiveSpaceState == .closed {
                        await enterCardSpace()
                    } else if appModel.immersiveSpaceState == .open {
                        appModel.immersiveSpaceState = .inTransition
                        await dismissImmersiveSpace()
                    }
                }
            } label: {
                if appModel.immersiveSpaceState == .open {
                    Label("現実に戻る", systemImage: "arrow.uturn.backward.circle.fill")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                } else {
                    Label("空間に入る", systemImage: "sparkles")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }
            }
            .disabled(appModel.immersiveSpaceState == .inTransition)
            .padding()
            .glassBackgroundEffect()
        }
    }

    // MARK: - イマーシブ空間への遷移

    /// 写真アプリに倣ったシームレスな遷移:
    /// ① カードフレームを非表示
    /// ② カードを正面・中央に向けてアニメーション
    /// ③ 空間写真を非表示にして ImmersiveSpace を開く
    private func enterCardSpace() async {
        guard appModel.immersiveSpaceState == .closed else { return }

        // フレームと裏面、ポータルを即座に非表示（フレームが「溶けて消える」）
        framePlaneEntity?.isEnabled  = false
        backPlaneEntity?.isEnabled   = false
        portalPlaneEntity?.isEnabled = false

        // カードを正面向きに整列しつつ、ユーザー方向へ少し前進させる
        if let cardRoot = cardRootEntity {
            let centerTransform = Transform(
                scale: SIMD3<Float>(repeating: 1.0),
                rotation: simd_quatf(angle: 0, axis: [0, 1, 0]),  // 正面を向かせる
                translation: SIMD3<Float>(0, 0, 0.08)              // 視点方向へわずかに前進
            )
            cardRoot.move(
                to: centerTransform,
                relativeTo: cardRoot.parent,
                duration: 0.4,
                timingFunction: .easeInOut
            )
            // アニメーション完了を待つ
            try? await Task.sleep(for: .seconds(0.4))
        }

        // 写真エンティティを非表示にしてから ImmersiveSpace を開く
        spatialPhotoEntity?.isEnabled = false
        appModel.immersiveSpaceState = .inTransition

        switch await openImmersiveSpace(id: appModel.cardSpaceID) {
        case .opened:
            break   // displayMode は CardSpaceView の onAppear で .immersive に切り替わる
        case .userCancelled, .error:
            fallthrough
        @unknown default:
            // 失敗したらすべて元に戻す
            appModel.immersiveSpaceState = .closed
            framePlaneEntity?.isEnabled   = true
            backPlaneEntity?.isEnabled    = true
            portalPlaneEntity?.isEnabled  = true
            spatialPhotoEntity?.isEnabled = true
            resetCardTransform()
        }
    }

    // MARK: - リセット

    /// カードのトランスフォームをアニメーション付きで初期状態に戻す
    private func resetCardTransform() {
        guard let cardRoot = cardRootEntity else { return }
        cardRoot.move(
            to: Transform(
                scale: .one,
                rotation: .init(angle: 0, axis: [0, 1, 0]),
                translation: .zero
            ),
            relativeTo: cardRoot.parent,
            duration: 0.5,
            timingFunction: .easeOut
        )
        dragRotation = .init(angle: 0, axis: [0, 1, 0])
        baseRotation = .init(angle: 0, axis: [0, 1, 0])
    }
}

#Preview(windowStyle: .volumetric) {
    ContentView()
        .environment(AppModel())
}
