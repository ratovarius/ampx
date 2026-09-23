@testable import AmpX
import XCTest

@MainActor
final class PlaylistKeyboardAdapterTests: XCTestCase {
    private var manager: PlaylistManager!
    private var adapter: PlaylistKeyboardAdapter!

    override func setUp() {
        super.setUp()
        let player = MockAudioPlayer()
        self.manager = PlaylistManager(
            audioPlayer: player,
            restoreBookmarks: false,
            restorePlaylist: false,
            alertPresenter: SilentPlaylistAlertPresenter()
        )
        self.adapter = PlaylistKeyboardAdapter(manager: self.manager)
    }

    private func track(_ name: String) -> Track {
        Track(title: name, artist: "Artist", url: URL(fileURLWithPath: "/tmp/\(name).wav"))
    }

    func testRemoveSelectedTracksRemovesAndPrunesSelection() {
        let a = self.track("A")
        let b = self.track("B")
        self.manager.addTracks([a, b])
        self.adapter.selection.selectOnly(b.id)
        self.adapter.removeSelectedTracks()
        XCTAssertEqual(self.manager.tracks.map(\.id), [a.id])
        XCTAssertFalse(self.adapter.selection.selectedIDs.contains(b.id))
    }

    func testMoveSelectionUpdatesCursor() {
        let tracks = [self.track("A"), self.track("B"), self.track("C")]
        self.manager.addTracks(tracks)
        self.adapter.selection.selectOnly(tracks[0].id)
        self.adapter.moveSelection(by: 1, extend: false)
        XCTAssertEqual(self.adapter.selection.cursorID, tracks[1].id)
        XCTAssertEqual(self.adapter.selection.selectedIDs, [tracks[1].id])
    }

    func testMoveSelectionWithExtendGrowsRange() {
        let tracks = [self.track("A"), self.track("B"), self.track("C")]
        self.manager.addTracks(tracks)
        self.adapter.selection.selectOnly(tracks[0].id)
        self.adapter.moveSelection(by: 2, extend: true)
        XCTAssertEqual(self.adapter.selection.selectedIDs, Set(tracks[0 ... 2].map(\.id)))
    }

    func testCropToSelectionKeepsOnlySelectedTracks() {
        let tracks = [self.track("A"), self.track("B"), self.track("C")]
        self.manager.addTracks(tracks)
        self.adapter.selection.selectedIDs = [tracks[0].id, tracks[2].id]
        self.adapter.cropToSelection()
        XCTAssertEqual(self.manager.tracks.map(\.title), ["A", "C"])
    }

    func testSelectAllAndInvertSelection() {
        let tracks = [self.track("A"), self.track("B"), self.track("C")]
        self.manager.addTracks(tracks)
        self.adapter.selectAll()
        XCTAssertEqual(self.adapter.selection.selectedIDs.count, 3)
        self.adapter.invertSelection()
        XCTAssertTrue(self.adapter.selection.selectedIDs.isEmpty)
    }

    func testMoveSelectedTracksPreservesSelectionIDs() {
        let tracks = [self.track("A"), self.track("B"), self.track("C")]
        self.manager.addTracks(tracks)
        self.adapter.selection.selectedIDs = [tracks[0].id, tracks[1].id]
        self.adapter.selection.cursorID = tracks[1].id
        self.adapter.selection.anchorID = tracks[0].id
        self.adapter.moveSelectedTracks(by: 1)
        XCTAssertEqual(self.manager.tracks.map(\.title), ["C", "A", "B"])
        XCTAssertEqual(self.adapter.selection.selectedIDs, Set([tracks[0].id, tracks[1].id]))
        XCTAssertEqual(self.adapter.selection.cursorID, tracks[1].id)
    }

    func testPlaySelectedTrackUsesCursor() {
        let tracks = [self.track("A"), self.track("B")]
        self.manager.addTracks(tracks)
        self.adapter.selection.selectOnly(tracks[1].id)
        self.adapter.playSelectedTrack()
        XCTAssertEqual(self.manager.currentIndex, 1)
    }

    func testPageSelectionMovesByOneFifth() {
        let tracks = (0 ..< 10).map { self.track("T\($0)") }
        self.manager.addTracks(tracks)
        self.adapter.selection.selectOnly(tracks[0].id)
        self.adapter.pageSelection(direction: 1, extend: false)
        XCTAssertEqual(self.adapter.selection.cursorID, tracks[2].id)
    }

    func testClearSelectionEmptiesModel() {
        let track = self.track("A")
        self.manager.addTracks([track])
        self.adapter.selection.selectOnly(track.id)
        self.adapter.clearSelection()
        XCTAssertTrue(self.adapter.selection.selectedIDs.isEmpty)
    }
}
