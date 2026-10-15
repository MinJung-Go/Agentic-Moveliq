import AVFoundation
import Foundation
import Combine
import Speech

/// 语音输入：把说话内容转写成文字，填进记录输入框。
/// 优先设备端识别；不可用时由 Apple 系统服务处理。原音频不上传到 App 代理。
@MainActor
final class SpeechRecognizer: ObservableObject, VoiceRecognizing {

    @Published private(set) var isRecording = false
    @Published var transcript = ""
    @Published var errorText: String?

    var onUpdate: ((String, Bool) -> Void)?
    var onFailure: ((String) -> Void)?
    private var generation = UUID()
    private var isStarting = false
    private var tapInstalled = false
    private let locale: Locale
    private var recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    init(locale: Locale = Locale(identifier: "zh-CN")) {
        self.locale = locale
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    var isAvailable: Bool {
        recognizer?.isAvailable ?? false
    }

    func toggle() {
        if isRecording {
            stop()
        } else {
            Task { await start() }
        }
    }

    func start() async {
        guard !isRecording, !isStarting else { return }
        isStarting = true
        let token = UUID()
        generation = token
        defer { if generation == token { isStarting = false } }
        errorText = nil
        transcript = ""

        guard let recognizer, recognizer.isAvailable else {
            fail("当前设备无法使用语音识别")
            return
        }

        let speechStatus = await requestSpeechAuthorization()
        guard generation == token, !Task.isCancelled else { return }
        guard speechStatus == .authorized else {
            fail("未授权语音识别，请在系统设置中开启")
            return
        }

        let micGranted = await requestMicrophonePermission()
        guard generation == token, !Task.isCancelled else { return }
        guard micGranted else {
            fail("未授权麦克风，请在系统设置中开启")
            return
        }

        begin(with: recognizer, token: token)
    }

    func stop() {
        generation = UUID()
        isStarting = false
        audioEngine?.stop()
        if tapInstalled, let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
        }
        tapInstalled = false
        request?.endAudio()
        task?.cancel()

        audioEngine = nil
        request = nil
        task = nil
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 内部

    private func begin(with recognizer: SFSpeechRecognizer, token: UUID) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            self.request = request

            let engine = AVAudioEngine()
            self.audioEngine = engine

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.channelCount > 0, format.sampleRate > 0 else {
                fail("没有可用的麦克风输入")
                return
            }

            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            tapInstalled = true
            engine.prepare()
            try engine.start()

            isRecording = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        let text = self.transcript
                        if result.isFinal { self.stop() }
                        self.onUpdate?(text, result.isFinal)
                    }
                    if error != nil, self.isRecording {
                        self.fail("语音识别中断，请重试")
                    }
                }
            }
        } catch {
            fail("录音启动失败：\(error.localizedDescription)")
        }
    }

    private func fail(_ message: String) {
        stop()
        errorText = message
        onFailure?(message)
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
