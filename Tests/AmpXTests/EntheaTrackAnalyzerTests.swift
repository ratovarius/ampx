@testable import AmpX
import AVFoundation
import XCTest

final class EntheaTrackAnalyzerTests: XCTestCase {
    /// Synthetic EDM-ish slam: quiet pad, brief dip, then a loud bass hit near 2.0 s.
    func testAnalyzerFindsDropNearKnownSlam() throws {
        let sampleRate = 44100.0
        let duration = 4.0
        let n = Int(sampleRate * duration)
        var samples = [Float](repeating: 0.02, count: n)

        // Dip before the slam (classic build→break→drop cue).
        let dipStart = Int(1.4 * sampleRate)
        let dipEnd = Int(1.85 * sampleRate)
        for i in dipStart ..< dipEnd {
            samples[i] = 0.005
        }

        // Bass-heavy slam centered ~2.0 s (40 Hz tone + envelope).
        let slamCenter = 2.0
        let slamHalf = 0.12
        let slam0 = Int((slamCenter - slamHalf) * sampleRate)
        let slam1 = Int((slamCenter + slamHalf) * sampleRate)
        let twoPiF = 2 * Float.pi * 40 / Float(sampleRate)
        for i in slam0 ..< min(n, slam1) {
            let t = Float(i - slam0) / Float(max(1, slam1 - slam0))
            let env = sin(Float.pi * t)
            samples[i] = 0.95 * env * sin(twoPiF * Float(i))
        }

        let timeline = EntheaTrackAnalyzer.analyzeMono(samples: samples, sampleRate: sampleRate)
        XCTAssertEqual(timeline.dur, duration, accuracy: 0.02)
        XCTAssertFalse(timeline.drops.isEmpty, "Expected at least one drop around the slam")
        let nearest = try XCTUnwrap(timeline.drops.min(by: { abs($0 - slamCenter) < abs($1 - slamCenter) }))
        XCTAssertEqual(
            nearest,
            slamCenter,
            accuracy: 0.35,
            "Drop should land near the synthetic slam (got \(timeline.drops))"
        )
        XCTAssertFalse(timeline.sections.isEmpty)
        XCTAssertGreaterThan(timeline.fps, 0)
    }

    func testAnalyzeWritesReadableWAVFixture() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("enthea-drop-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        try Self.writeDropFixture(to: url, sampleRate: 44100, duration: 3.5, slamAt: 1.8)
        let timeline = try EntheaTrackAnalyzer.analyze(url: url)
        XCTAssertGreaterThan(timeline.dur, 3.0)
        XCTAssertFalse(timeline.drops.isEmpty)
        let nearest = try XCTUnwrap(timeline.drops.min(by: { abs($0 - 1.8) < abs($1 - 1.8) }))
        XCTAssertEqual(nearest, 1.8, accuracy: 0.4)
    }

    func testTimelineJSONRoundTrip() throws {
        let timeline = EntheaTimeline(
            dur: 10,
            drops: [2.5, 8.0],
            sections: [
                EntheaTimelineSection(t: 0, energy: 0),
                EntheaTimelineSection(t: 4, energy: 1),
            ],
            fps: 43.5
        )
        let json = try timeline.jsonObjectString()
        XCTAssertTrue(json.contains("\"drops\""))
        XCTAssertTrue(json.contains("2.5"))
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(EntheaTimeline.self, from: data)
        XCTAssertEqual(decoded, timeline)
    }

    private static func writeDropFixture(
        to url: URL,
        sampleRate: Double,
        duration: Double,
        slamAt: Double
    ) throws {
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?[0] else {
            XCTFail("missing channel")
            return
        }
        let n = Int(frameCount)
        for i in 0 ..< n {
            channel[i] = 0.02
        }
        let dip0 = Int((slamAt - 0.45) * sampleRate)
        let dip1 = Int((slamAt - 0.1) * sampleRate)
        for i in max(0, dip0) ..< min(n, dip1) {
            channel[i] = 0.004
        }
        let half = 0.1
        let s0 = Int((slamAt - half) * sampleRate)
        let s1 = Int((slamAt + half) * sampleRate)
        let twoPiF = 2 * Float.pi * 55 / Float(sampleRate)
        for i in max(0, s0) ..< min(n, s1) {
            let t = Float(i - s0) / Float(max(1, s1 - s0))
            channel[i] = 0.95 * sin(Float.pi * t) * sin(twoPiF * Float(i))
        }
        try file.write(from: buffer)
    }
}

final class EntheaTrackBridgeTests: XCTestCase {
    func testTrackChangeEmitsSetTimeline() async throws {
        let evaluator = RecordingTrackEvaluator()
        let bridge = EntheaTrackBridge(evaluator: evaluator)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("enthea-bridge-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try EntheaTrackAnalyzerTests_writeMinimalSlam(url: url)

        bridge.trackDidChange(url: url)

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if evaluator.scripts.contains(where: { $0.contains("setTimeline({") }) {
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(
            evaluator.scripts.contains(where: { $0.contains("setTimeline({") }),
            "Expected setTimeline after analysis, got: \(evaluator.scripts)"
        )
    }

    func testPositionTickRateLimited() {
        let evaluator = RecordingTrackEvaluator()
        let bridge = EntheaTrackBridge(evaluator: evaluator)
        bridge.isActive = true
        bridge.tickPosition(seconds: 1.0, paused: false)
        bridge.tickPosition(seconds: 1.01, paused: false)
        let positionCalls = evaluator.scripts.filter { $0.contains("setPosition") }
        XCTAssertEqual(positionCalls.count, 1)
        bridge.tickPosition(seconds: 1.0, paused: true)
        let afterPause = evaluator.scripts.filter { $0.contains("setPosition") }
        XCTAssertEqual(afterPause.count, 2)
    }
}

private final class RecordingTrackEvaluator: EntheaJavaScriptEvaluating {
    private let lock = NSLock()
    private(set) var scripts: [String] = []

    func evaluateJavaScript(
        _ javaScriptString: String,
        completionHandler: (@Sendable (Any?, (any Error)?) -> Void)?
    ) {
        self.lock.lock()
        self.scripts.append(javaScriptString)
        self.lock.unlock()
        completionHandler?(nil, nil)
    }
}

private func EntheaTrackAnalyzerTests_writeMinimalSlam(url: URL) throws {
    let sampleRate = 44100.0
    let duration = 3.0
    let frameCount = AVAudioFrameCount(duration * sampleRate)
    guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
        throw EntheaTrackAnalyzerError.cannotOpenFile
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        throw EntheaTrackAnalyzerError.cannotOpenFile
    }
    buffer.frameLength = frameCount
    let channel = buffer.floatChannelData![0]
    let n = Int(frameCount)
    for i in 0 ..< n {
        channel[i] = 0.02
    }
    let slamAt = 1.5
    let s0 = Int((slamAt - 0.1) * sampleRate)
    let s1 = Int((slamAt + 0.1) * sampleRate)
    for i in s0 ..< s1 {
        let t = Float(i - s0) / Float(s1 - s0)
        channel[i] = 0.9 * sin(Float.pi * t) * sin(2 * Float.pi * 50 * Float(i) / Float(sampleRate))
    }
    for i in Int((slamAt - 0.4) * sampleRate) ..< Int((slamAt - 0.12) * sampleRate) {
        channel[i] = 0.004
    }
    try file.write(from: buffer)
}
