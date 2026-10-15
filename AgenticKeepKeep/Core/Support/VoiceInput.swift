import Combine
import Foundation

/// Dictation only: never submits a message or speaks a reply.
@MainActor
final class VoiceInput: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var text = ""
    @Published private(set) var notice = ""
    private let recognizer: VoiceRecognizing
    private var original = ""
    private var generation = UUID()
    private var startTask: Task<Void, Never>?

    init(recognizer: VoiceRecognizing) { self.recognizer = recognizer }
    convenience init() { self.init(recognizer: SpeechRecognizer()) }

    func begin(draft: String) {
        guard !active else { return }
        original = draft; text = draft; notice = "正在准备语音输入…"; active = true
        let token = UUID(); generation = token
        recognizer.onUpdate = { [weak self] value, final in
            guard let self, self.active, self.generation == token else { return }
            let spoken = value.trimmingCharacters(in: .whitespacesAndNewlines)
            self.text = self.original + (self.original.isEmpty || spoken.isEmpty ? "" : "\n") + spoken
            self.notice = "正在听…完成后可编辑，再手动发送。"
            if final { self.finish() }
        }
        recognizer.onFailure = { [weak self] message in
            guard let self, self.generation == token else { return }
            self.finish(); self.notice = message
        }
        startTask = Task { [weak self] in
            guard let self, self.active, self.generation == token, !Task.isCancelled else { return }
            await self.recognizer.start()
            guard self.active, self.generation == token else { return }
            self.notice = "正在听…完成后可编辑，再手动发送。"
        }
    }
    /// 发送时取走当前转写并结束这次收音：不必先手动停一次，也不会丢掉已识别的文字
    func finishForSend() -> String {
        let value = text
        finish()
        notice = ""
        return value
    }
    func finish(cancel: Bool = false) {
        guard active else { return }
        generation = UUID(); startTask?.cancel(); startTask = nil
        recognizer.onUpdate = nil; recognizer.onFailure = nil; recognizer.stop()
        active = false
        if cancel { text = original; notice = "已取消，原草稿已恢复。" }
        else { notice = "语音输入已停止，可编辑后发送。" }
    }
}
