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
}
