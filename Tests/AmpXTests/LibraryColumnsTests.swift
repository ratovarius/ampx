@testable import AmpX
import XCTest

final class LibraryColumnsTests: XCTestCase {
    func testDefaultSetShowsCamelotHidesTextColumns() {
        XCTAssertEqual(LibraryColumnSet.default.visible, [.artist, .title, .genre, .time, .bpm, .key, .camelot, .kbps, .format])
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
        XCTAssertEqual(columns.visible, [.number, .artist, .title, .time, .bpm, .key, .camelot, .kbps, .format])
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

    func testDefaultColumnsFillMinimumWindowTable() {
        let table = LibraryModuleLayout.frames(size: CGSize(width: 910, height: 420)).table
        let frames = LibraryColumnSet.default.frames(width: table.width)
        XCTAssertEqual(frames.map(\.0), LibraryColumnSet.default.visible)
        XCTAssertEqual(frames.last.map(\.1.maxX) ?? 0, table.width, accuracy: 0.5)
        XCTAssertTrue(frames.allSatisfy { $0.1.width > 0 })
    }

    func testStoredL2SetGainsCamelotAfterKey() throws {
        let stored = Data(#"{"visible":["artist","title","bpm","key","format"]}"#.utf8)
        let columns = try JSONDecoder().decode(LibraryColumnSet.self, from: stored)
        XCTAssertEqual(columns.visible, [.artist, .title, .bpm, .key, .camelot, .format])
    }

    func testHiddenCamelotStaysHiddenAfterRoundTrip() throws {
        var columns = LibraryColumnSet.default
        columns.toggle(.camelot)
        let decoded = try JSONDecoder().decode(LibraryColumnSet.self, from: JSONEncoder().encode(columns))
        XCTAssertEqual(decoded, columns)
        XCTAssertFalse(decoded.visible.contains(.camelot))
    }

    func testNewColumnsMapToSorts() {
        XCTAssertEqual(LibraryColumn.camelot.sortColumn, .camelotKey)
        XCTAssertEqual(LibraryColumn.label.sortColumn, .label)
        XCTAssertEqual(LibraryColumn.remixer.sortColumn, .remixer)
        XCTAssertEqual(LibraryColumn.composer.sortColumn, .composer)
        XCTAssertEqual(LibraryColumn.grouping.sortColumn, .grouping)
        XCTAssertEqual(LibraryColumn.mix.sortColumn, .mix)
        XCTAssertEqual(LibraryColumn.camelot.title, "CAMELOT")
        XCTAssertEqual(LibraryColumn.grouping.title, "GROUPING")
        XCTAssertTrue(LibraryColumn.camelot.isHideable)
    }
}
