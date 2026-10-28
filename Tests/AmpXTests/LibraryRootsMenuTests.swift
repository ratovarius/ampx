@testable import AmpX
import XCTest

/// ROOTS ▾ menu (Library Module spec § Behaviour).
@MainActor
final class LibraryRootsMenuTests: XCTestCase {
    private func root(_ path: String, available: Bool = true, unreadable: Int = 0) -> LibraryRootSnapshot {
        LibraryRootSnapshot(
            id: UUID(), url: URL(fileURLWithPath: path, isDirectory: true), displayPath: path,
            isAvailable: available, unreadableFolderCount: unreadable, lastCompletedScanAt: nil
        )
    }

    func testRootsMenuItemsAndStatus() throws {
        let dj = self.root("/Users/me/Music/DJ")
        let archive = self.root("/Volumes/Archive", available: false)
        let crates = self.root("/Users/me/Crates", unreadable: 2)
        var added = 0
        var relocated: [UUID] = []
        var removed: [UUID] = []
        let menu = LibraryRootsMenu.make(
            roots: [dj, archive, crates],
            actions: .init(add: { added += 1 }, relocate: { relocated.append($0) }, remove: { removed.append($0) })
        )
        XCTAssertEqual(menu.items.map(\.title), ["Add Folder…", "", "DJ", "Archive", "Crates"])
        XCTAssertTrue(menu.items[1].isSeparatorItem)

        let djMenu = try XCTUnwrap(menu.items[2].submenu)
        XCTAssertEqual(djMenu.items.map(\.title), ["/Users/me/Music/DJ", "Available", "", "Relocate…", "Remove…"])
        XCTAssertFalse(djMenu.items[0].isEnabled)
        XCTAssertEqual(menu.items[3].submenu?.items[1].title, "Unavailable")
        XCTAssertEqual(menu.items[4].submenu?.items[1].title, "2 folders unreadable")

        menu.performActionForItem(at: 0)
        djMenu.performActionForItem(at: 3)
        djMenu.performActionForItem(at: 4)
        XCTAssertEqual(added, 1)
        XCTAssertEqual(relocated, [dj.id])
        XCTAssertEqual(removed, [dj.id])
    }

    func testEmptyRootsMenuOnlyAdds() {
        let menu = LibraryRootsMenu.make(roots: [], actions: .init(add: {}, relocate: { _ in }, remove: { _ in }))
        XCTAssertEqual(menu.items.map(\.title), ["Add Folder…"])
    }

    func testRemoveConfirmationText() {
        let text = LibraryRootsMenu.removeConfirmation(rootName: "DJ", trackCount: 2232)
        XCTAssertEqual(text.message, "Remove \"DJ\" from the library?")
        XCTAssertEqual(text.info, "Its 2,232 tracks and their ratings and play counts will be removed. The files are not deleted.")
        XCTAssertEqual(
            LibraryRootsMenu.removeConfirmation(rootName: "X", trackCount: 1).info,
            "Its 1 track and its rating and play count will be removed. The file is not deleted."
        )
    }

    // MARK: - rekordbox

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func source(
        _ rootID: UUID, present: Bool = true, matched: Int = 1, lastImport: Date? = Date(timeIntervalSince1970: 1_790_000_000)
    ) -> RekordboxSourceSnapshot {
        var report = RekordboxSyncReport(fileName: "collection.xml")
        report.matched = matched
        return RekordboxSourceSnapshot(
            rootID: rootID, fileName: "collection.xml", isPresent: present,
            stamp: RekordboxFileStamp(size: 1, modifiedAt: .distantPast), lastImportAt: lastImport,
            lastReport: report
        )
    }

    private func actions(viewed: @escaping (UUID) -> Void = { _ in }) -> LibraryRootsMenu.Actions {
        .init(add: {}, relocate: { _ in }, remove: { _ in }, viewRekordboxReport: viewed)
    }

    func testRootWithoutSourceHasNoRekordboxItems() throws {
        let dj = self.root("/Users/me/Music/DJ")
        let menu = LibraryRootsMenu.make(roots: [dj], rekordboxSources: [:], actions: self.actions())
        XCTAssertEqual(
            try XCTUnwrap(menu.items[2].submenu).items.map(\.title),
            ["/Users/me/Music/DJ", "Available", "", "Relocate…", "Remove…"]
        )
    }

    func testRootWithSourceShowsLineAndReportItem() throws {
        let dj = self.root("/Users/me/Music/DJ")
        var viewed: [UUID] = []
        let menu = LibraryRootsMenu.make(
            roots: [dj], rekordboxSources: [dj.id: self.source(dj.id)], actions: self.actions { viewed.append($0) }
        )
        let submenu = try XCTUnwrap(menu.items[2].submenu)
        XCTAssertEqual(
            submenu.items.map(\.title).prefix(4),
            ["/Users/me/Music/DJ", "Available", LibraryRootsMenu.rekordboxLine(self.source(dj.id)), "View rekordbox Report"]
        )
        XCTAssertFalse(submenu.items[2].isEnabled)
        submenu.performActionForItem(at: 3)
        XCTAssertEqual(viewed, [dj.id])
    }

    func testZeroMatchSourceHidden() throws {
        let dj = self.root("/Users/me/Music/DJ")
        let menu = LibraryRootsMenu.make(
            roots: [dj], rekordboxSources: [dj.id: self.source(dj.id, matched: 0)], actions: self.actions()
        )
        XCTAssertEqual(
            try XCTUnwrap(menu.items[2].submenu).items.map(\.title),
            ["/Users/me/Music/DJ", "Available", "", "Relocate…", "Remove…"]
        )
    }

    func testAbsentSourceHidden() throws {
        let dj = self.root("/Users/me/Music/DJ")
        let menu = LibraryRootsMenu.make(
            roots: [dj],
            rekordboxSources: [dj.id: self.source(dj.id, present: false)],
            actions: self.actions()
        )
        XCTAssertFalse(try XCTUnwrap(menu.items[2].submenu).items.map(\.title).contains("View rekordbox Report"))
    }

    func testRekordboxLineFormats() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let id = UUID()
        XCTAssertEqual(
            LibraryRootsMenu.rekordboxLine(self.source(id, lastImport: now.addingTimeInterval(-60)), now: now, calendar: self.utc),
            "rekordbox: collection.xml · synced 14:12"
        )
        XCTAssertEqual(
            LibraryRootsMenu.rekordboxLine(
                self.source(id, lastImport: Date(timeIntervalSince1970: 1_788_400_000)),
                now: now,
                calendar: self.utc
            ),
            "rekordbox: collection.xml · synced 3 Sep"
        )
        XCTAssertEqual(
            LibraryRootsMenu.rekordboxLine(self.source(id, lastImport: nil), now: now, calendar: self.utc),
            "rekordbox: collection.xml · not synced"
        )
    }

    func testRekordboxSectionNeedsAShownSource() {
        let dj = self.root("/Users/me/Music/DJ")
        let hidden = LibraryRootsMenu.make(roots: [dj], rekordboxSources: [dj.id: self.source(dj.id, matched: 0)], actions: self.actions())
        XCTAssertFalse(hidden.items.map(\.title).contains("Allow Access to rekordbox Analysis…"))
    }

    func testRekordboxSectionOffersAccess() throws {
        let dj = self.root("/Users/me/Music/DJ")
        var allowed = 0
        var actions = self.actions()
        actions.allowRekordboxAnalysis = { allowed += 1 }
        let menu = LibraryRootsMenu.make(roots: [dj], rekordboxSources: [dj.id: self.source(dj.id)], actions: actions)
        XCTAssertEqual(menu.items.last?.title, "Allow Access to rekordbox Analysis…")
        menu.performActionForItem(at: menu.items.count - 1)
        XCTAssertEqual(allowed, 1)

        let granted = LibraryRootsMenu.make(
            roots: [dj], rekordboxSources: [dj.id: self.source(dj.id)],
            rekordbox: LibraryRootsMenu.RekordboxState(analysisGranted: true), actions: actions
        )
        XCTAssertEqual(granted.items.last?.title, "Change rekordbox Analysis Folder…")
    }

    func testRekordboxTagItems() throws {
        let dj = self.root("/Users/me/Music/DJ")
        var events: [String] = []
        var actions = self.actions()
        actions.toggleTagWriting = { events.append("toggle") }
        actions.writeTagsForSelection = { events.append("selection") }
        var state = LibraryRootsMenu.RekordboxState()
        var menu = LibraryRootsMenu.make(roots: [dj], rekordboxSources: [dj.id: self.source(dj.id)], rekordbox: state, actions: actions)
        XCTAssertEqual(menu.items.map(\.title).suffix(4), [
            "", "Keep rekordbox Data in File Tags", "Write rekordbox Tags to Selected Tracks", "Allow Access to rekordbox Analysis…",
        ])
        let keep = try XCTUnwrap(menu.items.first { $0.title == "Keep rekordbox Data in File Tags" })
        XCTAssertEqual(keep.state, .off)
        XCTAssertFalse(try XCTUnwrap(menu.items.first { $0.title == "Write rekordbox Tags to Selected Tracks" }).isEnabled)

        state.tagWriting = true
        state.hasSelection = true
        menu = LibraryRootsMenu.make(roots: [dj], rekordboxSources: [dj.id: self.source(dj.id)], rekordbox: state, actions: actions)
        XCTAssertEqual(try XCTUnwrap(menu.items.first { $0.title == "Keep rekordbox Data in File Tags" }).state, .on)
        menu.performActionForItem(at: try XCTUnwrap(menu.items.firstIndex { $0.title == "Keep rekordbox Data in File Tags" }))
        menu.performActionForItem(at: try XCTUnwrap(menu.items.firstIndex { $0.title == "Write rekordbox Tags to Selected Tracks" }))
        XCTAssertEqual(events, ["toggle", "selection"])
    }
}
