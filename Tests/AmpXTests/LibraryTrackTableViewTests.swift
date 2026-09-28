@testable import AmpX
import XCTest

/// Library track table (Library Module spec § Layout, Behaviour).
@MainActor
final class LibraryTrackTableViewTests: XCTestCase {
    private let skin = ClassicModernSkin()
    private let rootID = UUID()

    private func row(
        _ id: Int,
        title: String = "Song",
        bpm: Double? = 128,
        key: String? = "Am",
        bitrate: Int = 320_000,
        derived: Bool = false,
        available: Bool = true
    ) -> LibraryRow {
        LibraryRow(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))!,
            rootID: self.rootID, url: URL(fileURLWithPath: "/Music/DJ/\(id).mp3"),
            title: title, artist: "Artist \(id)", album: "", albumArtist: "",
            genre: "Techno", trackNumber: nil, duration: 402, fileSize: 1000,
            bpm: bpm, musicalKey: key, bitrate: bitrate, bitrateIsDerived: derived, codec: "mp3",
            isAvailable: available, searchKey: ""
        )
    }

    private func makeTable(rows count: Int = 100) -> LibraryTrackTableView {
        let table = LibraryTrackTableView(skin: self.skin)
        table.frame = CGRect(x: 0, y: 0, width: 600, height: LibraryTrackTableView.headerHeight + 22 * 10)
        table.rows = (1 ... max(1, count)).prefix(count).map { self.row($0) }
        return table
    }

    func testVisibleRowRangeOnly() {
        let table = self.makeTable(rows: 11000)
        XCTAssertEqual(table.visibleRowRange, 0 ..< 10)
        table.scroll(to: 22 * 500)
        XCTAssertEqual(table.visibleRowRange, 500 ..< 510)
        table.scroll(to: .greatestFiniteMagnitude)
        XCTAssertEqual(table.visibleRowRange.upperBound, 11000, "scrolling clamps to the last row")
    }

    func testHeaderClickReportsSort() throws {
        let table = self.makeTable()
        var sorted: [LibrarySortColumn] = []
        table.onSortClick = { sorted.append($0) }
        let frames = table.columnFrames()
        let bpm = try XCTUnwrap(frames.first { $0.0 == .bpm }?.1)
        table.handleHeaderClick(atX: bpm.midX)
        let format = try XCTUnwrap(frames.first { $0.0 == .format }?.1)
        table.handleHeaderClick(atX: format.midX)
        XCTAssertEqual(sorted, [.bpm], "FORMAT is not sortable")
    }

    func testHeaderMenuListsHideableColumnsWithState() {
        let table = self.makeTable()
        var changed: LibraryColumnSet?
        table.onColumnsChange = { changed = $0 }
        let menu = table.headerMenu()
        XCTAssertEqual(menu.items.map(\.title), ["#", "ARTIST", "GENRE", "TIME", "BPM", "KEY", "KBPS", "FORMAT"])
        XCTAssertEqual(menu.items.first?.state, .off)
        XCTAssertEqual(menu.items[1].state, .on)
        menu.performActionForItem(at: 0)
        XCTAssertEqual(changed?.visible.first, .number)
    }

    func testCellTextTruncatesWithinColumn() {
        let long = "Sébastien Léger – Mirage (Extended Mix) [Remastered 2024 Edition]"
        let fitted = LibraryTrackTableView.fittedText(long, width: 120, skin: self.skin)
        XCTAssertTrue(fitted.hasSuffix("…"))
        XCTAssertTrue(long.hasPrefix(String(fitted.dropLast())))
        XCTAssertLessThanOrEqual(LibraryTrackTableView.textWidth(fitted, skin: self.skin), 120)
        XCTAssertEqual(LibraryTrackTableView.fittedText("Short", width: 120, skin: self.skin), "Short")
        XCTAssertEqual(LibraryTrackTableView.fittedText(long, width: 4, skin: self.skin), "")
    }

    func testCellFormatting() {
        let table = self.makeTable(rows: 0)
        XCTAssertEqual(table.cellText(.bpm, row: self.row(1, bpm: nil), index: 0), "—")
        XCTAssertEqual(table.cellText(.key, row: self.row(1, key: nil), index: 0), "—")
        XCTAssertEqual(table.cellText(.bpm, row: self.row(1, bpm: 127.5), index: 0), "127.5")
        XCTAssertEqual(table.cellText(.bpm, row: self.row(1, bpm: 128), index: 0), "128")
        XCTAssertEqual(table.cellText(.kbps, row: self.row(1, bitrate: 243_400, derived: true), index: 0), "~243")
        XCTAssertEqual(table.cellText(.kbps, row: self.row(1, bitrate: 0), index: 0), "—")
        XCTAssertEqual(table.cellText(.time, row: self.row(1), index: 0), "6:42")
        XCTAssertEqual(table.cellText(.format, row: self.row(1), index: 0), "MP3")
        XCTAssertEqual(table.cellText(.number, row: self.row(1), index: 41), "42")
    }

    func testClickShiftCommandSelection() {
        let table = self.makeTable()
        var reported: LibrarySelection?
        table.onSelectionChange = { reported = $0 }
        table.handleRowClick(atY: 22 * 2 + 5, modifiers: [], clickCount: 1)
        table.handleRowClick(atY: 22 * 4 + 5, modifiers: .shift, clickCount: 1)
        XCTAssertEqual(reported?.ids.count, 3)
        table.handleRowClick(atY: 22 * 3 + 5, modifiers: .command, clickCount: 1)
        XCTAssertEqual(reported?.ids.count, 2)
        XCTAssertEqual(table.selection, reported ?? LibrarySelection())
    }

    func testDoubleClickActivates() {
        let table = self.makeTable(rows: 3)
        var activated: UUID?
        table.onActivate = { activated = $0 }
        table.handleRowClick(atY: 22 * 1 + 5, modifiers: [], clickCount: 2)
        XCTAssertEqual(activated, table.rows[1].id)
        table.handleRowClick(atY: 22 * 50, modifiers: [], clickCount: 2)
        XCTAssertEqual(activated, table.rows[1].id, "a click below the last row does nothing")
    }

    func testDragPasteboardHasAvailableURLsOnly() {
        let table = LibraryTrackTableView(skin: self.skin)
        table.rows = [self.row(1), self.row(2, available: false), self.row(3)]
        var selection = LibrarySelection()
        selection.selectAll(order: table.rows.map(\.id))
        table.selection = selection
        XCTAssertEqual(table.draggedRows(fromRowAt: 0).map(\.url.lastPathComponent), ["1.mp3", "3.mp3"])
        var single = LibrarySelection()
        single.click(table.rows[0].id, order: table.rows.map(\.id))
        table.selection = single
        XCTAssertEqual(table.draggedRows(fromRowAt: 2).map(\.url.lastPathComponent), ["3.mp3"], "a row outside the selection drags alone")
        XCTAssertTrue(table.draggedRows(fromRowAt: 1).isEmpty, "an unavailable row does not drag")
    }

    func testAccessibilityRowsAndSelection() throws {
        let table = self.makeTable(rows: 30)
        var reported: LibrarySelection?
        table.onSelectionChange = { reported = $0 }
        XCTAssertEqual(table.accessibilityRole(), .table)
        let children = try XCTUnwrap(table.accessibilityChildren() as? [NSAccessibilityElement])
        XCTAssertEqual(children.count, 10, "visible rows only")
        XCTAssertEqual(children[0].accessibilityLabel(), "Artist 1, Song, 6:42, 128 BPM")
        children[2].setAccessibilitySelected(true)
        XCTAssertEqual(reported?.ids, [table.rows[2].id])
        XCTAssertEqual(children[2].isAccessibilitySelected(), true)
    }
}
