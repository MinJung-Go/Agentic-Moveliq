import SwiftUI

struct LocalModelView: View {
    @ObservedObject private var store = LocalModelStore.shared
    @ObservedObject private var settings = LLMSettings.shared
    @State private var cellular = false
    @State private var confirmsCellular = false
    @State private var confirmsRemoval = false
    var body: some View {
        Form {
            Group {
            Section {
                HStack(spacing: 12) {
                    MiloAvatar(size: 42)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Milo").font(.headline)
                        Text(store.phase == .ready ? "已下载 · 可使用" : "下载后可在本机处理文字与照片")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
                LocalDownloadStatus()
                if store.phase == .ready {
                    Toggle("使用离线模式", isOn: $settings.useLocalModel)
                } else if !store.busy {
                    Button("下载 · \(LocalModelManifest.sizeLabel)") { store.download(cellular: cellular) }
                }
            } footer: {
                Text("聊天和照片在这台 iPhone 上处理。网页搜索仍需联网；模型不可用时不会自动切换到云端。")
            }
            Section {
                LabeledContent("下载大小", value: LocalModelManifest.sizeLabel)
                Toggle("允许蜂窝网络下载", isOn: Binding(get: { cellular }, set: { if $0 { confirmsCellular = true } else { cellular = false } }))
                DisclosureGroup("模型信息") {
                    Text("Qwen3.5-0.8B · MLX 4bit 图文模型\n下载来源：ModelScope\nApache 2.0 · mlx-community 量化\n\(LocalMLXPolicy.contextLabel) 上下文 · 单张图片\n版本 \(LocalModelManifest.revision.prefix(12))")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("模型来源与许可", destination: URL(string: "https://modelscope.cn/models/mlx-community/Qwen3.5-0.8B-4bit")!)
                }
                if store.phase != .absent {
                    Button("删除离线模型", role: .destructive) { confirmsRemoval = true }.disabled(store.isRemoving)
                }
            }
            Section {
                if settings.useLocalModel {
                    Button("使用已配置的云端 AI") { settings.useLocalModel = false }
                }
            } footer: { Text("离线功能为验证版，请核对生成的记录与建议。切换由你决定，不会因模型错误自动上传内容。") }

            }.listRowBackground(Theme.card)
        }.themedListSurface()
        .navigationTitle("离线模式").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("使用蜂窝网络下载？", isPresented: $confirmsCellular, titleVisibility: .visible) {
            Button("允许使用蜂窝网络") { cellular = true }
        } message: { Text("需要下载 \(LocalModelManifest.sizeLabel)，可能产生流量费用。") }
        .confirmationDialog("删除离线模型？", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("删除模型", role: .destructive) { Task { await store.remove() } }
        } message: { Text("会先停止本机推理，再删除模型。聊天记录、照片和训练数据会保留。") }
    }
}

struct LocalDownloadStatus: View {
    @ObservedObject private var store = LocalModelStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch store.phase {
            case .absent: EmptyView()
            case .downloading:
                HStack {
                    Text("正在下载 · \(Int(store.progress * 100))%")
                    Spacer()
                    Button { store.pause() } label: { Image(systemName: "pause").frame(width: 44, height: 44) }.accessibilityLabel("暂停下载")
                }
                ProgressView(value: store.progress).tint(Theme.accent)
                Text("对话和看图所需文件 · \(LocalModelManifest.sizeLabel)").font(.caption).foregroundStyle(.secondary)
            case .checking: HStack { ProgressView(); Text("正在检查模型文件…") }
            case .paused: Text("下载已暂停，可在离线模式设置中继续。")
            case .ready: Label("离线模式已就绪", systemImage: "checkmark.circle")
            case .failed(let message): Text(message).foregroundStyle(.secondary)
            }
        }.font(.subheadline)
    }
}

struct LocalModelInvitation: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = LLMSettings.shared
    var body: some View {
        VStack(spacing: 16) {
            MiloAvatar(size: 84)
            Text("没网，也能和 Milo 聊聊").font(.title2.weight(.semibold))
            Text("下载后，可在这台 iPhone 上聊天、\n整理图文记录。")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("\(LocalModelManifest.sizeLabel) · 建议使用 Wi-Fi").font(.footnote).foregroundStyle(.secondary)
            Button("下载并开启") {
                settings.useLocalModel = true
                LocalModelStore.shared.download(cellular: false)
                dismiss()
            }.buttonStyle(PrimaryButtonStyle())
            Button("暂不开启") { dismiss() }.frame(minHeight: 44)
            Text("聊天与看图在本机处理，网页搜索仍需联网。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).presentationDetents([.height(440), .large]).presentationDragIndicator(.visible)
    }
}
