import AVFoundation
import XCTest
@testable import AgenticKeepKeep

final class RealtimeInputTests: XCTestCase {
    private func buffer(rate: Double, channels: AVAudioChannelCount = 1, value: Float = 0.25) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: false)!
        let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate / 10))!
        result.frameLength = result.frameCapacity
        for channel in 0..<Int(channels) {
            for index in 0..<Int(result.frameLength) {
                result.floatChannelData![channel][index] = channel == 0 ? value : -value
            }
        }
        return result
    }
    private func samples(_ data: Data) -> [Int16] {
        let bytes = Array(data)
        return stride(from: 0, to: bytes.count - 1, by: 2).map {
            Int16(bitPattern: UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8)
        }
    }
    func testHardwareRatesProduceAudible16kPCMWithoutDuplication() throws {
        for rate in [16000.0, 44100.0, 48000.0] {
            let converter = RealtimeInputConverter()
            var output = Data()
            for _ in 0..<100 { output.append(try XCTUnwrap(converter.convert(buffer(rate: rate)))) }
            let values = samples(output)
            // A live resampler retains a partial internal block; no end-of-stream flush occurs.
            // Over ten seconds, allow one input period of pending data, but no duplicated audio.
            XCTAssertGreaterThanOrEqual(values.count, 158400, "sample rate \(rate)")
            XCTAssertLessThanOrEqual(values.count, 160002, "sample rate \(rate)")
            XCTAssertGreaterThan(values.filter { abs(Int($0)) > 4000 }.count, values.count * 9 / 10)
        }
    }
    func testSilenceIsStillUploadedAsAudio() throws {
        let pcm = try XCTUnwrap(RealtimeInputConverter().convert(buffer(rate: 48000, value: 0)))
        XCTAssertFalse(pcm.isEmpty)
        XCTAssertTrue(pcm.allSatisfy { $0 == 0 })
    }
    func testInputFormatChangesRebuildConverter() throws {
        let converter = RealtimeInputConverter()
        for rate in [48000.0, 44100.0, 16000.0] {
            var pcm = Data()
            for _ in 0..<100 { pcm.append(try XCTUnwrap(converter.convert(buffer(rate: rate)))) }
            XCTAssertGreaterThanOrEqual(pcm.count / 2, 158400)
            XCTAssertLessThanOrEqual(pcm.count / 2, 160002)
            XCTAssertTrue(samples(pcm).contains { $0 > 4000 })
        }
    }
    func testMultiChannelVoiceSelectsMicrophoneChannelWithoutCancellingIt() throws {
        let pcm = try XCTUnwrap(RealtimeInputConverter().convert(buffer(rate: 48000, channels: 2)))
        XCTAssertGreaterThan(samples(pcm).filter { $0 > 4000 }.count, pcm.count / 4)
    }
    func testEmptyInputProducesNoInventedAudio() throws {
        let input = buffer(rate: 48000); input.frameLength = 0
        XCTAssertNil(try RealtimeInputConverter().convert(input))
    }
}
