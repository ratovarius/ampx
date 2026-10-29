@testable import AmpX
import XCTest

/// DJ mode spec Revision 2 § What plays next: the Playlist's order, AUTO picks and the Automix hooks.
@MainActor
final class PlaylistAutomixTests: XCTestCase {
    private var mockPlayer: MockAudioPlayer!
    private var manager: PlaylistManager!

    override func setUp() {
        super.setUp()
        self.mockPlayer = MockAudioPlayer()
        self.manager = PlaylistManager(
            audioPlayer: self.mockPlayer,
            restoreBookmarks: false,
            restorePlaylist: false,
            alertPresenter: SilentPlaylistAlertPresenter()
        )
    }

    private func makeTracks(_ count: Int) -> [Track] {
        (0 ..< count).map { Track(title: "Track \($0)", artist: "Artist", url: URL(fileURLWithPath: "/tmp/automix-\($0).mp3")) }
    }

    private func load(_ count: Int, current: Int) {
        self.manager.addTracks(self.makeTracks(count))
        self.manager.currentIndex = current
    }

    func testNextTrackIndexSequential() {
        self.load(3, current: 0)
        XCTAssertEqual(self.manager.nextTrackIndex(), 1)
    }

    func testNextTrackIndexNilAtEndWithoutRepeat() {
        self.load(3, current: 2)
        XCTAssertNil(self.manager.nextTrackIndex())
    }

    func testNextTrackIndexWrapsWithRepeat() {
        self.load(3, current: 2)
        self.manager.repeatEnabled = true
        XCTAssertEqual(self.manager.nextTrackIndex(), 0)
    }

    func testNextTrackIndexFollowsShuffleOrderWithoutMutating() {
        self.load(4, current: 2)
        self.manager.shuffleEnabled = true
        self.manager.test_setShuffledIndices([2, 0, 3, 1], position: 0)
        XCTAssertEqual(self.manager.nextTrackIndex(), 0)
        XCTAssertEqual(self.manager.nextTrackIndex(), 0)
        XCTAssertEqual(self.manager.test_shuffleCurrentIndex, 0)
        self.manager.test_setShuffledIndices([2, 0, 3, 1], position: 3)
        XCTAssertNil(self.manager.nextTrackIndex())
    }

    func testAppendAutoTrackMarksIt() {
        self.load(2, current: 1)
        let pick = Track(title: "Pick", artist: "A", url: URL(fileURLWithPath: "/tmp/pick.mp3"))
        self.manager.appendAutoTrack(pick)
        XCTAssertEqual(self.manager.tracks.last?.id, pick.id)
        XCTAssertEqual(self.manager.autoTrackIDs, [pick.id])
        XCTAssertEqual(self.manager.nextTrackIndex(), 2)
    }

    func testRemovingAutoTrackRecordsURL() {
        let removals: [(PlaylistManager, Int) -> Void] = [
            { manager, index in manager.removeTrack(at: index) },
            { manager, index in manager.removeTracks(at: [index]) },
            { manager, index in manager.cropToTracks(at: IndexSet(integersIn: 0 ..< index)) },
            { manager, _ in manager.clearPlaylist() },
        ]
        for (number, remove) in removals.enumerated() {
            self.manager.clearPlaylist()
            self.load(2, current: 0)
            let url = URL(fileURLWithPath: "/tmp/pick-\(number).mp3")
            self.manager.appendAutoTrack(Track(title: "Pick", artist: "A", url: url))
            remove(self.manager, 2)
            XCTAssertTrue(self.manager.removedAutoURLs.contains(url), "removal path \(number)")
            XCTAssertTrue(self.manager.autoTrackIDs.isEmpty, "removal path \(number)")
        }
    }

    func testAdvanceToIncomingDoesNotLoad() {
        self.load(3, current: 0)
        let loads = self.mockPlayer.loadTrackCalls.count
        self.manager.advanceToIncoming(index: 1)
        XCTAssertEqual(self.manager.currentIndex, 1)
        XCTAssertEqual(self.mockPlayer.loadTrackCalls.count, loads)
    }

    func testAdvanceToIncomingMovesShufflePosition() {
        self.load(4, current: 2)
        self.manager.shuffleEnabled = true
        self.manager.test_setShuffledIndices([2, 0, 3, 1], position: 0)
        self.manager.advanceToIncoming(index: 0)
        XCTAssertEqual(self.manager.test_shuffleCurrentIndex, 1)
        XCTAssertEqual(self.manager.nextTrackIndex(), 3)
    }

    func testNextInterceptorShortCircuits() {
        self.load(3, current: 0)
        self.manager.nextInterceptor = { true }
        self.manager.next()
        XCTAssertEqual(self.manager.currentIndex, 0)
        XCTAssertTrue(self.mockPlayer.loadTrackCalls.isEmpty)
        self.manager.nextInterceptor = { false }
        self.manager.next()
        XCTAssertEqual(self.manager.currentIndex, 1)
    }

    func testPlaylistChangedEmits() {
        var count = 0
        let cancellable = self.manager.playlistChanged.sink { count += 1 }
        self.load(2, current: 0)
        self.manager.repeatEnabled = true
        XCTAssertGreaterThanOrEqual(count, 3)
        cancellable.cancel()
    }

    func testAutoTagRectSitsLeftOfDuration() {
        let row = CGRect(x: 0, y: 0, width: 275, height: 13)
        let tag = PlaylistRowLayout.autoTagRect(in: row)
        XCTAssertLessThan(tag.maxX, PlaylistRowLayout.durationRect(in: row).minX)
        XCTAssertGreaterThan(tag.minX, PlaylistRowLayout.titleRect(in: row).minX)
        XCTAssertEqual(tag.height, row.height)
    }

    /// Review finding 5: with Shuffle on, the continuation's pick plays next instead of a reshuffled old track.
    func testAutoPickIsNextInShuffleOrder() {
        self.load(3, current: 1)
        self.manager.shuffleEnabled = true
        self.manager.test_setShuffledIndices([0, 2, 1], position: 2)
        let pick = Track(title: "Pick", artist: "A", url: URL(fileURLWithPath: "/tmp/shuffle-pick.mp3"))
        self.manager.appendAutoTrack(pick)
        XCTAssertEqual(self.manager.nextTrackIndex(), 3)
        XCTAssertEqual(self.manager.test_shuffledIndices, [0, 2, 1, 3])
        XCTAssertEqual(self.manager.test_shuffleCurrentIndex, 2)
    }
}
