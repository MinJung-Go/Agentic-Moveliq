import AVFoundation
import Foundation

@MainActor
protocol VoiceSpeaking: AnyObject {
    func speak(_ text: String, onFinish: @escaping () -> Void) throws
    func stop()
}

@MainActor
final class SystemVoiceSpeaker: NSObject, VoiceSpeaking, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var utterance: AVSpeechUtterance?
    private var onFinish: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, onFinish: @escaping () -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try session.setActive(true)
        let speech = AVSpeechUtterance(string: text)
        speech.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        self.utterance = speech
        self.onFinish = onFinish
        synthesizer.speak(speech)
    }

    func stop() {
        utterance = nil
        onFinish = nil
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.utterance === utterance else { return }
            let completion = self.onFinish
            self.stop()
            completion?()
        }
    }
}
