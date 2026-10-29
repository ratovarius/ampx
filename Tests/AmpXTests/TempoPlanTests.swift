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

/// DJ mode spec Revision 2 § Tempo: glide back.
final class TempoPlanGlideTests: XCTestCase {
    private func step(_ current: Double, original: Double = 124, next: Double?) -> Double {
        TempoPlan.glideStep(currentBPM: current, originalBPM: original, nextBPM: next, speedPer4Bars: 0.1)
    }

    func testGlideMovesTowardOriginalWhenNextLiesThatWay() {
        XCTAssertEqual(self.step(128, next: 122), 127.975, accuracy: 1e-9)
    }

    func testGlideHoldsWhenNextLiesTheOtherWay() {
        XCTAssertEqual(self.step(128, next: 130), 128)
    }

    func testGlideStopsAtOriginal() {
        XCTAssertEqual(self.step(124.01, next: 120), 124)
        XCTAssertEqual(self.step(124, next: 120), 124)
    }

    func testGlideUpward() {
        XCTAssertEqual(self.step(120, next: 125), 120.025, accuracy: 1e-9)
    }

    func testGlideHoldsWithoutNext() {
        XCTAssertEqual(self.step(128, next: nil), 128)
    }

    func testGlideOctaveNormalisesNext() {
        XCTAssertEqual(self.step(128, next: 62), 127.975, accuracy: 1e-9)
    }
}
