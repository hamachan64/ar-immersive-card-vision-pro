import SwiftUI
import RealityKit
import RealityKitContent
import PhotosUI
import AVFoundation

// MARK: - カードの基本サイズ定数
private let kCardWidth:  Float = 0.3
private let kCardHeight: Float = 0.4

// MARK: - ECS: ドラッグ回転用
public struct RotationComponent: Component {
    public var speed: Float
    public var axis: SIMD3<Float>
    public init(speed: Float = 1.0, axis: SIMD3<Float> = [0, 1, 0]) {
        self.speed = speed
        self.axis = axis
    }
}

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

// MARK: - Sec 4: カード遊びシーン
struct CardPlayView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismiss) private var dismiss

    @State private var dragRotation: simd_quatf = .init(angle: 0, axis: [0, 1, 0])
    @State private var baseRotation: simd_quatf = .init(angle: 0, axis: [0, 1, 0])

    @State private var cardRootEntity:    Entity?
    @State private var spatialPhotoEntity: Entity?
    @State private var framePlaneEntity:  ModelEntity?
    @State private var backPlaneEntity:   ModelEntity?
    @State private var portalPlaneEntity: ModelEntity?
    /// 動画再生用エンティティ（動画選択時に生成）
    @State private var videoEntity:       Entity?

    init() {
        RotationComponent.registerComponent()
        RotationSystem.registerSystem()
    }

    var body: some View {
        @Bindable var appModel = appModel
        
        // --- 起動時の残存ウィンドウ防止ガード ---
        if appModel.phase != .cardPlay {
            Color.clear
                .onAppear {
                    openWindow(id: "MenuWindow")
                    dismissWindow(id: "CardWindow")
                    print("[CardPlayView] ガード処理により MenuWindow を開き、自分自身を消去しました")
                }
        } else {
            // 本来の表示内容 (Phase 4)
            VStack {
                RealityView { content in
                    let cardCornerRadius: Float = 0.03
                    let cardDepth: Float = 0.002
                    
                    let cardRoot = Entity()
                    cardRoot.name = "CardFrame"
                    cardRoot.components.set(InputTargetComponent())
                    cardRoot.components.set(CollisionComponent(shapes: [.generateBox(size: [kCardWidth, kCardHeight, cardDepth])]))
                    
                    let worldEntity = Entity()
                    worldEntity.components.set(WorldComponent())
                    
                    let photoEntity = Entity()
                    photoEntity.name = "SpatialPhoto"
                    photoEntity.position = [0, 0, 0]
                    
                    // --- メディア種別によって表示内容を切り替える ---
                    if appModel.selectedMediaType == .video, let player = appModel.videoPlayer {
                        let videoMaterial = VideoMaterial(avPlayer: player)
                        let videoHeight: Float = kCardHeight
                        let videoWidth:  Float = min(videoHeight * appModel.videoAspectRatio, kCardWidth)

                        let videoPlane = ModelEntity(
                            mesh: .generatePlane(width: videoWidth, height: videoHeight, cornerRadius: 0.015),
                            materials: [videoMaterial]
                        )
                        videoPlane.position = [0, 0, 0.002]
                        cardRoot.addChild(videoPlane)
                        await MainActor.run { self.videoEntity = videoPlane }
                    } else {
                        let targetURL = appModel.selectedPhotoURL ?? Bundle.main.url(forResource: "Picture2", withExtension: "HEIC")
                        if let url = targetURL, var imageComp = try? await ImagePresentationComponent(contentsOf: url) {
                            imageComp.desiredViewingMode = .spatialStereo
                            imageComp.screenHeight = kCardHeight
                            await MainActor.run { photoEntity.components.set(imageComp) }
                        } else {
                            let fallbackModel = ModelEntity(mesh: .generateBox(size: [kCardHeight * (4.0/3.0), kCardHeight, 0.0001], cornerRadius: cardCornerRadius))
                            await MainActor.run { photoEntity.addChild(fallbackModel) }
                        }
                        worldEntity.addChild(photoEntity)
                        cardRoot.addChild(worldEntity)
                    }
                    
                    let portalPlane = ModelEntity(mesh: .generateBox(size: [kCardWidth, kCardHeight, 0.0001], cornerRadius: cardCornerRadius), materials: [PortalMaterial()])
                    portalPlane.components.set(PortalComponent(target: worldEntity))
                    cardRoot.addChild(portalPlane)
                    
                    let framePlane = ModelEntity(mesh: .generateBox(size: [kCardWidth, kCardHeight, 0.001], cornerRadius: cardCornerRadius), materials: [SimpleMaterial(color: .white, isMetallic: false)])
                    framePlane.position = [0, 0, 0.002]
                    Task {
                        if let texture = try? await TextureResource(named: "Frame") {
                            var mat = UnlitMaterial()
                            mat.blending = .transparent(opacity: .init(scale: 1.0)); mat.color = .init(texture: .init(texture))
                            await MainActor.run { framePlane.model?.materials = [mat] }
                        }
                    }
                    cardRoot.addChild(framePlane)
                    
                    let backPlane = ModelEntity(mesh: .generateBox(size: [kCardWidth, kCardHeight, 0.001], cornerRadius: cardCornerRadius), materials: [SimpleMaterial(color: .white, isMetallic: false)])
                    backPlane.position = [0, 0, -0.001]; backPlane.transform.rotation = simd_quatf(angle: .pi, axis: [0, 1, 0])
                    Task {
                        if let texture = try? await TextureResource(named: "Back") {
                            var mat = UnlitMaterial()
                            mat.color = .init(texture: .init(texture))
                            await MainActor.run { backPlane.model?.materials = [mat] }
                        }
                    }
                    cardRoot.addChild(backPlane)
                    
                    content.add(cardRoot)
                    self.cardRootEntity = cardRoot; self.spatialPhotoEntity = photoEntity; self.framePlaneEntity = framePlane; self.backPlaneEntity = backPlane; self.portalPlaneEntity = portalPlane
                } update: { content in
                    guard appModel.displayMode == .windowed, appModel.immersiveSpaceState == .closed else { return }
                    if let cardFrame = content.entities.first(where: { $0.name == "CardFrame" }) {
                        cardFrame.transform.rotation = dragRotation * baseRotation
                    }
                }
                .gesture(DragGesture().targetedToAnyEntity().onChanged { value in
                    guard appModel.displayMode == .windowed, appModel.immersiveSpaceState == .closed else { return }
                    let h = simd_quatf(angle: Float(value.translation.width) * 0.01, axis: [0, 1, 0])
                    let v = simd_quatf(angle: Float(value.translation.height) * 0.01, axis: [1, 0, 0])
                    dragRotation = h * v
                }.onEnded { _ in
                    guard appModel.displayMode == .windowed, appModel.immersiveSpaceState == .closed else { return }
                    baseRotation = dragRotation * baseRotation; dragRotation = .init(angle: 0, axis: [0, 1, 0])
                })
            }
            .onAppear {
                // カード表示が始まったら、メインメニューウィンドウを確実に閉じる
                dismissWindow(id: "MenuWindow")
                
                if appModel.selectedMediaType == .video {
                    appModel.videoPlayer?.play()
                }
            }
            .onDisappear {
                // ウィンドウが閉じる際や遷移時に動画を停止する
                if appModel.selectedMediaType == .video {
                    appModel.videoPlayer?.pause()
                }
            }
            .ornament(attachmentAnchor: .scene(.bottom)) {
                HStack(spacing: 20) {
                    Button {
                        appModel.phase = .title
                        openWindow(id: "MenuWindow")
                        // 自分のウィンドウを確実に閉じる
                        dismiss()
                    } label: { Image(systemName: "house.fill").padding() }
                    .disabled(appModel.immersiveSpaceState != .closed)
                    
                    Button { resetCardTransform() } label: { Image(systemName: "arrow.counterclockwise").padding() }
                    .disabled(appModel.immersiveSpaceState != .closed)

                    Button {
                        Task { @MainActor in
                            if appModel.immersiveSpaceState == .closed { await enterCardSpace() }
                            else if appModel.immersiveSpaceState == .open { 
                                appModel.immersiveSpaceState = .inTransition
                                await dismissImmersiveSpace()
                                appModel.immersiveSpaceState = .closed
                                resetCardTransform()
                            }
                        }
                    } label: {
                        if appModel.immersiveSpaceState == .open { Label("現実に戻る", systemImage: "arrow.uturn.backward.circle.fill") }
                        else { Label("空間に入る", systemImage: "sparkles") }
                    }
                    .disabled(appModel.immersiveSpaceState == .inTransition)
                    .padding(.horizontal, 10)
                }
                .padding().glassBackgroundEffect()
            }
        }
    }

    private func enterCardSpace() async {
        guard appModel.immersiveSpaceState == .closed else { return }
        appModel.immersiveSpaceState = .inTransition; backPlaneEntity?.isEnabled = false
        let fadeTargets = [framePlaneEntity, portalPlaneEntity]
        for entity in fadeTargets { entity?.components.set(OpacityComponent(opacity: 1.0)) }
        if let cardRoot = cardRootEntity {
            let zoomTransform = Transform(scale: SIMD3<Float>(repeating: 2.2), rotation: simd_quatf(angle: 0, axis: [0, 1, 0]), translation: SIMD3<Float>(0, 0, 0.15))
            cardRoot.move(to: zoomTransform, relativeTo: cardRoot.parent, duration: 0.6, timingFunction: .easeIn)
        }
        Task {
            let steps = 20; let duration: Double = 0.5
            for i in 1...steps {
                let opacity = Float(steps - i) / Float(steps)
                await MainActor.run { for entity in fadeTargets { entity?.components.set(OpacityComponent(opacity: opacity)) } }
                try? await Task.sleep(for: .seconds(duration / Double(steps)))
            }
        }
        try? await Task.sleep(for: .seconds(0.4))
        let result = await openImmersiveSpace(id: appModel.cardSpaceID)
        await MainActor.run {
            switch result {
            case .opened: cardRootEntity?.isEnabled = false; appModel.immersiveSpaceState = .open
            case .userCancelled, .error: fallthrough
            @unknown default: appModel.immersiveSpaceState = .closed; resetCardTransform()
            }
        }
    }

    private func resetCardTransform() {
        guard let cardRoot = cardRootEntity else { return }
        cardRoot.isEnabled = true
        let fadeTargets = [framePlaneEntity, backPlaneEntity, portalPlaneEntity]
        for entity in fadeTargets { entity?.isEnabled = true; entity?.components.set(OpacityComponent(opacity: 1.0)) }
        spatialPhotoEntity?.isEnabled = true; dragRotation = .init(angle: 0, axis: [0, 1, 0]); baseRotation = .init(angle: 0, axis: [0, 1, 0])
        let homeTransform = Transform(scale: .one, rotation: .init(angle: 0, axis: [0, 1, 0]), translation: [0, 0.05, 0])
        cardRoot.move(to: homeTransform, relativeTo: cardRoot.parent, duration: 0.5, timingFunction: .easeOut)
    }
}

#Preview(windowStyle: .volumetric) {
    CardPlayView()
        .environment(AppModel())
}
