import AVFoundation
import CoreImage
import UIKit

/// All capture mutations and frame processing run on one serial queue.
final class RealtimeCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "moveliq.realtime.camera")
    private let session = AVCaptureSession()
    private let context = CIContext()
    private var callback: (@Sendable (Data, UIImage) -> Void)?
    private var lastFrame = CFAbsoluteTimeGetCurrent()

    func start(front: Bool, onFrame: @escaping @Sendable (Data, UIImage) -> Void,
               onError: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            session.stopRunning(); callback = nil
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
            session.automaticallyConfiguresApplicationAudioSession = false
            session.sessionPreset = .vga640x480
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back),
                  let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                session.commitConfiguration(); onError(); return
            }
            session.addInput(input)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            guard session.canAddOutput(output) else { session.commitConfiguration(); onError(); return }
            session.addOutput(output)
            if let connection = output.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                if connection.isVideoMirroringSupported { connection.isVideoMirrored = front }
            }
            session.commitConfiguration(); callback = onFrame
            lastFrame = 0; session.startRunning()
        }
    }
    func stop() { queue.async { [self] in callback = nil; session.stopRunning() } }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let callback, CFAbsoluteTimeGetCurrent() - lastFrame >= 1,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = CFAbsoluteTimeGetCurrent()
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let cg = context.createCGImage(ci, from: ci.extent) else { return }
        let image = UIImage(cgImage: cg)
        guard let jpeg = image.jpegData(compressionQuality: 0.5), jpeg.count < 290000 else { return }
        callback(jpeg, image)
    }
}
