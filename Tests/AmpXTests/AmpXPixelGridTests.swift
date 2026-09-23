@testable import AmpX
import CoreGraphics
import XCTest

final class AmpXPixelGridTests: XCTestCase {
    func testAlignSnapsToHalfPointAt2x() {
        XCTAssertEqual(AmpXPixelGrid.align(0.26, backingScale: 2), 0.5)
    }

    func testStrokeRectEdgesAt1x() {
        let rect = AmpXPixelGrid.strokeRect(
            CGRect(x: 0, y: 0, width: 10, height: 10),
            lineWidth: 1,
            backingScale: 1
        )
        XCTAssertEqual(rect.minX, 0.5)
        XCTAssertEqual(rect.maxX, 9.5)
        XCTAssertEqual(rect.minY, 0.5)
        XCTAssertEqual(rect.maxY, 9.5)
    }

    func testStrokeRectEdgesAt2x() {
        let rect = AmpXPixelGrid.strokeRect(
            CGRect(x: 0, y: 0, width: 10, height: 10),
            lineWidth: 1,
            backingScale: 2
        )
        // 1 device pixel = 0.5 pt; half-width inset centers the stroke on a pixel boundary.
        XCTAssertEqual(rect.minX, 0.25)
        XCTAssertEqual(rect.maxX, 9.75)
    }

    func testStrokeRectEdgesAt3x() {
        let rect = AmpXPixelGrid.strokeRect(
            CGRect(x: 1, y: 2, width: 9, height: 8),
            lineWidth: 1,
            backingScale: 3
        )
        let half = 1.0 / 6.0
        XCTAssertEqual(rect.minX, 1 + half, accuracy: 1e-9)
        XCTAssertEqual(rect.maxX, 10 - half, accuracy: 1e-9)
        XCTAssertEqual(rect.minY, 2 + half, accuracy: 1e-9)
        XCTAssertEqual(rect.maxY, 10 - half, accuracy: 1e-9)
    }

    func testAlignAt1xAnd3x() {
        XCTAssertEqual(AmpXPixelGrid.align(1.26, backingScale: 1), 1.0)
        XCTAssertEqual(AmpXPixelGrid.align(1.26, backingScale: 3), 4.0 / 3.0)
    }
}
