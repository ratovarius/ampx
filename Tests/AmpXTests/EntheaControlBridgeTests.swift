@testable import AmpX
import XCTest

private final class RecordingEvaluator: EntheaJavaScriptEvaluating {
    private(set) var scripts: [String] = []
    var readyResult: Any? = true
    var statusResult: Any?

    func evaluateJavaScript(
        _ javaScriptString: String,
        completionHandler: (@Sendable (Any?, (any Error)?) -> Void)?
    ) {
        self.scripts.append(javaScriptString)
        if javaScriptString.contains("winampEnthea.ready") {
            completionHandler?(self.readyResult, nil)
        } else if javaScriptString.contains("getStatus") {
            completionHandler?(self.statusResult, nil)
        } else {
            completionHandler?(nil, nil)
        }
    }
}

final class EntheaControlBridgeTests: XCTestCase {
    func testStepModeEmitsRelativeJS() {
        let evaluator = RecordingEvaluator()
        let bridge = EntheaControlBridge(evaluator: evaluator)
        bridge.stepMode(1)
        XCTAssertTrue(evaluator.scripts.contains { $0.contains("stepMode(1)") })
    }

    func testSetModeEmitsAbsoluteJS() {
        let evaluator = RecordingEvaluator()
        let bridge = EntheaControlBridge(evaluator: evaluator)
        bridge.setMode(7)
        XCTAssertTrue(evaluator.scripts.contains { $0.contains("setMode(7)") })
    }

    func testHostStatusParsesDictionary() {
        let status = EntheaHostStatus(jsValue: [
            "mode": 3,
            "name": "SACRED GEOM",
            "autopilot": true,
            "dose": 0.55,
        ])
        XCTAssertEqual(status?.modeID, 3)
        XCTAssertEqual(status?.modeName, "SACRED GEOM")
        XCTAssertEqual(status?.autopilot, true)
        XCTAssertEqual(status?.dose ?? 0, 0.55, accuracy: 0.001)
    }

    func testSetSubstanceEmitsJS() {
        let evaluator = RecordingEvaluator()
        let bridge = EntheaControlBridge(evaluator: evaluator)
        bridge.setSubstance("psilo")
        XCTAssertTrue(evaluator.scripts.contains { $0.contains("setSubstance(\"psilo\")") })
    }

    @MainActor
    func testStripTitleReflectsAutopilot() {
        let controller = EntheaPanelController()
        controller.autopilot = true
        XCTAssertEqual(controller.stripTitle, "ENTHEA • AUTOPILOT")
        controller.autopilot = false
        controller.modeName = "Neural Field"
        XCTAssertEqual(controller.stripTitle, "ENTHEA • NEURAL FIELD")
    }
}
