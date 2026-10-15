import Foundation

@MainActor
protocol VoiceRecognizing: AnyObject {
    var onUpdate: ((String, Bool) -> Void)? { get set }
    var onFailure: ((String) -> Void)? { get set }
    func start() async
    func stop()
}
