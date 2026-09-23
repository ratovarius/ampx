@testable import AmpX
import XCTest

private final class SpyJavaScriptEvaluator: EntheaJavaScriptEvaluating {
    var callCount = 0
    var completeImmediately = true
    var lastScript: String?

    func evaluateJavaScript(
        _ javaScriptString: String,
        completionHandler: (@Sendable (Any?, (any Error)?) -> Void)?
    ) {
        self.callCount += 1
        self.lastScript = javaScriptString
        if self.completeImmediately {
            completionHandler?(nil, nil)
        }
    }
}

final class EntheaAudioBridgeTests: XCTestCase {
    func testBridgeDoesNotEvaluateWhenInactive() {
        let evaluator = SpyJavaScriptEvaluator()
        let bridge = EntheaAudioBridge(featureBus: .shared, evaluator: evaluator)
        bridge.isActive = false
        bridge.tick()
        XCTAssertEqual(evaluator.callCount, 0)
    }

    func testBridgeSkipsPushWhileAPreviousEvaluationIsInFlight() {
        let evaluator = SpyJavaScriptEvaluator()
        evaluator.completeImmediately = false
        let bus = AudioFeatureBus.shared
        bus.publishRawBins(Array(repeating: 7, count: AudioFeatures.rawBinCount), sampleRate: 48000)
        bus.setPlaying(true)
        let bridge = EntheaAudioBridge(featureBus: bus, evaluator: evaluator)
        bridge.isActive = true
        bridge.tick()
        bridge.tick()
        bridge.tick()
        XCTAssertEqual(evaluator.callCount, 1, "pushes must coalesce, not queue")
    }

    func testBridgePushIncludesBase64PayloadAndSampleRate() {
        let evaluator = SpyJavaScriptEvaluator()
        let bus = AudioFeatureBus.shared
        bus.publishRawBins(Array(repeating: 7, count: AudioFeatures.rawBinCount), sampleRate: 48000)
        bus.setPlaying(true)

        let bridge = EntheaAudioBridge(featureBus: bus, evaluator: evaluator)
        bridge.isActive = true
        bridge.tick()

        guard let script = evaluator.lastScript else {
            return XCTFail("expected a JS push")
        }
        XCTAssertTrue(script.contains("winampAudio.push("))
        XCTAssertTrue(script.contains("48000"))
        XCTAssertTrue(script.contains("true"))
    }

    func testBridgeSkipsPushWhenNotPlaying() {
        let evaluator = SpyJavaScriptEvaluator()
        let bus = AudioFeatureBus.shared
        bus.publishRawBins(Array(repeating: 7, count: AudioFeatures.rawBinCount), sampleRate: 48000)
        bus.setPlaying(false)

        let bridge = EntheaAudioBridge(featureBus: bus, evaluator: evaluator)
        bridge.isActive = true
        bridge.tick()
        XCTAssertEqual(evaluator.callCount, 0)
    }

    func testBridgeRespectsMaxPushHz() {
        let evaluator = SpyJavaScriptEvaluator()
        let bus = AudioFeatureBus.shared
        bus.publishRawBins(Array(repeating: 7, count: AudioFeatures.rawBinCount), sampleRate: 48000)
        bus.setPlaying(true)

        let bridge = EntheaAudioBridge(featureBus: bus, evaluator: evaluator)
        bridge.isActive = true
        bridge.maxPushHz = 30
        bridge.tick()
        bridge.tick()
        XCTAssertEqual(evaluator.callCount, 1, "second tick within 1/30s must be rate-limited")
    }
}
