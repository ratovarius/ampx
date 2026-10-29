@testable import AmpX
import XCTest

/// DJ mode spec Revision 2 § Audio graph: B starts where A's mix-out downbeat is heard.
final class DeckSyncTests: XCTestCase {
    private func start(now: Double, target: Double = 60, rateA: Double = 1, rateB: Double = 1, incomingStart: Double = 0) -> DeckSync.Start {
        DeckSync.start(outgoingNow: now, outgoingTarget: target, outgoingRate: rateA, incomingRate: rateB, incomingStart: incomingStart)
    }

    func testDelayAtRateOne() {
        let start = self.start(now: 50)
        XCTAssertEqual(start.requestedDelay, 10, accuracy: 1e-12)
        XCTAssertEqual(start.incomingStart, 0)
    }

    func testDelayFollowsOutgoingRate() {
        XCTAssertEqual(self.start(now: 49.5, rateA: 1.05).requestedDelay, 10, accuracy: 1e-12)
    }

    /// `play(at:)` in front of an active time-pitch unit waits `requested / rateB` (measured on device), so the
    /// request is scaled by B's rate: 10 s at rate 1.05 is requested as 10.5 s.
    func testDelayScalesByIncomingRate() {
        XCTAssertEqual(self.start(now: 50, rateB: 1.05).requestedDelay, 10.5, accuracy: 1e-12)
        XCTAssertEqual(self.start(now: 50, rateA: 1.02, rateB: 0.97).requestedDelay, 10 / 1.02 * 0.97, accuracy: 1e-12)
    }

    /// Armed late (A already past its mix-out): B starts after the minimum lead, skipping what it would have played.
    func testLateStartSkipsIncomingAhead() {
        let start = self.start(now: 61, rateA: 1, rateB: 1.02, incomingStart: 8)
        XCTAssertEqual(start.requestedDelay, DeckSync.minimumLead * 1.02, accuracy: 1e-12)
        XCTAssertEqual(start.incomingStart, 8 + (1 + DeckSync.minimumLead) * 1.02, accuracy: 1e-12)
    }

    func testLeadShorterThanMinimumAlsoSkipsAhead() {
        let start = self.start(now: 59.99, rateA: 1, rateB: 1)
        XCTAssertEqual(start.requestedDelay, DeckSync.minimumLead, accuracy: 1e-12)
        XCTAssertEqual(start.incomingStart, DeckSync.minimumLead - 0.01, accuracy: 1e-9)
    }
}
