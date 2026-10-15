import AVFoundation
import Foundation

@MainActor
final class RealtimeAudio {
    private var captureProgress = RealtimeCaptureProgress()
    private var tapInstalled = false
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var captureMixer: AVAudioMixerNode?
    private var outputFormat: AVAudioFormat?
    private var playback = RealtimePlaybackQueue()
    private var playbackGeneration = UUID()

    func start(onInput: @escaping @Sendable (Data) -> Void, onFailure: @escaping @Sendable () -> Void) throws {
        stop()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        let engine = AVAudioEngine(), player = AVAudioPlayerNode(), captureMixer = AVAudioMixerNode()
        self.engine = engine; self.player = player; self.captureMixer = captureMixer
        try engine.inputNode.setVoiceProcessingEnabled(true)
        engine.inputNode.isVoiceProcessingInputMuted = false
        let input = engine.inputNode.outputFormat(forBus: 0)
        guard input.sampleRate > 0, input.channelCount > 0,
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false) else {
            throw AudioError.unavailable
        }
        outputFormat = output
        engine.attach(player)
        engine.attach(captureMixer)
        // Keep an explicit render path for capture even before playback is scheduled.
        // Only the monitor branch is muted; the input tap still receives microphone audio.
        captureMixer.outputVolume = 0
        engine.connect(engine.inputNode, to: captureMixer, format: input)
        engine.connect(captureMixer, to: engine.mainMixerNode, format: input)
        engine.connect(player, to: engine.mainMixerNode, format: output)
        let converter = RealtimeInputConverter()
        let progress = RealtimeCaptureProgress()
        captureProgress = progress
        engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: nil) { buffer, _ in
            progress.received(frames: Int(buffer.frameLength), at: ProcessInfo.processInfo.systemUptime)
            do {
                if let pcm = try converter.convert(buffer) {
                    progress.produced(at: ProcessInfo.processInfo.systemUptime)
                    onInput(RealtimeWire.wav(pcm))
                }
            } catch { onFailure() }
        }
        tapInstalled = true
        engine.prepare(); try engine.start(); player.play()
    }

    var isRunning: Bool { engine?.isRunning == true }

    func restartStoppedEngine() throws {
        guard let engine else { throw AudioError.unavailable }
        guard !engine.isRunning else { return }
        try AVAudioSession.sharedInstance().setActive(true)
        // Keep the existing voice-processing graph; never fall back to unprocessed speaker audio.
        engine.prepare()
        try engine.start()
        player?.play()
    }

    func captureFailureMessage(at now: TimeInterval) -> String {
        switch captureProgress.stage(engineRunning: isRunning, at: now) {
        case .engineStopped: return "通话音频引擎已停止，请重新连接。（MIC-ENGINE）"
        case .noCallback: return "麦克风采集没有回调，请重新连接。（MIC-TAP）"
        case .emptyBuffer: return "麦克风返回空音频，请重新连接。（MIC-EMPTY）"
        case .noConversion: return "麦克风音频转换没有输出，请重新连接。（MIC-CONVERT）"
        case .deliveryStopped: return "已采集音频，但未进入发送队列，请重新连接。（MIC-DELIVERY）"
        }
    }

    /// 排队播放一段 24kHz PCM16。
    /// 返回 true 表示这一批里有音频因为积压被跳过（调用方可以提示一次），通话本身不受影响。
    @discardableResult
    func play(_ pcm: Data) throws -> Bool {
        guard !pcm.isEmpty, pcm.count % 2 == 0,
              let format = outputFormat, let player else { throw AudioError.unavailable }
        let dropped = playback.droppedFrames
        var offset = 0
        for frames in playback.admit(frames: pcm.count / 2) {
            let start = offset
            offset += frames * 2
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
                  let samples = buffer.floatChannelData?[0] else { playback.played(frames: frames); continue }
            buffer.frameLength = AVAudioFrameCount(frames)
            pcm.withUnsafeBytes { raw in
                let bytes = raw.bindMemory(to: UInt8.self)
                for i in 0..<frames {
                    let at = start + i * 2
                    samples[i] = Float(Int16(bitPattern: UInt16(bytes[at]) | UInt16(bytes[at+1]) << 8)) / 32768
                }
            }
            let token = playbackGeneration
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.playbackGeneration == token else { return }
                    self.playback.played(frames: frames)
                }
            }
        }
        if !player.isPlaying { player.play() }
        return playback.droppedFrames > dropped
    }
    func interrupt() { playbackGeneration = UUID(); player?.stop(); playback.reset(); if engine?.isRunning == true { player?.play() } }
    func stop() {
        interrupt()
        if let engine { engine.stop(); if tapInstalled { engine.inputNode.removeTap(onBus: 0) } }
        tapInstalled = false
        engine = nil; player = nil; captureMixer = nil; outputFormat = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    enum AudioError: Error { case unavailable }
}
