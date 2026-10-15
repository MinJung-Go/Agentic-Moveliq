import AVFoundation
import Foundation

/// Owned by one input tap; conversion stays on that tap's serial audio callback.
final class RealtimeInputConverter {
    private var converter: AVAudioConverter?
    private let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!

    func convert(_ input: AVAudioPCMBuffer) throws -> Data? {
        guard input.frameLength > 0 else { return nil }
        guard input.format.sampleRate > 0, input.format.channelCount > 0 else { throw ConversionError.invalidFormat }
        // Voice processing / route negotiation can change the delivered format.
        if converter?.inputFormat != input.format {
            guard let next = AVAudioConverter(from: input.format, to: target) else { throw ConversionError.invalidFormat }
            next.channelMap = [0]
            next.primeMethod = .none
            converter = next
        }
        guard let converter else { throw ConversionError.invalidFormat }
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * target.sampleRate / input.format.sampleRate) + 32)
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { throw ConversionError.conversionFailed }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            guard !consumed else { state.pointee = .noDataNow; return nil }
            consumed = true
            state.pointee = .haveData
            return input
        }
        guard status != .error, error == nil else { throw ConversionError.conversionFailed }
        guard output.frameLength > 0 else { return nil }
        guard let samples = output.int16ChannelData?[0] else { throw ConversionError.conversionFailed }
        return Data(bytes: samples, count: Int(output.frameLength) * MemoryLayout<Int16>.size)
    }

    enum ConversionError: Error { case invalidFormat, conversionFailed }
}
