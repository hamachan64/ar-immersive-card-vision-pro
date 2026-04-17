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
        VStack {
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
                // ==========================================
                let photoEntity = Entity()
                photoEntity.name = "SpatialPhoto"
                photoEntity.position = [0, 0, 0]

                // AppModelでの3D化処理（数秒）が完了するまでの代替表示（2D版のPicture）
                let picWidth = kCardHeight * appModel.imageAspectRatio
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

                worldEntity.addChild(photoEntity)
                cardRoot.addChild(worldEntity)

                let portalPlane = ModelEntity(
                    mesh: .generateBox(size: [kCardWidth, kCardHeight, 0.0001], cornerRadius: cardCornerRadius),
                    materials: [PortalMaterial()]
                )
                portalPlane.position = [0, 0, 0]
                portalPlane.components.set(PortalComponent(target: worldEntity))
                cardRoot.addChild(portalPlane)

                let framePlane = ModelEntity(
                    mesh: .generateBox(size: [kCardWidth, kCardHeight, 0.001], cornerRadius: cardCornerRadius),
                    materials: [SimpleMaterial(color: .white, isMetallic: false)]
                )
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

                content.add(cardRoot)
                self.cardRootEntity     = cardRoot
                self.spatialPhotoEntity = photoEntity
                self.framePlaneEntity   = framePlane
                self.backPlaneEntity    = backPlane
                self.portalPlaneEntity  = portalPlane

            } update: { content in
                // 遷移中や没入モード中は自動更新を停止（アニメーションとの競合防止）
                guard appModel.displayMode == .windowed,
                      appModel.immersiveSpaceState == .closed else { return }

                if let cardFrame = content.entities.first(where: { $0.name == "CardFrame" }) {
                    cardFrame.transform.rotation = dragRotation * baseRotation
                }
                
                // AppModelから読み込んだ画像コンポーネントを適用
                if let cardFrame = content.entities.first(where: { $0.name == "CardFrame" }),
                   let photoEntity = cardFrame.findEntity(named: "SpatialPhoto") {
                    
                    if appModel.isSpatialPhotoLoaded, let comp = appModel.imagePresentationComponent {
                        if !photoEntity.components.has(ImagePresentationComponent.self) {
                            var windowComp = comp
                            // Window用の表示モードに調整
                            // AI生成された3D写真なら .spatial3D を、通常の空間写真なら .spatialStereo を優先
                            if windowComp.availableViewingModes.contains(.spatial3D) {
                                windowComp.desiredViewingMode = .spatial3D
                            } else if windowComp.availableViewingModes.contains(.spatialStereo) {
                                windowComp.desiredViewingMode = .spatialStereo
                            } else {
                                windowComp.desiredViewingMode = windowComp.availableViewingModes.first ?? windowComp.desiredViewingMode
                            }
                            windowComp.screenHeight = kCardHeight
                            photoEntity.components.set(windowComp)
                            // フォールバック用の2D画像を削除
                            photoEntity.children.removeAll()
                        }
                    }
                }
            }
            .gesture(
                DragGesture()
                    .targetedToAnyEntity()
                    .onChanged { value in
                        guard appModel.displayMode == .windowed,
                              appModel.immersiveSpaceState == .closed else { return }
                        let h = simd_quatf(angle: Float(value.translation.width)  * 0.01, axis: [0, 1, 0])
                        let v = simd_quatf(angle: Float(value.translation.height) * 0.01, axis: [1, 0, 0])
                        dragRotation = h * v
                    }
                    .onEnded { _ in
                        guard appModel.displayMode == .windowed,
                              appModel.immersiveSpaceState == .closed else { return }
                        baseRotation = dragRotation * baseRotation
                        dragRotation = .init(angle: 0, axis: [0, 1, 0])
                    }
            )
        }
        .contentShape(Rectangle()) // ヒットテストの判定範囲を確保
        .onChange(of: appModel.displayMode) { _, newValue in
            if newValue == .immersive {
                // イマーシブ移行処理（実際はenterCardSpaceで制御するが念のため）
            } else {
                // Window に戻る: すべて再表示してリセット
                resetCardTransform()
            }
        }
        .task {
            // アセットの非同期読み込みと3D化演算を開始
            await appModel.loadSpatialPhoto()
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
    
    /// 写真アプリに倣ったシームレスな遷移
    private func enterCardSpace() async {
        guard appModel.immersiveSpaceState == .closed else { return }
        
        // 遷移開始を即座に通知（updateクロージャによる角度固定を解除し、正面を向かせる）
        appModel.immersiveSpaceState = .inTransition
        
        // 裏面は見えないように即座に無効化
        backPlaneEntity?.isEnabled = false
        
        // 1. 各パーツのフェードアウト開始（不透明度を 1.0 -> 0.0）
        let fadeTargets = [framePlaneEntity, portalPlaneEntity]
        for entity in fadeTargets {
            entity?.components.set(OpacityComponent(opacity: 1.0))
        }
        
        // 2. ズームアニメーション（正面を向きつつ大きく拡大して前進）
        if let cardRoot = cardRootEntity {
            let zoomTransform = Transform(
                scale: SIMD3<Float>(repeating: 2.2), // 2.2倍に拡大
                rotation: simd_quatf(angle: 0, axis: [0, 1, 0]),
                translation: SIMD3<Float>(0, 0, 0.15) // よりユーザーの近くへ
            )
            
            cardRoot.move(
                to: zoomTransform,
                relativeTo: cardRoot.parent,
                duration: 0.6,
                timingFunction: .easeIn
            )
        }
        
        // 3. フェードアニメーションのタスク
        Task {
            let steps = 20
            let duration: Double = 0.5
            for i in 1...steps {
                let opacity = Float(steps - i) / Float(steps)
                await MainActor.run {
                    for entity in fadeTargets {
                        entity?.components.set(OpacityComponent(opacity: opacity))
                    }
                }
                try? await Task.sleep(for: .seconds(duration / Double(steps)))
            }
        }
        
        // 4. アニメーションの山場で遷移を開始
        // アニメーションの進行を待ってから遷移を開始
        try? await Task.sleep(for: .seconds(0.4))
        
        let result = await openImmersiveSpace(id: appModel.cardSpaceID)
        
        await MainActor.run {
            switch result {
            case .opened:
                // カードルート自体を無効化して、衝突判定（見えない巨大な壁）を完全に取り除く
                cardRootEntity?.isEnabled     = false
                appModel.immersiveSpaceState = .open
            case .userCancelled, .error:
                fallthrough
            @unknown default:
                appModel.immersiveSpaceState = .closed
                resetCardTransform()
            }
        }
    }
    
    // MARK: - リセット
    
    /// カードのトランスフォームと表示状態をリセット
    private func resetCardTransform() {
        guard let cardRoot = cardRootEntity else { return }
        
        // カードルートと各パーツを再活性化
        cardRoot.isEnabled = true
        let fadeTargets = [framePlaneEntity, backPlaneEntity, portalPlaneEntity]
        for entity in fadeTargets {
            entity?.isEnabled = true
            entity?.components.set(OpacityComponent(opacity: 1.0))
        }
        spatialPhotoEntity?.isEnabled = true
        
        // 回転状態をクリア
        dragRotation = .init(angle: 0, axis: [0, 1, 0])
        baseRotation = .init(angle: 0, axis: [0, 1, 0])
        
        // ウィンドウの座標系（parent）に対してホームポジションへリセット
        let homeTransform = Transform(
            scale: .one,
            rotation: .init(angle: 0, axis: [0, 1, 0]),
            translation: [0, 0.05, 0]
        )
        
        cardRoot.move(
            to: homeTransform,
            relativeTo: cardRoot.parent,
            duration: 0.5,
            timingFunction: .easeOut
        )
    }
}

#Preview(windowStyle: .volumetric) {
    ContentView()
        .environment(AppModel())
}
