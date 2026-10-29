@testable import AmpX
import XCTest

/// DJ mode spec Revision 2 § Transitions.
final class BlendCurveTests: XCTestCase {
    private func plan(_ kind: MixPlan.Kind) -> MixPlan {
        MixPlan(kind: kind, outgoingStart: 100, incomingStart: 0, length: 30, blendBars: 16, switchTime: 115)
    }

    func testEqualPowerSumIsOne() {
        let curve = BlendCurve(plan: self.plan(.crossfade))
        for step in 0 ... 10 {
            let gains = curve.gains(at: Double(step) / 10)
            XCTAssertEqual(gains.outgoing * gains.outgoing + gains.incoming * gains.incoming, 1, accuracy: 1e-6)
        }
        XCTAssertEqual(curve.gains(at: 0).outgoing, 1)
        XCTAssertEqual(curve.gains(at: 0).incoming, 0)
        XCTAssertEqual(curve.gains(at: 1).outgoing, 0, accuracy: 1e-6)
        XCTAssertEqual(curve.gains(at: 1).incoming, 1)
    }

    func testProgressClampsAndIsLinearInOutgoingTime() {
        let curve = BlendCurve(plan: self.plan(.crossfade))
        XCTAssertEqual(curve.progress(atOutgoingTime: 90), 0)
        XCTAssertEqual(curve.progress(atOutgoingTime: 107.5), 0.25, accuracy: 1e-12)
        XCTAssertEqual(curve.progress(atOutgoingTime: 130), 1)
        XCTAssertEqual(curve.progress(atOutgoingTime: 200), 1)
    }

    func testBassSwapCutSwitchesOnce() {
        let curve = BlendCurve(plan: self.plan(.beatmatched(rate: 1, transition: .bassSwap)))
        XCTAssertTrue(curve.lowCut(atOutgoingTime: 100) == (false, true))
        XCTAssertTrue(curve.lowCut(atOutgoingTime: 114.99) == (false, true))
        XCTAssertTrue(curve.lowCut(atOutgoingTime: 115) == (true, false))
        XCTAssertTrue(curve.lowCut(atOutgoingTime: 129) == (true, false))
        XCTAssertFalse(curve.isPastSwitch(atOutgoingTime: 114.99))
        XCTAssertTrue(curve.isPastSwitch(atOutgoingTime: 115))
    }

    func testCrossfadeNeverCuts() {
        for kind in [MixPlan.Kind.crossfade, .beatmatched(rate: 1.02, transition: .crossfade)] {
            let curve = BlendCurve(plan: self.plan(kind))
            for time in [100.0, 114, 116, 130] {
                XCTAssertTrue(curve.lowCut(atOutgoingTime: time) == (false, false))
            }
        }
    }
}
