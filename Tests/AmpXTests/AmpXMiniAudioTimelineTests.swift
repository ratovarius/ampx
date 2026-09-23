@testable import AmpX
import AVFoundation
import XCTest

final class AmpXMiniAudioTimelineTests: XCTestCase {
    private func pcm(rate: Double, count: Int, left: Float, right: Float) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)))
        buffer.frameLength = AVAudioFrameCount(count)
        let channels = try XCTUnwrap(buffer.floatChannelData)
        channels[0].initialize(repeating: left, count: count)
        channels[1].initialize(repeating: right, count: count)
        return buffer
    }

    func testStereoMeasurementsAndWaveformAtSupportedRates() throws {
        for rate in [44100.0, 48000, 96000, 192_000] {
            let timeline = AmpXMiniAudioTimeline()
            let count = Int(rate * 0.1)
            try timeline.publish(
                pcm: self.pcm(rate: rate, count: count, left: 0.5, right: 0.25),
                spectrumFrames: [[Float](repeating: 0.7, count: 32)],
                hopOffsets: [count], arrivalTime: 10, generation: 0
            )
            let frame = timeline.snapshot(at: 11)
            XCTAssertEqual(frame.rms.x, 0.5, accuracy: 0.0001)
            XCTAssertEqual(frame.rms.y, 0.25, accuracy: 0.0001)
            XCTAssertEqual(frame.peak, SIMD2<Float>(0.5, 0.25))
            XCTAssertEqual(frame.waveformLeft.last, 0.5)
            XCTAssertEqual(frame.waveformRight.last, 0.25)
            XCTAssertEqual(frame.sampleRate, rate)
        }
    }

    func testSpectrumAndWaveformAdvanceTogetherWithinBatch() throws {
        let timeline = AmpXMiniAudioTimeline()
        let buffer = try self.pcm(rate: 48000, count: 4800, left: 0, right: 0)
        for index in 2400 ..< 4800 {
            buffer.floatChannelData?[0][index] = 0.8
            buffer.floatChannelData?[1][index] = 0.4
        }
        timeline.publish(
            pcm: buffer, spectrumFrames: [[Float](repeating: 0.2, count: 32), [Float](repeating: 0.9, count: 32)],
            hopOffsets: [2400, 4800], arrivalTime: 5, generation: 0
        )
        let first = timeline.snapshot(at: 5)
        let second = timeline.snapshot(at: 5.075)
        XCTAssertEqual(first.spectrum[0], 0.2)
        XCTAssertEqual(first.waveformLeft.last, 0)
        XCTAssertEqual(second.spectrum[0], 0.9)
        XCTAssertEqual(second.waveformLeft.last, 0.8)
        XCTAssertGreaterThan(second.sequence, first.sequence)
        XCTAssertEqual(timeline.snapshot(at: 50).sequence, second.sequence)
    }

    func testResetRejectsLateOldGeneration() throws {
        let timeline = AmpXMiniAudioTimeline()
        let buffer = try self.pcm(rate: 48000, count: 4800, left: 1, right: 1)
        let generation = timeline.reset()
        timeline.publish(
            pcm: buffer,
            spectrumFrames: [[Float](repeating: 1, count: 32)],
            hopOffsets: [4800],
            arrivalTime: 0,
            generation: 0
        )
        XCTAssertEqual(timeline.snapshot(at: 1).generation, generation)
        XCTAssertEqual(timeline.snapshot(at: 1).peak, .zero)
        timeline.publish(
            pcm: buffer,
            spectrumFrames: [[Float](repeating: 1, count: 32)],
            hopOffsets: [4800],
            arrivalTime: 2,
            generation: generation
        )
        XCTAssertEqual(timeline.snapshot(at: 3).peak, SIMD2<Float>(repeating: 1))
    }

    func testCaptureConsumesOnceAndMarksOverwrite() throws {
        let staging = TapPCMStaging(capacity: 32768)
        let first = try self.pcm(rate: 192_000, count: 19200, left: 0.2, right: 0.3)
        let second = try self.pcm(rate: 192_000, count: 19200, left: 0.5, right: 0.6)
        XCTAssertTrue(staging.capture(first, generation: 7, arrivalTime: 1))
        XCTAssertTrue(staging.capture(second, generation: 7, arrivalTime: 2))
        let batch = staging.take()
        XCTAssertEqual(batch?.pcm.frameLength, 19200)
        XCTAssertEqual(batch?.pcm.floatChannelData?[0][0], 0.5)
        XCTAssertEqual(batch?.generation, 7)
        XCTAssertEqual(batch?.arrivalTime, 2)
        XCTAssertEqual(batch?.discontinuity, true)
        XCTAssertNil(staging.take())
    }

    func testOversizedCaptureMarksDiscontinuityAndRetainsNewestSamples() throws {
        let staging = TapPCMStaging(capacity: 256)
        let buffer = try self.pcm(rate: 48000, count: 512, left: 0.25, right: 0.5)
        buffer.floatChannelData?[0][511] = 0.9
        XCTAssertTrue(staging.capture(buffer))
        let batch = staging.take()
        XCTAssertEqual(batch?.pcm.frameLength, 256)
        XCTAssertEqual(batch?.pcm.floatChannelData?[0][255], 0.9)
        XCTAssertEqual(batch?.discontinuity, true)
    }

    func testBipolarTransientSurvivesPCMThroughPreparedWaveform() throws {
        for rate in [44100.0, 48000, 96000, 192_000] {
            let count = Int(rate * 0.02)
            let buffer = try self.pcm(rate: rate, count: count, left: 0, right: 0)
            buffer.floatChannelData?[0][5] = 1
            buffer.floatChannelData?[0][6] = -0.8
            let timeline = AmpXMiniAudioTimeline()
            timeline.publish(
                pcm: buffer,
                spectrumFrames: [[Float](repeating: 0.5, count: 32)],
                hopOffsets: [count],
                arrivalTime: 1,
                generation: 0
            )
            var state = AmpXMiniVisualizerState()
            let prepared = state.update(timeline.snapshot(at: 2), at: 2)
            XCTAssertEqual(prepared.waveform.min(), -0.8, "negative lobe at \(rate) Hz")
            XCTAssertEqual(prepared.waveform.max(), 1, "positive lobe at \(rate) Hz")
            XCTAssertLessThanOrEqual(prepared.waveform.count, 512)
        }
    }

    func testStereoMeasurementsReleaseAfterTwentyMillisecondsOfSilence() throws {
        for rate in [44100.0, 48000, 96000, 192_000] {
            let timeline = AmpXMiniAudioTimeline()
            let count = Int(rate * 0.02)
            try timeline.publish(
                pcm: self.pcm(rate: rate, count: count, left: 0.5, right: 0.25),
                spectrumFrames: [[Float](repeating: 0, count: 32)],
                hopOffsets: [count], arrivalTime: 1, generation: 0
            )
            XCTAssertEqual(timeline.snapshot(at: 1).rms, SIMD2(0.5, 0.25))
            try timeline.publish(
                pcm: self.pcm(rate: rate, count: count, left: 0, right: 0),
                spectrumFrames: [[Float](repeating: 0, count: 32)],
                hopOffsets: [count], arrivalTime: 1.02, generation: 0
            )
            let quiet = timeline.snapshot(at: 1.02)
            XCTAssertEqual(quiet.rms, .zero, "\(rate) Hz must not smear the preceding beat into silence")
            XCTAssertEqual(quiet.peak, .zero, "sample-peak window must not retain stale audio")
        }
    }
}
