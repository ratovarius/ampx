@testable import AmpX
import XCTest

@MainActor
final class PlaylistRowContextMenuTests: XCTestCase {
    private var player: MockAudioPlayer!
    private var manager: PlaylistManager!
    private var adapter: PlaylistKeyboardAdapter!

    /// XCTest's setUp() is nonisolated; create the NSView from a MainActor helper instead.
    override func setUp() {
        super.setUp()
        self.player = MockAudioPlayer()
        self.manager = PlaylistManager(
            audioPlayer: self.player,
            restoreBookmarks: false,
            restorePlaylist: false,
            alertPresenter: SilentPlaylistAlertPresenter()
        )
        self.adapter = PlaylistKeyboardAdapter(manager: self.manager)
    }

    private func makeRows() -> PlaylistRowsView {
        let rows = PlaylistRowsView(skin: ClassicModernSkin())
        rows.manager = self.manager
        rows.keyboardAdapter = self.adapter
        return rows
    }

    private func tracks(_ names: String...) -> [Track] {
        names.map { Track(title: $0, artist: "Artist", url: URL(fileURLWithPath: "/tmp/\($0).wav")) }
    }

    private func perform(_ title: String, in menu: NSMenu) throws {
        let index = menu.indexOfItem(withTitle: title)
        XCTAssertGreaterThanOrEqual(index, 0, "missing \(title)")
        guard index >= 0 else { throw XCTSkip("missing \(title)") }
        menu.performActionForItem(at: index)
    }

    func testMenuListsClassicRowActions() throws {
        let rows = self.makeRows()
        self.manager.addTracks(self.tracks("A"))
        let menu = try XCTUnwrap(rows.contextMenu(forTrackAt: 0))
        XCTAssertEqual(
            menu.items.map { $0.isSeparatorItem ? "-" : $0.title },
            ["Play", "Get Info", "-", "Remove from Playlist", "Remove from Disk…"]
        )
        XCTAssertNil(rows.contextMenu(forTrackAt: 1))
    }

    func testRightClickOnUnselectedRowSelectsOnlyThatRow() throws {
        let rows = self.makeRows()
        let tracks = self.tracks("A", "B", "C")
        self.manager.addTracks(tracks)
        self.adapter.selection.selectAll(orderedIDs: [tracks[0].id, tracks[1].id])
        _ = try XCTUnwrap(rows.contextMenu(forTrackAt: 2))
        XCTAssertEqual(self.adapter.selection.selectedIDs, [tracks[2].id])
    }

    func testRightClickInsideSelectionKeepsIt() throws {
        let rows = self.makeRows()
        let tracks = self.tracks("A", "B", "C")
        self.manager.addTracks(tracks)
        self.adapter.selection.selectAll(orderedIDs: [tracks[0].id, tracks[1].id])
        _ = try XCTUnwrap(rows.contextMenu(forTrackAt: 1))
        XCTAssertEqual(self.adapter.selection.selectedIDs, [tracks[0].id, tracks[1].id])
    }

    func testPlayStartsTheClickedTrack() throws {
        let rows = self.makeRows()
        self.manager.addTracks(self.tracks("A", "B"))
        let menu = try XCTUnwrap(rows.contextMenu(forTrackAt: 1))
        try self.perform("Play", in: menu)
        XCTAssertEqual(self.manager.currentIndex, 1)
    }

    func testRemoveFromPlaylistRemovesTheSelection() throws {
        let rows = self.makeRows()
        let tracks = self.tracks("A", "B", "C")
        self.manager.addTracks(tracks)
        self.adapter.selection.selectAll(orderedIDs: [tracks[0].id, tracks[1].id])
        let menu = try XCTUnwrap(rows.contextMenu(forTrackAt: 0))
        try self.perform("Remove from Playlist", in: menu)
        XCTAssertEqual(self.manager.tracks.map(\.id), [tracks[2].id])
        XCTAssertTrue(self.adapter.selection.selectedIDs.isEmpty)
    }

    func testRemoveFromDiskTrashesOnlyTheClickedTrackAfterConfirmation() throws {
        let rows = self.makeRows()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("context-trash-\(UUID().uuidString).wav")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data([0x00, 0x01]))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let keep = self.tracks("Keep")[0]
        self.manager.tracks = [keep, Track(title: "Trash", artist: "Artist", url: fileURL)]

        var confirmed: [URL] = []
        rows.confirmDiskRemoval = { url in
            confirmed.append(url)
            return false
        }
        try self.perform("Remove from Disk…", in: XCTUnwrap(rows.contextMenu(forTrackAt: 1)))
        XCTAssertEqual(confirmed, [fileURL])
        XCTAssertEqual(self.manager.tracks.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        rows.confirmDiskRemoval = { _ in true }
        try self.perform("Remove from Disk…", in: XCTUnwrap(rows.contextMenu(forTrackAt: 1)))
        XCTAssertEqual(self.manager.tracks.map(\.id), [keep.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(self.adapter.selection.selectedIDs.isEmpty)
    }
}
