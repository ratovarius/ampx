@testable import AmpX
import XCTest

final class AmpXScopeLineLayoutTests: XCTestCase {
    private let rect = CGRect(x: 10, y: 20, width: 137.5, height: 41)

    func testColumnCountFollowsScopeWidth() {
        XCTAssertEqual(AmpXScopeLineLayout.columnCount(forWidth: 137.5), 138)
        XCTAssertEqual(AmpXScopeLineLayout.columnCount(forWidth: 40), 120, "clamps up to the scope minimum")
    }

    func testSilenceSitsOnTheVerticalCentre() throws {
        let points = AmpXScopeLineLayout.points(levels: [0, 0, 0], in: self.rect)

        XCTAssertEqual(points.count, 3)
        try XCTSkipIf(points.count != 3)
        for point in points {
            XCTAssertEqual(point.y, self.rect.midY, accuracy: 0.001)
        }
    }

    func testFullScaleReachesTopAndBottom() throws {
        let points = AmpXScopeLineLayout.points(levels: [1, -1], in: self.rect)

        XCTAssertEqual(points.count, 2)
        try XCTSkipIf(points.count != 2)
        XCTAssertEqual(points[0].y, self.rect.minY, accuracy: 0.001, "+1 is the top in flipped coordinates")
        XCTAssertEqual(points[1].y, self.rect.maxY, accuracy: 0.001)
    }

    func testLevelsBeyondFullScaleAreClamped() throws {
        let points = AmpXScopeLineLayout.points(levels: [4, -4], in: self.rect)

        XCTAssertEqual(points.count, 2)
        try XCTSkipIf(points.count != 2)
        XCTAssertEqual(points[0].y, self.rect.minY, accuracy: 0.001)
        XCTAssertEqual(points[1].y, self.rect.maxY, accuracy: 0.001)
    }

    func testPointsSpanTheFullWidth() throws {
        let points = AmpXScopeLineLayout.points(levels: [0, 0, 0, 0, 0], in: self.rect)

        XCTAssertEqual(points.count, 5)
        try XCTSkipIf(points.count != 5)
        XCTAssertEqual(points[0].x, self.rect.minX, accuracy: 0.001)
        XCTAssertEqual(points[4].x, self.rect.maxX, accuracy: 0.001)
        XCTAssertEqual(points[1].x, self.rect.minX + self.rect.width / 4, accuracy: 0.001)
    }

    /// With no samples yet (a parked or freshly cycled-to scope) a real oscilloscope still shows its
    /// zero line, so an empty input draws the flat centre line rather than an empty well.
    func testEmptyInputDrawsTheFlatCentreLine() throws {
        let points = AmpXScopeLineLayout.points(levels: [], in: self.rect)

        XCTAssertEqual(points.count, 2)
        try XCTSkipIf(points.count != 2)
        XCTAssertEqual(points[0], CGPoint(x: self.rect.minX, y: self.rect.midY))
        XCTAssertEqual(points[1], CGPoint(x: self.rect.maxX, y: self.rect.midY))
    }

    func testSingleSampleSitsAtTheLeftEdge() throws {
        let points = AmpXScopeLineLayout.points(levels: [0.5], in: self.rect)

        XCTAssertEqual(points.count, 1)
        try XCTSkipIf(points.count != 1)
        XCTAssertEqual(points[0].x, self.rect.minX, accuracy: 0.001)
        XCTAssertLessThan(points[0].y, self.rect.midY, "positive levels sit above the centre")
    }
}
