import SwiftUI
import PhotosUI

struct HomeMenuView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        @Bindable var appModel = appModel  // プロパティ書き換えのためにバインダブルに
        ZStack {
            if appModel.phase == .title {
                titlePhase
            } else if appModel.phase == .photoSelection {
                photoSelectionPhase
            } else if appModel.phase == .paint {
                paintPhase
            } else if appModel.phase == .cardPlay {
                // カード遊び中はこのウィンドウには何も表示しない
                // （これにより、dismiss 命令が確実に実行され、ウィンドウが消去される）
                EmptyView()
            } else {
                // 初期状態や不明なフェーズの場合のみタイトルを表示
                titlePhase
            }
        }
        .frame(width: 800, height: 600)
        .onAppear {
            // 起動時に Phase 4 のウィンドウが残っていたら強制的に閉じる
            if appModel.phase != .cardPlay {
                dismissWindow(id: "CardWindow")
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            Task {
                await appModel.updatePhoto(from: newItem)
            }
        }
    }

    // Sec1: タイトル
    private var titlePhase: some View {
        VStack(spacing: 40) {
            Spacer()
            VStack(spacing: 16) {
                Text("Immersive Card")
                    .font(.system(size: 88, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 20)
                Text("思い出を、触れられる3Dの世界へ")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                appModel.phase = .photoSelection
            } label: {
                Text("はじめる").font(.title2).fontWeight(.bold).frame(width: 240).padding()
            }
            .buttonStyle(.borderedProminent)
            .glassBackgroundEffect()
            Spacer().frame(height: 100)
        }
    }

    // Sec2: 写真を選択
    private var photoSelectionPhase: some View {
        VStack(spacing: 50) {
            Text("Step 1: 写真を選択").font(.system(size: 48, weight: .bold))
            
            ZStack {
                if appModel.selectedMediaType == .video {
                    // 動画選択時: サムネイル代わりのアイコンを表示
                    RoundedRectangle(cornerRadius: 32)
                        .fill(.ultraThinMaterial)
                        .frame(width: 440, height: 320)
                        .overlay {
                            VStack(spacing: 16) {
                                Image(systemName: "film.fill")
                                    .font(.system(size: 60))
                                    .foregroundStyle(.cyan)
                                Text("動画が選択されました")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                } else if let url = appModel.selectedPhotoURL,
                   let data = try? Data(contentsOf: url),
                   let uiImage = UIImage(data: data) {
                    // 静止画選択時: プレビューを表示
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 440, height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 32))
                        .shadow(radius: 30)
                } else {
                    // 未選択時: プレースホルダー
                    RoundedRectangle(cornerRadius: 32)
                        .fill(.ultraThinMaterial)
                        .frame(width: 440, height: 320)
                        .overlay(Image(systemName: "photo.stack").font(.system(size: 60)).foregroundStyle(.secondary))
                }
            }
            
            HStack(spacing: 24) {
                // 画像のみでなく動画も選択できるようにフィルタを安す
                PhotosPicker(selection: $selectedItem, matching: .any(of: [.images, .videos]), photoLibrary: .shared()) {
                    Label("ライブラリから選ぶ", systemImage: "photo.on.rectangle.angled").font(.headline).padding()
                }
                .buttonStyle(.bordered)
                
                if appModel.selectedPhotoURL != nil || appModel.selectedVideoURL != nil {
                    Button {
                        appModel.phase = .paint
                    } label: {
                        Text("次へ進む").font(.headline).fontWeight(.bold).padding(.horizontal, 40)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    // Sec3: ペイントデコレーション
    private var paintPhase: some View {
        VStack(spacing: 50) {
            Text("Step 2: ペイントデコレーション").font(.system(size: 48, weight: .bold))
            
            ZStack {
                RoundedRectangle(cornerRadius: 40).fill(.ultraThinMaterial).frame(width: 600, height: 300)
                VStack(spacing: 20) {
                    Image(systemName: "paintbrush.pointed.fill").font(.system(size: 60)).foregroundStyle(.purple)
                    Text("Coming Soon").font(.title).fontWeight(.black)
                    Text("今後のアップデートで追加予定です。").font(.headline).foregroundStyle(.secondary)
                }
            }
            
            Button {
                appModel.phase = .cardPlay
                openWindow(id: "CardWindow")
                // 自分自身を確実に閉じる
                dismiss()
            } label: {
                Text("カードを完成させて遊ぶ").font(.title3).fontWeight(.bold).frame(width: 350).padding()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
