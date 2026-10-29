@testable import AmpX
import XCTest

/// DJ mode spec Revision 2 § Tempo.
final class TempoPlanTests: XCTestCase {
    func testMatchRateWithinClamp() throws {
        XCTAssertEqual(try XCTUnwrap(TempoPlan.matchRate(outgoingEffectiveBPM: 128, incomingLocalBPM: 126)), 128.0 / 126.0, accuracy: 1e-12)
    }

    func testMatchRateOutsideClampIsNil() {
        XCTAssertNil(TempoPlan.matchRate(outgoingEffectiveBPM: 128, incomingLocalBPM: 138))
        XCTAssertNil(TempoPlan.matchRate(outgoingEffectiveBPM: 128, incomingLocalBPM: 0))
    }

    func testOctaveFactor() {
        XCTAssertEqual(TempoPlan.octaveFactor(incoming: 87, outgoing: 174), 2)
        XCTAssertEqual(TempoPlan.octaveFactor(incoming: 176, outgoing: 88), 0.5)
        XCTAssertEqual(TempoPlan.octaveFactor(incoming: 126, outgoing: 128), 1)
    }
}
