@testable import AmpX
import XCTest

final class LibraryColumnsTests: XCTestCase {
    func testDefaultHidesNumberOnly() {
        XCTAssertEqual(LibraryColumnSet.default.visible, [.artist, .title, .genre, .time, .bpm, .key, .kbps, .format])
    }

    func testTitleCannotBeHidden() {
        var columns = LibraryColumnSet.default
        columns.toggle(.title)
        XCTAssertTrue(columns.visible.contains(.title))
        XCTAssertFalse(LibraryColumn.title.isHideable)
    }

    func testToggleKeepsDisplayOrder() {
        var columns = LibraryColumnSet.default
        columns.toggle(.number)
        columns.toggle(.genre)
        XCTAssertEqual(columns.visible, [.number, .artist, .title, .time, .bpm, .key, .kbps, .format])
        columns.toggle(.genre)
        XCTAssertEqual(columns.visible.firstIndex(of: .genre), 3)
    }

    func testFramesHonourMinimumsAndFillWidth() throws {
        let frames = LibraryColumnSet.default.frames(width: 1400)
        XCTAssertEqual(frames.map(\.0), LibraryColumnSet.default.visible)
        XCTAssertEqual(frames.first?.1.minX, 0)
        XCTAssertEqual(frames.last.map(\.1.maxX) ?? 0, 1400, accuracy: 0.5)
        for (column, frame) in frames {
            XCTAssertGreaterThanOrEqual(frame.width, column.minimumWidth - 0.5, "\(column)")
        }
        for (previous, next) in zip(frames, frames.dropFirst()) {
            XCTAssertEqual(previous.1.maxX, next.1.minX, accuracy: 0.01)
        }
        // Only weighted columns (artist, title, genre) take the spare width.
        let time = try XCTUnwrap(frames.first { $0.0 == .time }?.1)
        XCTAssertEqual(time.width, LibraryColumn.time.minimumWidth, accuracy: 0.5)
    }

    func testFramesShrinkProportionallyBelowMinimums() {
        let frames = LibraryColumnSet.default.frames(width: 394)
        XCTAssertEqual(frames.last.map(\.1.maxX) ?? 0, 394, accuracy: 0.5)
        XCTAssertTrue(frames.allSatisfy { $0.1.width > 0 })
    }

    func testSortColumnMapping() {
        XCTAssertNil(LibraryColumn.number.sortColumn)
        XCTAssertNil(LibraryColumn.format.sortColumn)
        XCTAssertEqual(LibraryColumn.time.sortColumn, .duration)
        XCTAssertEqual(LibraryColumn.key.sortColumn, .musicalKey)
        XCTAssertEqual(LibraryColumn.kbps.sortColumn, .bitrate)
        XCTAssertEqual(LibraryColumn.column(for: .genre), .genre)
    }
}
