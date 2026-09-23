@testable import AmpX
import AppKit
import XCTest

@MainActor
final class AmpXCompactPlaylistTests: XCTestCase {
    func testLoadedIdentityReorderRemovalAndMetadataFallback() {
        let first = Track(title: "First", artist: "Artist", duration: 100)
        let loaded = Track(title: "God Damn", artist: "SLEAZE", duration: 226)
        XCTAssertEqual(
            AmpXCompactPlaylistSummary.make(loadedTrack: loaded, tracks: [first, loaded], loadedDuration: 227),
            .init(title: "2. SLEAZE - God Damn", duration: "3:47")
        )
        XCTAssertEqual(
            AmpXCompactPlaylistSummary.make(loadedTrack: loaded, tracks: [loaded, first], loadedDuration: 0).title,
            "1. SLEAZE - God Damn"
        )
        XCTAssertEqual(
            AmpXCompactPlaylistSummary.make(loadedTrack: loaded, tracks: [first], loadedDuration: .nan),
            .init(title: "SLEAZE - God Damn", duration: "3:46")
        )
        XCTAssertEqual(
            AmpXCompactPlaylistSummary.make(loadedTrack: nil, tracks: [first], loadedDuration: 227),
            .init(title: "NO TRACK", duration: "--:--")
        )
        let empty = Track(title: " \n ", artist: "", duration: .infinity)
        XCTAssertEqual(
            AmpXCompactPlaylistSummary.make(loadedTrack: empty, tracks: [], loadedDuration: -.infinity),
            .init(title: "Unknown Artist - Unknown Title", duration: "--:--")
        )
        XCTAssertEqual(
            AmpXCompactPlaylistSummary.make(loadedTrack: loaded, tracks: [], loadedDuration: 360_001).duration,
            "100:00:01"
        )
        XCTAssertEqual(
            AmpXCompactPlaylistSummary.make(loadedTrack: empty, tracks: [], loadedDuration: .greatestFiniteMagnitude).duration,
            "--:--"
        )
    }

    func testLongUnicodeTitleCannotEnterDurationColumn() {
        let track = Track(title: String(repeating: "東京🎵 café ", count: 30), artist: "Björk", duration: 360_001)
        let tracks = (0 ..< 999).map { Track(title: "\($0)", artist: "") } + [track]
        let summary = AmpXCompactPlaylistSummary.make(loadedTrack: track, tracks: tracks, loadedDuration: 0)
        XCTAssertTrue(summary.title.hasPrefix("1000. Björk - 東京"))
        for width: CGFloat in [490, 800] {
            let rect = CGRect(x: 90, y: 5, width: width - 200, height: 18)
            let durationWidth = AmpXLabel(text: summary.duration, color: .green, fontSize: 12).measuredSize(skin: ClassicModernSkin()).width
            let columns = AmpXCompactPlaylistSummary.textRects(in: rect, durationWidth: durationWidth)
            XCTAssertLessThan(columns.title.maxX, columns.duration.minX)
            XCTAssertEqual(columns.duration.width, durationWidth)
            XCTAssertEqual(columns.duration.maxX, rect.maxX)
        }
    }

    func testMenuUsesExistingSelectionAndActualCommands() throws {
        let manager = self.makeManager()
        let track = Track(title: "Selected", artist: "")
        manager.addTracks([track])
        let adapter = PlaylistKeyboardAdapter(manager: manager)
        adapter.selection.selectOnly(track.id)
        var selectionChanges = 0
        adapter.onSelectionChanged = { selectionChanges += 1 }
        let owner = PlaylistListOptionsMenu(manager: manager, keyboardAdapter: adapter)
        let menu = owner.makeMenu()
        XCTAssertEqual(menu.items.map(\.title), ["New List", "Save List…", "Load List…"])
        XCTAssertTrue(try XCTUnwrap(menu.item(withTitle: "Save List…")).isEnabled)
        guard menu.items.count == 3 else { return }
        for item in menu.items {
            XCTAssertIdentical(item.target as AnyObject?, owner)
            XCTAssertTrue(try NSApp.sendAction(XCTUnwrap(item.action), to: item.target, from: item))
        }
        XCTAssertTrue(manager.tracks.isEmpty)
        XCTAssertTrue(adapter.selection.selectedIDs.isEmpty)
        XCTAssertEqual(selectionChanges, 1)
        XCTAssertEqual(manager.saveCalls, 1)
        XCTAssertEqual(manager.loadCalls, 1)
    }

    func testSaveListDisabledWhenPlaylistEmpty() {
        let manager = self.makeManager()
        let adapter = PlaylistKeyboardAdapter(manager: manager)
        let menu = PlaylistListOptionsMenu(manager: manager, keyboardAdapter: adapter).makeMenu()
        XCTAssertFalse(try XCTUnwrap(menu.item(withTitle: "Save List…")).isEnabled)
    }

    func testObservedSummaryFollowsLoadedTrackAndDoesNotReuseOldDecodedDuration() async {
        let manager = self.makeManager()
        let audio = AudioPlayer(installRemoteCommands: false)
        let first = Track(title: "First", artist: "Artist", duration: 100)
        let second = Track(title: "Second", artist: "Artist", duration: 200)
        manager.addTracks([first, second])
        let adapter = PlaylistKeyboardAdapter(manager: manager)
        let owner = PlaylistListOptionsMenu(manager: manager, keyboardAdapter: adapter)
        let view = PlaylistCompactContent(skin: ClassicModernSkin(), manager: manager, audioPlayer: audio, listOptionsMenu: owner)
        audio.currentTrack = first
        audio.duration = 110
        await self.flushMainQueue()
        XCTAssertEqual(view.summary, .init(title: "1. Artist - First", duration: "1:50"))
        manager.currentIndex = 0
        adapter.selection.selectOnly(first.id)
        audio.currentTrack = second
        await self.flushMainQueue()
        XCTAssertEqual(view.summary, .init(title: "2. Artist - Second", duration: "3:20"), "Old decoded duration is invalid")
        audio.duration = 110 // Equal value is still a new track's decoded result.
        manager.moveTrack(from: 1, to: 0)
        await self.flushMainQueue()
        XCTAssertEqual(view.summary, .init(title: "1. Artist - Second", duration: "1:50"))
        adapter.selection.selectOnly(first.id)
        audio.pause()
        audio.stop()
        await self.flushMainQueue()
        XCTAssertEqual(view.summary.title, "1. Artist - Second")
        manager.clearPlaylist()
        await self.flushMainQueue()
        XCTAssertEqual(view.summary.title, "Artist - Second")
        XCTAssertEqual(view.listOptionsButton.accessibilityTitle, "List Options")
        XCTAssertTrue(view.listOptionsButton.isAccessibilityElement())
    }

    private func flushMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func makeManager() -> CompactPlaylistManagerSpy {
        let suite = "AmpXCompactPlaylistTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        self.addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return CompactPlaylistManagerSpy(
            audioPlayer: MockAudioPlayer(),
            restoreBookmarks: false,
            restorePlaylist: false,
            stateStore: PlaylistStateStore(userDefaults: defaults),
            alertPresenter: SilentPlaylistAlertPresenter()
        )
    }
}

@MainActor
private final class CompactPlaylistManagerSpy: PlaylistManager {
    var saveCalls = 0
    var loadCalls = 0
    override func saveM3UPlaylist() {
        self.saveCalls += 1
    }

    override func showLoadM3UPicker() {
        self.loadCalls += 1
    }
}
