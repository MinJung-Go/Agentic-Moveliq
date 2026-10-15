import Foundation
import Combine

/// One turn at a time: recognition → existing text proxy → system speech.
@MainActor
final class VoiceConversation: ObservableObject {
    enum Phase { case consent, listening, thinking, speaking, muted, paused, failed, review, ended }
    @Published private(set) var phase: Phase = .ended
    @Published private(set) var transcript = ""
    @Published private(set) var reply = ""
    @Published private(set) var notice = ""
    @Published private(set) var isMuted = false
    @Published private(set) var canRetry = false
    @Published var showsSubtitles = true
    var onSubmit: ((String, UUID) -> Void)?
    var onCancel: (() -> Task<Void, Never>?)?
    private var cancellation: Task<Void, Never>?
    private let recognition: VoiceRecognizing
    private let speaker: VoiceSpeaking
    private var timer: Task<Void, Never>?
    private var operation: Task<Void, Never>?
    private var generation = UUID()
    private(set) var turn: UUID?

    init(recognition: VoiceRecognizing? = nil, speaker: VoiceSpeaking? = nil) {
        self.recognition = recognition ?? SpeechRecognizer()
        self.speaker = speaker ?? SystemVoiceSpeaker()
        self.recognition.onUpdate = { [weak self] text, final in self?.heard(text, final: final) }
        self.recognition.onFailure = { [weak self] message in
            guard let self, self.phase == .listening else { return }
            self.fail(message)
        }
    }

    func open() {
        stopAudio()
        phase = .consent
        isMuted = false
        transcript = ""; reply = ""; notice = ""; canRetry = false
    }

    func begin() {
        guard [.consent, .paused, .failed, .muted, .review].contains(phase) else { return }
        isMuted = false
        listen()
    }

    private func listen() {
        stopAudio()
        guard !isMuted else { phase = .muted; return }
        phase = .listening
        transcript = ""; reply = ""; notice = ""; canRetry = false
        let token = generation
        operation = Task { [weak self] in
            guard let self else { return }
            await self.cancellation?.value
            guard self.generation == token, !Task.isCancelled else { return }
            await self.recognition.start()
            guard self.generation == token, self.phase == .listening else { return }
            self.armTimeout(seconds: self.transcript.isEmpty ? 12 : 1.5, token: token)
        }
    }

    private func heard(_ text: String, final: Bool) {
        guard phase == .listening else { return }
        transcript = text
        if final { submit() }
        else { armTimeout(seconds: 1.5, token: generation) }
    }

    private func armTimeout(seconds: Double, token: UUID) {
        timer?.cancel()
        timer = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            catch { return }
            guard let self, self.generation == token, self.phase == .listening else { return }
            self.submit()
        }
    }

    private func submit() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { fail("刚才没有听清，没有发送消息。请再试一次。"); return }
        stopAudio()
        let id = UUID()
        turn = id
        phase = .thinking
        onSubmit?(text, id)
    }

    func complete(id: UUID, text: String, needsReview: Bool, error: String?) {
        guard turn == id, phase == .thinking else { return }
        turn = nil
        if let error {
            fail(error + "\n转写仍保留在此处，已发送内容可返回聊天查看。")
            canRetry = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return
        }
        reply = text
        if needsReview {
            phase = .review
            notice = "请返回聊天查看课程建议，手动确认后才会保存。"
            return
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail("这次没有可朗读的回复，请返回聊天查看。"); return
        }
        let spoken = VoiceReplyText.spoken(text)
        guard !spoken.isEmpty else { fail("回复没有可朗读的文字，请返回聊天查看。"); return }
        do {
            let token = generation
            phase = .speaking
            try speaker.speak(spoken) { [weak self] in
                guard let self, self.generation == token, self.phase == .speaking else { return }
                self.listen()
            }
        } catch { fail("无法播放语音，请检查音频设备后重试。") }
    }

    func retry() {
        guard phase == .failed, canRetry else { return }
        canRetry = false
        submit()
    }

    func toggleMute() {
        guard [.listening, .thinking, .speaking, .muted].contains(phase) else { return }
        isMuted.toggle()
        if phase == .listening { stopAudio(); phase = .muted }
        else if phase == .muted, !isMuted { listen() }
    }

    func interrupt() {
        guard phase == .thinking || phase == .speaking else { return }
        stopAudio()
        phase = .paused
        notice = "正在停止回复…"
        cancellation = onCancel?()
        let token = generation
        operation = Task { [weak self] in
            guard let self else { return }
            await self.cancellation?.value
            guard self.generation == token, self.phase == .paused else { return }
            self.listen()
        }
    }

    func pause() {
        guard ![.ended, .consent, .paused, .review].contains(phase) else { return }
        stopAudio()
        phase = .paused
        notice = "语音已暂停，点击继续后才会恢复收音。"
        cancellation = onCancel?()
    }

    func end() {
        stopAudio()
        phase = .ended
        cancellation = onCancel?()
        onSubmit = nil; onCancel = nil
    }

    private func fail(_ message: String) {
        stopAudio()
        notice = message
        phase = .failed
    }

    private func stopAudio() {
        generation = UUID()
        turn = nil
        timer?.cancel(); timer = nil
        operation?.cancel(); operation = nil
        recognition.stop()
        speaker.stop()
    }
}
