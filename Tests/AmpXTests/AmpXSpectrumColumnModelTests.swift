@testable import AmpX
import XCTest

final class AmpXSpectrumColumnModelTests: XCTestCase {
    func testLitCountClampsBelowZero() {
        XCTAssertEqual(AmpXSpectrumColumnModel.litCount(level: -1, segmentCount: 12), 0)
    }

    func testLitCountClampsAboveOne() {
        XCTAssertEqual(AmpXSpectrumColumnModel.litCount(level: 1, segmentCount: 12), 12)
    }

    func testLitCountMapsHalfLevel() {
        XCTAssertEqual(AmpXSpectrumColumnModel.litCount(level: 0.5, segmentCount: 12), 6)
    }

    func testLitCountRoundsNearestSegment() {
        XCTAssertEqual(AmpXSpectrumColumnModel.litCount(level: 0.26, segmentCount: 12), 3)
        XCTAssertEqual(AmpXSpectrumColumnModel.litCount(level: 0.24, segmentCount: 12), 3)
    }

    func testColorBandMatchesMeasuredThresholds() {
        let count = 16
        XCTAssertEqual(AmpXSpectrumColumnModel.colorBand(segment: 0, count: count), 0)
        XCTAssertEqual(AmpXSpectrumColumnModel.colorBand(segment: 6, count: count), 0)
        XCTAssertEqual(AmpXSpectrumColumnModel.colorBand(segment: 7, count: count), 1)
        XCTAssertEqual(AmpXSpectrumColumnModel.colorBand(segment: 11, count: count), 1)
        XCTAssertEqual(AmpXSpectrumColumnModel.colorBand(segment: 12, count: count), 2)
        XCTAssertEqual(AmpXSpectrumColumnModel.colorBand(segment: 15, count: count), 2)
    }
}
