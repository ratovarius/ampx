@testable import AmpX
import XCTest

/// DJ mode spec Revision 2 § Audio graph: B starts at the host time where A's mix-out downbeat is heard.
final class DeckSyncTests: XCTestCase {
    func testStartHostTimeAtRateOne() {
        let start = DeckSync.startHostTime(nowHostTime: 1000, outgoingNow: 50, outgoingTarget: 60, outgoingRate: 1, ticksPerSecond: 100)
        XCTAssertEqual(start, 2000)
    }

    func testStartHostTimeScalesByRate() {
        let start = DeckSync.startHostTime(nowHostTime: 0, outgoingNow: 0, outgoingTarget: 10.5, outgoingRate: 1.05, ticksPerSecond: 1000)
        XCTAssertEqual(start, 10000)
    }

    func testTargetInThePastClampsToNow() {
        XCTAssertEqual(DeckSync.startHostTime(nowHostTime: 500, outgoingNow: 20, outgoingTarget: 10, outgoingRate: 1, ticksPerSecond: 100), 500)
    }
}
