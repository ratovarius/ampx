@testable import AmpX
import XCTest

final class PlaylistRowLayoutTests: XCTestCase {
    func testVisibleRangeWithOffset() {
        XCTAssertEqual(PlaylistRowLayout.visibleRange(offset: 22, viewport: 44, count: 10), 1 ..< 3)
    }

    func testVisibleRangeEmptyPlaylist() {
        XCTAssertEqual(PlaylistRowLayout.visibleRange(offset: 0, viewport: 100, count: 0), 0 ..< 0)
    }

    func testVisibleRangeIncludesPartialRows() {
        XCTAssertEqual(PlaylistRowLayout.visibleRange(offset: 10, viewport: 30, count: 5), 0 ..< 2)
    }

    func testRowRectReservesDurationColumn() {
        let rect = PlaylistRowLayout.rowRect(index: 2, width: 200)
        XCTAssertEqual(rect.origin.y, 44)
        XCTAssertEqual(rect.height, PlaylistRowLayout.rowHeight)
        XCTAssertEqual(rect.width, 200)
        XCTAssertEqual(PlaylistRowLayout.durationColumnWidth, 42)
    }
}
