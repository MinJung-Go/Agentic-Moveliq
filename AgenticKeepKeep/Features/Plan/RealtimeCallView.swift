import SwiftUI
import UIKit

struct RealtimeCallView: View {
    @ObservedObject var call: RealtimeCall
    let name: String
    let onEnd: () -> Void
    let onReview: (String) -> Void
    @State private var confirmsCamera = false
    private var title: String {
        switch call.phase {
        case .consent: return "和 \(name) 实时聊聊"
        case .connecting: return "正在连接…"
        case .listening: return call.muted ? "麦克风已静音" : "我在听，慢慢说"
        case .speaking: return "\(name) 正在说"
        case .paused: return "通话已暂停"
        case .failed: return "连接暂时中断"
        case .review: return "先看看这份课程"
        case .ended: return "通话已结束"
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(name).font(.headline)
                    Text(call.cameraOn ? "实时通话 · 视频" : "实时通话 · 仅语音")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(call.subtitles ? "字幕 开" : "字幕 关") { call.subtitles.toggle() }
                    .buttonStyle(.bordered).clipShape(Capsule())
            }.padding(22)
            ScrollView {
                VStack(spacing: 20) {
                    if call.cameraOn {
                        ZStack(alignment: .top) {
                            Group {
                                if let image = call.preview { Image(uiImage: image).resizable().scaledToFill() }
                                else { Color.black.opacity(0.7).overlay { ProgressView().tint(.white) } }
                            }.frame(height: 280).clipped()
                            HStack {
                                Text(call.muted ? "画面仍在共享 · 麦克风静音" : "正在共享画面")
                                    .font(.caption2).padding(9).background(.black.opacity(0.65), in: Capsule())
                                Spacer()
                                Button { call.flipCamera() } label: { Image(systemName: "arrow.triangle.2.circlepath.camera").frame(width: 44, height: 44) }
                                    .background(.black.opacity(0.65), in: Circle()).disabled(call.switching)
                                    .accessibilityLabel("切换前后镜头")
                            }.foregroundStyle(.white).padding(12)
                        }.clipShape(RoundedRectangle(cornerRadius: 24))
                    } else {
                        MiloAvatar(size: 156).padding(24).background(.blue.opacity(0.07), in: Circle()).padding(.top, 28)
                        Text("摄像头未开启").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(title).font(.title2.bold())
                    if call.active && !call.muted { Text("直接开口即可打断回复").font(.caption).foregroundStyle(.secondary) }
                    if call.switching { ProgressView("正在切换，暂时停止发送音频…") }
                    if call.phase == .consent {
                        Text("音频将发送给云端模型处理，首次需要麦克风权限。摄像头默认关闭，只有你主动开启后才共享画面。App 不保存原始音视频，转写和回复保留在聊天中。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("同意并开始语音") { call.connect() }.buttonStyle(PrimaryButtonStyle())
                    } else if call.phase == .connecting { ProgressView() }
                    if call.subtitles, call.active {
                        if !call.transcript.isEmpty { Text("你：" + call.transcript).font(.subheadline).foregroundStyle(.secondary) }
                        if !call.reply.isEmpty { Text(call.reply).font(.title3).textSelection(.enabled) }
                    }
                    if !call.notice.isEmpty { Text(call.notice).font(.subheadline).foregroundStyle(.secondary) }
                    if call.phase == .paused || call.phase == .failed {
                        Button("重新连接语音") { call.connect() }.buttonStyle(.borderedProminent)
                        Button("系统权限设置") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                    if call.phase == .review {
                        Text(call.planRequest).font(.subheadline)
                        Button("查看课程建议") { onReview(call.planRequest) }.buttonStyle(PrimaryButtonStyle())
                    }
                }.frame(maxWidth: .infinity).padding(.horizontal, 22).padding(.bottom, 20)
            }.multilineTextAlignment(.center)
            HStack(spacing: 0) {
                control(call.muted ? "取消静音" : "静音", icon: call.muted ? "mic.slash.fill" : "mic.fill", disabled: !call.active || call.switching) { call.toggleMute() }
                control(call.cameraOn ? "关摄像头" : "开摄像头", icon: call.cameraOn ? "video.fill" : "video.slash", disabled: !call.active || call.switching) {
                    if call.cameraOn { call.disableCamera() } else { confirmsCamera = true }
                }
                control("挂断", icon: "xmark", tint: .red, disabled: false, action: onEnd)
            }.padding(.horizontal, 14).padding(.vertical, 24)
        }
        .background(Theme.conversationCanvas.ignoresSafeArea())
        .confirmationDialog("让 \(name) 看看画面？", isPresented: $confirmsCamera, titleVisibility: .visible) {
            Button("开启摄像头") { Task { await call.enableCamera() } }
            Button("暂不开启", role: .cancel) {}
        } message: { Text("开启后，摄像头画面会发送给云端模型理解。关闭后仍可继续语音聊天。") }
    }
    private func control(_ label: String, icon: String, tint: Color = Theme.secondaryLabel, disabled: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 9) {
            Button(action: action) {
                Image(systemName: icon).font(.title3).frame(width: 56, height: 56)
                    .foregroundStyle(tint).background(tint.opacity(0.1), in: Circle())
            }.disabled(disabled).accessibilityLabel(label)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).opacity(disabled ? 0.4 : 1)
    }
}
