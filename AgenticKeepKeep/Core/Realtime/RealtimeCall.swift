import AVFoundation
import Combine
import Foundation
import UIKit

@MainActor
final class RealtimeCall: ObservableObject {
    enum Phase { case consent, connecting, listening, speaking, paused, failed, review, ended }
    @Published private(set) var phase: Phase = .ended
    @Published private(set) var muted = false
    @Published private(set) var cameraOn = false
    @Published private(set) var switching = false
    @Published private(set) var preview: UIImage?
    @Published private(set) var transcript = ""
    @Published private(set) var reply = ""
    @Published private(set) var notice = ""
    @Published private(set) var planRequest = ""
    @Published var subtitles = true
    var onText: ((String, String) -> Void)?
    private static let idleTimer = RealtimeIdleTimer(
        read: { UIApplication.shared.isIdleTimerDisabled },
        write: { UIApplication.shared.isIdleTimerDisabled = $0 }
    )
    private let idleTimerOwner = UUID()
    private let audio = RealtimeAudio()
    private let camera = RealtimeCamera()
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var sender: Task<Void, Never>?
    private var connecting: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var inputWatchdog: Task<Void, Never>?
    private var inputHealth = RealtimeInputHealth()
    private var engineRecovery = RealtimeEngineRecovery()
    private var generation = UUID()
    private var cameraGeneration = UUID()
    private var queue: [(type: String, text: String)] = []
    private var queueBytes = 0
    private var history: [(role: String, text: String)] = []
    private var restoreHistory = false
    private var audioStarted = false
    private var front = false
    private var requestingCamera = false
    private var responseID: String?
    private var cancelledResponses = Set<String>()
    private var savedItems = Set<String>()
    /// 长回复逐块到达：字幕合并到 60ms 窗口刷新，避免每个 chunk 都重排整屏（设计系统 §10）
    private var replyBuffer = ""
    private var replyThrottle = StreamThrottle()
    private var droppedAudio = false

    private static let audioMessage = "input_audio_buffer.append"
    private static let maxQueuedMessages = 60
    private static let maxQueuedBytes = 1_500_000

    var active: Bool { [.listening, .speaking].contains(phase) }
    func open(history: [(role: String, text: String)] = []) {
        disconnect()
        self.history = Array(history.suffix(12))
        transcript = ""; reply = ""; notice = ""; planRequest = ""; muted = false
        savedItems.removeAll(); phase = .consent
    }
    func connect() {
        guard [.consent, .paused, .failed].contains(phase) else { return }
        disconnect()
        phase = .connecting; notice = "正在连接实时通话…"; muted = false
        let token = generation
        connecting = Task { [weak self] in
            guard let self else { return }
            let allowed = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
            guard self.generation == token, !Task.isCancelled else { return }
            guard allowed else { self.fail("请在系统设置中允许麦克风，再继续通话。"); return }
            guard let session = ServiceCredentials.session else { self.fail("请先登录。"); return }
            Self.idleTimer.acquire(self.idleTimerOwner)
            do {
                var request = URLRequest(url: try ServiceEndpoint.realtimeURL())
                request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 20
                let socket = ServiceTransport.shared.session.webSocketTask(with: request)
                socket.maximumMessageSize = 2 * 1024 * 1024
                self.socket = socket; self.restoreHistory = true
                socket.resume(); self.waitForConfiguration(token: token)
                self.receiver = Task { [weak self] in
                    do {
                        while !Task.isCancelled {
                            let message = try await socket.receive()
                            guard let self, self.generation == token else { return }
                            let data: Data
                            switch message { case .string(let text): data = Data(text.utf8); case .data(let value): data = value; @unknown default: continue }
                            guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                            try self.receive(event)
                        }
                    } catch {
                        guard let self, self.generation == token, !Task.isCancelled else { return }
                        let response = socket.response as? HTTPURLResponse
                        let message = RealtimeWire.connectionMessage(status: response?.statusCode, reason: response?.value(forHTTPHeaderField: "X-Realtime-Error"))
                        self.fail(message + RealtimeWire.transportNote(closeCode: socket.closeCode.rawValue, errorCode: (error as NSError).code))
                    }
                }
            } catch { self.fail("实时通话暂时无法连接，请稍后重试。") }
        }
    }
    private func waitForConfiguration(token: UUID) {
        deadline?.cancel()
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.fail("连接或模式切换超时，请重新连接。")
        }
    }
    private func receive(_ event: [String: Any]) throws {
        guard let type = event["type"] as? String else { return }
        if type == "relay.error" { fail(event["message"] as? String ?? "实时服务不可用。"); return }
        if type == "relay.ready" {
            guard phase == .connecting || switching else { return }
            guard event["outputSampleRate"] as? Int == 24000 else { fail("实时音频格式不兼容，请更新服务。"); return }
            deadline?.cancel()
            if restoreHistory {
                RealtimeWire.history(history).forEach(enqueue)
                restoreHistory = false
            }
            switching = false; notice = ""; phase = .listening
            if !audioStarted {
                let token = generation
                do {
                    engineRecovery = RealtimeEngineRecovery()
                    inputHealth.reset(at: ProcessInfo.processInfo.systemUptime)
                    try audio.start(onInput: { [weak self] data in
                        Task { @MainActor in
                            guard let self, self.generation == token, self.active, !self.muted, !self.switching,
                                  !self.cameraOn || self.preview != nil else { return }
                            self.inputHealth.capture(at: ProcessInfo.processInfo.systemUptime)
                            self.enqueue(["type": "input_audio_buffer.append", "audio": data.base64EncodedString()])
                        }
                    }, onFailure: { [weak self] in
                        Task { @MainActor in
                            guard let self, self.generation == token else { return }
                            self.fail("麦克风音频转换失败，请重新连接；若使用耳机，请断开后再试。")
                        }
                    })
                    audioStarted = true
                    watchInput(token: token)
                } catch { fail("无法启动通话音频，请检查麦克风或蓝牙设备。"); return }
            }
            if cameraOn { startCamera() }
            return
        }
        if type == "input_audio_buffer.speech_started" {
            cancelPlayback(sendCancel: false); phase = .listening; clearReply(); return
        }
        if type == "conversation.item.input_audio_transcription.completed", let text = event["transcript"] as? String {
            transcript = text
            save(role: "user", text: text, id: event["item_id"] as? String ?? UUID().uuidString)
            return
        }
        if type == "response.created" {
            let id = (event["response"] as? [String: Any])?["id"] as? String
            responseID = id
            if switching, let id { cancelledResponses.insert(id) }
            else { clearReply() }
            return
        }
        let id = event["response_id"] as? String ?? responseID ?? ""
        guard !switching, !cancelledResponses.contains(id) else { return }
        switch type {
        case "response.audio.delta":
            guard active, let raw = event["delta"] as? String, let pcm = Data(base64Encoded: raw) else { return }
            do {
                if try audio.play(pcm), !droppedAudio {
                    droppedAudio = true; notice = "播放跟不上，已跳过一段语音。"
                }
                phase = .speaking
            }
            catch { fail("通话音频播放失败，请检查音频设备后重试。") }
        case "response.audio_transcript.delta":
            if let text = event["delta"] as? String {
                replyBuffer += text
                if replyThrottle.shouldEmit() { reply = replyBuffer }
            }
        case "response.audio_transcript.done":
            if let text = event["transcript"] as? String {
                clearReply(); reply = text
                save(role: "assistant", text: text, id: event["item_id"] as? String ?? id)
            }
        case "response.done":
            if active { phase = .listening }
        case "response.function_call_arguments.done":
            guard event["name"] as? String == "propose_training_plan",
                  let arguments = event["arguments"] as? String, let data = arguments.data(using: .utf8),
                  let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let request = body["request"] as? String, !request.isEmpty, request.count <= 4000 else { return }
            planRequest = request
            disconnect(); phase = .review
            notice = "查看建议后将在文字聊天中生成课程草稿，手动确认才会保存。"
        default: break
        }
    }
    private func save(role: String, text: String, id: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, savedItems.insert(role + id).inserted else { return }
        history.append((role, text)); history = Array(history.suffix(12))
        onText?(role, text)
    }
    /// 字幕重置：清空当前回复及未刷新的缓冲
    private func clearReply() {
        reply = ""; replyBuffer = ""
        _ = replyThrottle.flush()
    }
    private func enqueue(_ value: [String: Any]) {
        guard socket != nil, let data = try? JSONSerialization.data(withJSONObject: value), let text = String(data: data, encoding: .utf8) else { return }
        // 麦克风音频可以丢：发送队列满时先丢最早的音频帧，而不是结束整通电话
        while queue.count >= Self.maxQueuedMessages || queueBytes + text.utf8.count > Self.maxQueuedBytes {
            guard let index = queue.firstIndex(where: { $0.type == Self.audioMessage }) else {
                fail("网络过慢，已暂停通话。"); return
            }
            queueBytes -= queue[index].text.utf8.count
            queue.remove(at: index)
        }
        queue.append((value["type"] as? String ?? "", text))
        queueBytes += text.utf8.count
        guard sender == nil else { return }
        let token = generation
        sender = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == token { self.sender = nil } }
            while !self.queue.isEmpty, self.generation == token, !Task.isCancelled {
                let item = self.queue.removeFirst()
                self.queueBytes = max(0, self.queueBytes - item.text.utf8.count)
                do {
                    try await self.socket?.send(.string(item.text))
                    if self.generation == token, item.type == Self.audioMessage {
                        self.inputHealth.upload(at: ProcessInfo.processInfo.systemUptime)
                    }
                }
                catch {
                    guard self.generation == token else { return }
                    self.fail("发送中断，请重新连接。" + RealtimeWire.transportNote(
                        closeCode: self.socket?.closeCode.rawValue ?? 0, errorCode: (error as NSError).code))
                    return
                }
            }
        }
    }
    private func watchInput(token: UUID) {
        inputWatchdog?.cancel()
        inputWatchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.generation == token else { return }
                let expected = self.active && !self.muted && !self.switching && (!self.cameraOn || self.preview != nil)
                let now = ProcessInfo.processInfo.systemUptime
                if self.engineRecovery.shouldRestart(engineRunning: self.audio.isRunning, expectingInput: expected) {
                    do {
                        try self.audio.restartStoppedEngine()
                        self.inputHealth.reset(at: now)
                    } catch {
                        self.fail("通话音频引擎恢复失败，请重新连接。（MIC-RESTART）")
                        return
                    }
                }
                if let failure = self.inputHealth.failure(at: now, shouldSend: expected) {
                    self.fail(failure == .captureStopped
                        ? self.audio.captureFailureMessage(at: now)
                        : "语音上传没有完成，请检查网络后重新连接。")
                    return
                }
            }
        }
    }
    /// 丢掉还没发出去的音频帧（静音、模式切换、断开时用）
    private func dropQueuedAudio() {
        queue.removeAll { $0.type.hasPrefix(Self.audioMessage) }
        queueBytes = queue.reduce(0) { $0 + $1.text.utf8.count }
    }
    func toggleMute() {
        guard active, !switching else { return }
        muted.toggle()
        if muted {
            dropQueuedAudio()
            enqueue(["type": "input_audio_buffer.clear"])
        }
    }
    func interrupt() { guard active else { return }; cancelPlayback(sendCancel: true); phase = .listening }
    private func cancelPlayback(sendCancel: Bool) {
        audio.interrupt()
        if let id = responseID { cancelledResponses.insert(id) }
        if sendCancel { enqueue(["type": "response.cancel"]) }
    }
    func enableCamera() async {
        guard active, !cameraOn, !switching, !requestingCamera else { return }
        requestingCamera = true
        let token = generation
        defer { if generation == token { requestingCamera = false } }
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        guard generation == token, active else { return }
        guard allowed else { notice = "摄像头未获授权，可以继续语音；如需画面请在系统设置开启。"; return }
        cameraOn = true; front = false; switching = true
        cancelPlayback(sendCancel: true)
        dropQueuedAudio()
        enqueue(["type": "input_audio_buffer.clear"])
        enqueue(RealtimeWire.mode(true)); waitForConfiguration(token: token)
    }
    func disableCamera() {
        guard cameraOn else { return }
        cameraGeneration = UUID(); camera.stop(); cameraOn = false; preview = nil
        switching = true; restoreHistory = true
        cancelPlayback(sendCancel: true)
        dropQueuedAudio()
        enqueue(["type": "input_audio_buffer.clear"])
        enqueue(RealtimeWire.mode(false)); waitForConfiguration(token: generation)
    }
    func flipCamera() { guard cameraOn, !switching else { return }; front.toggle(); preview = nil; startCamera() }
    private func startCamera() {
        cameraGeneration = UUID()
        let cameraToken = cameraGeneration, token = generation
        camera.start(front: front, onFrame: { [weak self] data, image in
            Task { @MainActor in
                guard let self, self.generation == token, self.cameraGeneration == cameraToken, self.cameraOn, !self.switching else { return }
                self.preview = image
                self.enqueue(["type": "input_audio_buffer.append_video_frame", "video_frame": data.base64EncodedString()])
            }
        }, onError: { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == token, self.cameraGeneration == cameraToken else { return }
                self.disableCamera(); self.notice = "摄像头启动失败，已切回语音。"
            }
        })
    }
    func pause() {
        guard ![.ended, .consent, .paused, .review].contains(phase) else { return }
        disconnect(); phase = .paused; notice = "采集已停止。继续时仅恢复语音，摄像头需重新开启。"
    }
    func end() { disconnect(); phase = .ended; onText = nil }
    private func fail(_ message: String) { disconnect(); phase = .failed; notice = message }
    private func disconnect() {
        Self.idleTimer.release(idleTimerOwner)
        generation = UUID(); cameraGeneration = UUID()
        receiver?.cancel(); sender?.cancel(); connecting?.cancel(); deadline?.cancel(); inputWatchdog?.cancel()
        receiver = nil; sender = nil; connecting = nil; deadline = nil; inputWatchdog = nil
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        queue.removeAll(); queueBytes = 0; droppedAudio = false
        // 断在这里也要把窗口里最后一段字幕补上，别让用户丢掉最后几个字
        if replyThrottle.flush() { reply = replyBuffer }
        audio.stop(); camera.stop(); audioStarted = false; cameraOn = false; preview = nil; switching = false; requestingCamera = false
        cancelledResponses.removeAll(); responseID = nil
    }
}
