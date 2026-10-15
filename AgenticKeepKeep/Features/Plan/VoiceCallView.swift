import SwiftUI
import UIKit

struct VoiceCallView: View {
    @ObservedObject var voice: VoiceConversation
    let name: String
    let onEnd: () -> Void
    let onReview: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    private var title: String {
        switch voice.phase {
        case .consent: return "开始前，了解一下"
        case .listening: return "我在听，慢慢说"
        case .thinking: return "让我想一想"
        case .speaking: return "\(name) 正在说"
        case .muted: return "麦克风已关闭"
        case .paused: return "语音已暂停"
        case .failed: return "暂时无法继续"
        case .review: return "先看看这份课程"
        case .ended: return "通话已结束"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.headline)
                    Text("语音对话").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(voice.showsSubtitles ? "字幕 开" : "字幕 关") { voice.showsSubtitles.toggle() }
                    .font(.subheadline).buttonStyle(.bordered).clipShape(Capsule())
                    .accessibilityLabel(voice.showsSubtitles ? "关闭字幕" : "显示字幕")
            }.padding(24)
            ScrollView {
                VStack(spacing: 18) {
                    MiloAvatar(size: 156)
                        .padding(24)
                        .background(Circle().fill(Color.blue.opacity(0.07)))
                        .scaleEffect(breathing && !reduceMotion && [.listening, .speaking].contains(voice.phase) ? 1.04 : 1)
                        .padding(.top, 28)
                    Text(voice.isMuted ? "麦克风关闭" : "连续语音")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(title).font(.title2.bold())
                    if voice.phase == .listening {
                        Text("说完后会自动发送，无需点击。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Image(systemName: "waveform").font(.title).foregroundStyle(.blue)
                    }
                    if voice.phase == .thinking { ProgressView().accessibilityLabel("正在准备回复") }
                    if voice.showsSubtitles, [.listening, .thinking, .speaking].contains(voice.phase) {
                        Text(voice.phase == .speaking ? voice.reply : voice.transcript)
                            .font(.title3).textSelection(.enabled)
                    }
                    if voice.phase == .consent {
                        Text("开始后，说完一句会自动发送。需要麦克风和语音识别权限。原音频不保存；优先设备端识别，不支持时可能使用 Apple 服务。转写文本经现有云端服务处理并保存在聊天中。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("同意并开始") { voice.begin() }.buttonStyle(PrimaryButtonStyle())
                    }
                    if voice.phase == .failed, !voice.transcript.isEmpty {
                        Text(voice.transcript).textSelection(.enabled)
                    }
                    if !voice.notice.isEmpty { Text(voice.notice).font(.subheadline).foregroundStyle(.secondary) }
                    if voice.canRetry, voice.phase == .failed {
                        Button("重试这句话") { voice.retry() }.buttonStyle(.borderedProminent)
                    }
                    if voice.phase == .paused || voice.phase == .failed {
                        Button("继续收音") { voice.begin() }.buttonStyle(.borderedProminent)
                        if voice.phase == .failed {
                            Button("打开系统设置") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }
                        }
                    }
                    if voice.phase == .review {
                        Button("查看课程建议") { onReview() }.buttonStyle(PrimaryButtonStyle())
                    }
                }.padding(.horizontal, 28).padding(.bottom, 20)
                    .frame(maxWidth: .infinity)
            }.multilineTextAlignment(.center)
            HStack(spacing: 30) {
                control(voice.isMuted ? "取消静音" : "静音", icon: voice.isMuted ? "mic.slash.fill" : "mic.fill", tint: Theme.secondaryLabel,
                        disabled: ![.listening, .thinking, .speaking, .muted].contains(voice.phase)) { voice.toggleMute() }
                control("点击打断", icon: "stop.fill", tint: Theme.secondaryLabel,
                        disabled: ![.thinking, .speaking].contains(voice.phase)) { voice.interrupt() }
                control("挂断", icon: "xmark", tint: .red) { onEnd() }
            }.padding(.vertical, 24)
        }
        .background(Theme.conversationCanvas.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { breathing = true }
        }
    }

    private func control(_ label: String, icon: String, tint: Color, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Button(action: action) {
                Image(systemName: icon).font(.title3)
                    .frame(width: 60, height: 60)
                    .foregroundStyle(tint)
                    .background(tint.opacity(0.1), in: Circle())
            }.disabled(disabled).accessibilityLabel(label)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.opacity(disabled ? 0.35 : 1)
    }
}
