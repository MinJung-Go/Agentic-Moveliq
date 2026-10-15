import AVFoundation
import Combine
import PhotosUI
import SwiftUI
import UIKit

/// 首页、教练与记一笔共用。这里只管理输入，不调用模型或持久化记录。
struct MessageComposer: View {
    enum Accessory {
        case photo
        case realtime(() -> Void)
    }

    @Binding var text: String
    @Binding var photo: Data?
    @ObservedObject var dictation: VoiceInput
    var focus: FocusState<Bool>.Binding
    let placeholder: String
    var accessory: Accessory = .photo
    var isBusy = false
    var onStop: (() -> Void)? = nil
    let identifier: String
    var background: Color = Theme.conversationCanvas
    var onSend: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var photoItem: PhotosPickerItem?
    @State private var photoError: String?

    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || photo != nil
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if !dictation.notice.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    Text(dictation.notice)
                        .font(Theme.Font.caption)
                        .foregroundStyle(dictation.hasError ? Theme.danger : Theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if dictation.active {
                        Button("取消") { dictation.finish(cancel: true) }
                            .buttonStyle(PlainActionButtonStyle(font: Theme.Font.caption))
                    }
                }
                .accessibilityIdentifier("\(identifier).voiceNotice")
            }
            if let photoError {
                Text(photoError)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let photo, let image = UIImage(data: photo) {
                attachment(image)
            }
            if focus.wrappedValue {
                HStack {
                    Spacer(minLength: 0)
                    Button("收起键盘", systemImage: "keyboard.chevron.compact.down") {
                        focus.wrappedValue = false
                    }
                    .buttonStyle(PlainActionButtonStyle(font: Theme.Font.caption))
                    .accessibilityHint("保留文字和已附加照片")
                    .accessibilityIdentifier("\(identifier).dismissKeyboard")
                }
            }
            field
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .background(background)
        .task(id: photoItem) { await loadPhoto() }
        // 同步接收转写，避免异步 onChange 在发送清空后又把旧转写写回草稿。
        .onReceive(dictation.$text.dropFirst()) { text = $0 }
        .onDisappear { dictation.finish() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { dictation.finish() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
            if let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
               type == AVAudioSession.InterruptionType.began.rawValue { dictation.finish() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
            if let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { dictation.finish() }
        }
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: 0) {
            accessoryButton
            TextField(placeholder, text: $text, axis: .vertical)
                .font(Theme.Font.body)
                .lineLimit(1...4)
                .focused(focus)
                .disabled(dictation.active)
                .frame(minHeight: 44)
                .accessibilityLabel(placeholder)
                .accessibilityIdentifier("\(identifier).draft")

            if isBusy {
                if let onStop {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondaryLabel)
                    .accessibilityLabel("停止生成")
                } else {
                    ProgressView()
                        .tint(Theme.secondaryLabel)
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("正在处理")
                }
            } else {
                voiceButton
                if hasContent {
                    Button(action: submit) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.onAccent)
                            .frame(width: 36, height: 36)
                            .background(Theme.accent, in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(photoItem != nil)
                    .accessibilityLabel("发送")
                    .accessibilityIdentifier("\(identifier).send")
                }
            }
        }
        .padding(Theme.Spacing.xs)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    @ViewBuilder
    private var accessoryButton: some View {
        switch accessory {
        case .photo:
            PhotosPicker(selection: $photoItem, matching: .images) {
                Group {
                    if photoItem != nil { ProgressView().tint(Theme.secondaryLabel) }
                    else { Image(systemName: "plus").font(.system(size: 20)) }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .disabled(isBusy || dictation.active || photoItem != nil)
            .accessibilityLabel("添加照片")
        case .realtime(let open):
            Menu {
                Button("实时通话（可选视频）", systemImage: "phone.fill") {
                    focus.wrappedValue = false
                    open()
                }
                .accessibilityIdentifier("\(identifier).realtimeCall")
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(Theme.accent)
            .disabled(isBusy || dictation.active)
            .accessibilityLabel("更多操作")
        }
    }

    private var voiceButton: some View {
        Button {
            focus.wrappedValue = false
            if dictation.active { dictation.finish() }
            else { dictation.begin(draft: text) }
        } label: {
            Image(systemName: dictation.active ? "stop.circle.fill" : "mic")
                .font(.system(size: 19))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(dictation.active ? Theme.danger : Theme.secondaryLabel)
        .disabled(photoItem != nil)
        .accessibilityLabel(dictation.active ? "停止语音输入" : "开始语音输入")
        .accessibilityHint("只转成文字，确认后手动发送")
        .accessibilityIdentifier("\(identifier).voiceInput")
    }

    private func attachment(_ image: UIImage) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(uiImage: image)
                .resizable().scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.inner))
                .accessibilityLabel("已附加照片")
            VStack(alignment: .leading, spacing: 2) {
                Text("照片已附加")
                Text("可补充说明后一起发送").foregroundStyle(Theme.secondaryLabel)
            }
            .font(Theme.Font.caption)
            Spacer(minLength: 0)
            Button("移除") { photo = nil }
                .buttonStyle(PlainActionButtonStyle(font: Theme.Font.caption, tint: Theme.secondaryLabel))
                .disabled(isBusy)
        }
    }

    private func submit() {
        guard !isBusy, photoItem == nil, hasContent else { return }
        if dictation.active { text = dictation.finishForSend() }
        dictation.clearNotice()
        focus.wrappedValue = false
        onSend()
    }

    private func loadPhoto() async {
        guard let selection = photoItem else { return }
        photoError = nil
        do {
            let data = try await selection.loadTransferable(type: Data.self)
            try Task.checkCancellation()
            guard let data, !data.isEmpty, UIImage(data: data) != nil else {
                photoError = "无法读取这张照片，请换一张。原草稿已保留。"
                photoItem = nil
                return
            }
            photo = data
            photoItem = nil
        } catch {
            guard !Task.isCancelled else { return }
            photoError = "读取照片失败，请重试。原草稿已保留。"
            photoItem = nil
        }
    }
}
