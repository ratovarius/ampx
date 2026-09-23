@testable import AmpX
import XCTest

@MainActor
final class PlaylistManagerTests: XCTestCase {
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
        (0 ..< count).map { index in
            Track(title: "Track \(index)", artist: "Artist", url: URL(fileURLWithPath: "/tmp/\(index).mp3"))
        }
    }

    func testAddTrackDoesNotAutoPlay() {
        self.manager.addTrack(self.makeTracks(1)[0])
        waitForMainQueue(after: 0.2)
        XCTAssertEqual(self.manager.currentIndex, -1)
        XCTAssertEqual(self.mockPlayer.playCallCount, 0)
        XCTAssertEqual(self.mockPlayer.loadTrackCalls.count, 0)
    }

    func testAddTracksDoesNotAutoPlay() {
        self.manager.addTracks(self.makeTracks(3))
        waitForMainQueue(after: 0.2)
        XCTAssertEqual(self.manager.currentIndex, -1)
        XCTAssertEqual(self.mockPlayer.playCallCount, 0)
        XCTAssertEqual(self.mockPlayer.loadTrackCalls.count, 0)
    }

    func testRemoveTrackFromDiskMovesFileToTrashAndRemovesPlaylistEntry() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trash-\(UUID().uuidString).mp3")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data([0x00, 0x01]))
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        self.manager.tracks = [Track(title: "Trash Me", artist: "Artist", url: fileURL)]
        XCTAssertTrue(self.manager.removeTrackFromDisk(at: 0, confirm: { _ in true }))

        XCTAssertTrue(self.manager.tracks.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testNextSequentialAdvancesIndex() {
        self.manager.tracks = self.makeTracks(3)
        self.manager.currentIndex = 0
        self.manager.next()
        waitForMainQueue()
        XCTAssertEqual(self.manager.currentIndex, 1)
        XCTAssertEqual(self.mockPlayer.loadTrackCalls.count, 1)
        XCTAssertEqual(self.mockPlayer.playCallCount, 1)
    }

    func testTrackFinishedAtEndWithoutRepeatStops() {
        self.manager.tracks = self.makeTracks(2)
        self.manager.currentIndex = 1
        self.manager.advanceAfterTrackFinished()
        waitForMainQueue()
        XCTAssertEqual(self.mockPlayer.stopCallCount, 1)
        XCTAssertEqual(self.mockPlayer.playCallCount, 0)
    }

    func testTrackFinishedAtEndWithRepeatWraps() {
        self.manager.tracks = self.makeTracks(2)
        self.manager.currentIndex = 1
        self.manager.repeatEnabled = true
        self.manager.advanceAfterTrackFinished()
        waitForMainQueue()
        XCTAssertEqual(self.manager.currentIndex, 0)
        XCTAssertEqual(self.mockPlayer.playCallCount, 1)
    }

    func testManualNextAtEndWithoutRepeatWrapsToFirst() {
        self.manager.tracks = self.makeTracks(2)
        self.manager.currentIndex = 1
        self.manager.next()
        waitForMainQueue()
        XCTAssertEqual(self.manager.currentIndex, 0)
        XCTAssertEqual(self.mockPlayer.stopCallCount, 0)
        XCTAssertEqual(self.mockPlayer.playCallCount, 1)
    }

    func testManualShuffleNextPastEndStartsNewOrder() {
        self.manager.tracks = self.makeTracks(3)
        self.manager.currentIndex = 2
        self.manager.shuffleEnabled = true
        self.manager.test_setShuffledIndices([0, 1, 2], position: 2)
        self.manager.next()
        waitForMainQueue()
        XCTAssertEqual(self.mockPlayer.stopCallCount, 0)
        XCTAssertEqual(self.mockPlayer.playCallCount, 1)
        XCTAssertNotEqual(self.manager.currentIndex, 2, "new shuffle order should not replay the current track")
    }

    func testShuffleTrackFinishedAtEndWithoutRepeatStops() {
        self.manager.tracks = self.makeTracks(3)
        self.manager.currentIndex = 2
        self.manager.shuffleEnabled = true
        self.manager.test_setShuffledIndices([0, 1, 2], position: 2)
        self.manager.advanceAfterTrackFinished()
        waitForMainQueue()
        XCTAssertEqual(self.mockPlayer.stopCallCount, 1)
        XCTAssertEqual(self.mockPlayer.playCallCount, 0)
    }

    func testNextAtEndWithRepeatWraps() {
        self.manager.tracks = self.makeTracks(3)
        self.manager.currentIndex = 2
        self.manager.repeatEnabled = true
        self.manager.next()
        waitForMainQueue()
        XCTAssertEqual(self.manager.currentIndex, 0)
        XCTAssertEqual(self.mockPlayer.playCallCount, 1)
    }

    func testPreviousSequentialGoesBack() {
        self.manager.tracks = self.makeTracks(3)
        self.manager.currentIndex = 2
        self.manager.previous()
        waitForMainQueue()
        XCTAssertEqual(self.manager.currentIndex, 1)
        XCTAssertEqual(self.mockPlayer.playCallCount, 1)
    }

    func testPreviousAtStartWithoutRepeatStaysOnFirst() {
        self.manager.tracks = self.makeTracks(3)
        self.manager.currentIndex = 0
        self.manager.previous()
        waitForMainQueue()
        XCTAssertEqual(self.manager.currentIndex, 0)
        XCTAssertEqual(self.mockPlayer.playCallCount, 1)
        XCTAssertEqual(self.mockPlayer.loadTrackCalls.first?.title, "Track 0")
    }

    func testShuffleNextUsesShuffledOrder() {
        self.manager.tracks = self.makeTracks(4)
        self.manager.currentIndex = 0
        self.manager.shuffleEnabled = true
        self.manager.test_setShuffledIndices([0, 2, 1, 3], position: 0)
        self.manager.next()
        waitForMainQueue()
        XCTAssertEqual(self.manager.currentIndex, 2)
    }

    func testShufflePreviousAtStartWithoutRepeatDoesNothing() {
        self.manager.tracks = self.makeTracks(3)
        self.manager.currentIndex = 1
        self.manager.shuffleEnabled = true
        self.manager.test_setShuffledIndices([1, 0, 2], position: 0)
        self.manager.previous()
        waitForMainQueue()
        XCTAssertEqual(self.manager.currentIndex, 1)
        XCTAssertEqual(self.mockPlayer.playCallCount, 0)
    }

    func testRemoveTrackBeforeCurrentAdjustsIndex() {
        self.manager.tracks = self.makeTracks(3)
        self.manager.currentIndex = 2
        self.manager.removeTrack(at: 0)
        XCTAssertEqual(self.manager.currentIndex, 1)
        XCTAssertEqual(self.manager.tracks.count, 2)
    }

    func testRemoveCurrentTrackUpdatesIndexAndPlaysNext() {
        self.manager.tracks = self.makeTracks(3)
        self.manager.currentIndex = 1
        self.manager.removeTrack(at: 1)
        waitForMainQueue()
        XCTAssertEqual(self.manager.currentIndex, 1)
        XCTAssertEqual(self.manager.tracks[1].title, "Track 2")
        XCTAssertEqual(self.mockPlayer.loadTrackCalls.count, 1)
        XCTAssertEqual(self.mockPlayer.loadTrackCalls.first?.title, "Track 2")
        XCTAssertEqual(self.mockPlayer.playCallCount, 1)
    }

    func testClearPlaylistKeepsPlaying() {
        self.manager.tracks = self.makeTracks(2)
        self.manager.currentIndex = 0
        self.manager.clearPlaylist()
        XCTAssertTrue(self.manager.tracks.isEmpty)
        XCTAssertEqual(self.manager.currentIndex, -1)
        XCTAssertEqual(self.mockPlayer.stopCallCount, 0)
    }

    func testPlayTrackOnlyPlaysAfterSuccessfulLoad() {
        self.manager.tracks = self.makeTracks(1)
        self.mockPlayer.loadShouldSucceed = false
        self.manager.playTrack(at: 0)
        waitForMainQueue()
        XCTAssertEqual(self.mockPlayer.loadTrackCalls.count, 1)
        XCTAssertEqual(self.mockPlayer.playCallCount, 0)
        XCTAssertEqual(self.manager.currentIndex, -1)
    }

    func testPlayTrackFailedLoadPreservesPreviousIndex() {
        self.manager.tracks = self.makeTracks(3)
        self.manager.currentIndex = 1
        self.mockPlayer.loadShouldSucceed = false
        self.manager.playTrack(at: 2)
        waitForMainQueue()
        XCTAssertEqual(self.manager.currentIndex, 1)
        XCTAssertEqual(self.mockPlayer.playCallCount, 0)
    }

    func testPlayTrackFailedLoadRevertsOptimisticIndex() {
        self.manager.tracks = self.makeTracks(3)
        self.manager.currentIndex = 0
        self.mockPlayer.loadShouldSucceed = false
        self.manager.playTrack(at: 2)
        waitForMainQueue()
        XCTAssertEqual(self.manager.currentIndex, 0)
    }

    func testPlayTrackPlaysOnSuccessfulLoad() {
        self.manager.tracks = self.makeTracks(1)
        self.manager.playTrack(at: 0)
        waitForMainQueue()
        XCTAssertEqual(self.mockPlayer.playCallCount, 1)
    }

    func testRapidNextPlaysLatestRequestedTrack() {
        self.mockPlayer.loadCompletionDelay = 0.05
        self.manager.tracks = self.makeTracks(5)
        self.manager.currentIndex = 0
        self.manager.next()
        self.manager.next()
        self.manager.next()

        waitForMainQueue(after: 0.4)

        XCTAssertEqual(self.manager.currentIndex, 3)
        XCTAssertEqual(self.mockPlayer.loadTrackCalls.last?.title, "Track 3")
        XCTAssertEqual(self.mockPlayer.playCallCount, 1)
    }

    func testGenerateShuffledIndicesKeepsCurrentFirst() {
        self.manager.tracks = self.makeTracks(5)
        self.manager.currentIndex = 2
        self.manager.shuffleEnabled = true
        XCTAssertEqual(self.manager.test_shuffledIndices.first, 2)
        XCTAssertEqual(Set(self.manager.test_shuffledIndices), Set(0 ..< 5))
    }

    func testMoveTrackUpdatesCurrentIndex() {
        self.manager.tracks = self.makeTracks(4)
        self.manager.currentIndex = 2
        self.manager.moveTrack(from: 2, to: 0)
        XCTAssertEqual(self.manager.tracks[0].title, "Track 2")
        XCTAssertEqual(self.manager.currentIndex, 0)
    }

    func testMoveTrackShiftsCurrentIndexWhenMovingOtherRows() {
        self.manager.tracks = self.makeTracks(4)
        self.manager.currentIndex = 2
        self.manager.moveTrack(from: 0, to: 3)
        XCTAssertEqual(self.manager.currentIndex, 1)
    }

    func testPersistStateSavesTrackOrderAndModes() throws {
        let suiteName = "winamp-persist-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let stateStore = PlaylistStateStore(userDefaults: userDefaults)
        let manager = PlaylistManager(
            audioPlayer: mockPlayer,
            restoreBookmarks: false,
            restorePlaylist: false,
            stateStore: stateStore,
            alertPresenter: SilentPlaylistAlertPresenter()
        )

        manager.tracks = self.makeTracks(3)
        manager.currentIndex = 2
        manager.shuffleEnabled = true
        manager.repeatEnabled = true
        manager.persistStateForTests()

        let saved = try XCTUnwrap(stateStore.loadState())
        XCTAssertEqual(saved.trackPaths.count, 3)
        XCTAssertEqual(saved.currentIndex, 2)
        XCTAssertTrue(saved.shuffleEnabled)
        XCTAssertTrue(saved.repeatEnabled)
    }

    func testRestorePlaylistReloadsTracksWithoutAutoPlay() throws {
        let suiteName = "winamp-restore-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let bookmarkStore = SecurityScopedBookmarkStore(userDefaults: userDefaults)
        let stateStore = PlaylistStateStore(userDefaults: userDefaults)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("restore-\(UUID().uuidString).mp3")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data([0x00]))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        bookmarkStore.saveBookmark(for: fileURL)
        stateStore.saveState(PersistedPlaylistState(
            trackPaths: [fileURL.path],
            currentIndex: 0,
            shuffleEnabled: false,
            repeatEnabled: true
        ))

        let restoredBookmarkStore = SecurityScopedBookmarkStore(userDefaults: userDefaults)
        let manager = PlaylistManager(
            audioPlayer: mockPlayer,
            restoreBookmarks: true,
            restorePlaylist: true,
            bookmarkStore: restoredBookmarkStore,
            stateStore: stateStore,
            alertPresenter: SilentPlaylistAlertPresenter()
        )

        waitForMainQueue(after: 0.5)

        XCTAssertEqual(manager.tracks.count, 1)
        XCTAssertEqual(manager.currentIndex, 0)
        XCTAssertTrue(manager.repeatEnabled)
        XCTAssertEqual(self.mockPlayer.loadTrackCalls.count, 1)
        XCTAssertEqual(self.mockPlayer.playCallCount, 0)
        XCTAssertFalse(manager.shouldPlayStartupSoundOnLaunch)
    }

    func testShouldPlayStartupSoundOnLaunchWhenPlaylistEmpty() {
        let manager = PlaylistManager(
            audioPlayer: mockPlayer,
            restoreBookmarks: false,
            restorePlaylist: false,
            alertPresenter: SilentPlaylistAlertPresenter()
        )
        XCTAssertTrue(manager.shouldPlayStartupSoundOnLaunch)
    }

    func testShouldNotPlayStartupSoundAfterRestore() throws {
        let suiteName = "winamp-startup-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let bookmarkStore = SecurityScopedBookmarkStore(userDefaults: userDefaults)
        let stateStore = PlaylistStateStore(userDefaults: userDefaults)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("startup-restore-\(UUID().uuidString).mp3")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data([0x00]))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        bookmarkStore.saveBookmark(for: fileURL)
        stateStore.saveState(PersistedPlaylistState(
            trackPaths: [fileURL.path],
            currentIndex: 0,
            shuffleEnabled: false,
            repeatEnabled: false
        ))

        let manager = PlaylistManager(
            audioPlayer: mockPlayer,
            restoreBookmarks: true,
            restorePlaylist: true,
            bookmarkStore: SecurityScopedBookmarkStore(userDefaults: userDefaults),
            stateStore: stateStore,
            alertPresenter: SilentPlaylistAlertPresenter()
        )

        // Bookmark resolution is async; wait until the restored track lands.
        waitForMainQueue(after: 0.5)
        XCTAssertFalse(manager.tracks.isEmpty)
        XCTAssertFalse(manager.shouldPlayStartupSoundOnLaunch)
    }

    func testRestoreDropsMissingFilesButKeepsPresentTracks() throws {
        let suiteName = "winamp-restore-missing-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let bookmarkStore = SecurityScopedBookmarkStore(userDefaults: userDefaults)
        let stateStore = PlaylistStateStore(userDefaults: userDefaults)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("restore-present-\(UUID().uuidString).mp3")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data([0x00]))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        bookmarkStore.saveBookmark(for: fileURL)
        stateStore.saveState(PersistedPlaylistState(
            trackPaths: [fileURL.path, "/tmp/does-not-exist-\(UUID().uuidString).mp3"],
            currentIndex: 0,
            shuffleEnabled: false,
            repeatEnabled: false
        ))

        let manager = PlaylistManager(
            audioPlayer: mockPlayer,
            restoreBookmarks: true,
            restorePlaylist: true,
            bookmarkStore: SecurityScopedBookmarkStore(userDefaults: userDefaults),
            stateStore: stateStore,
            alertPresenter: SilentPlaylistAlertPresenter()
        )

        waitForMainQueue(after: 0.5)

        XCTAssertEqual(manager.tracks.count, 1)
        XCTAssertEqual(manager.tracks.first?.url?.path, fileURL.path)
        // Missing path is dropped from persistence once a partial restore succeeds.
        XCTAssertEqual(stateStore.loadState()?.trackPaths, [fileURL.path])
    }

    func testRestoreDoesNotWipePersistedPathsWhenNothingLoads() throws {
        let suiteName = "winamp-restore-empty-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let stateStore = PlaylistStateStore(userDefaults: userDefaults)
        let missing = "/tmp/does-not-exist-\(UUID().uuidString).mp3"
        stateStore.saveState(PersistedPlaylistState(
            trackPaths: [missing],
            currentIndex: 0,
            shuffleEnabled: false,
            repeatEnabled: false
        ))

        let manager = PlaylistManager(
            audioPlayer: mockPlayer,
            restoreBookmarks: true,
            restorePlaylist: true,
            bookmarkStore: SecurityScopedBookmarkStore(userDefaults: userDefaults),
            stateStore: stateStore,
            alertPresenter: SilentPlaylistAlertPresenter()
        )

        waitForMainQueue(after: 0.5)

        XCTAssertTrue(manager.tracks.isEmpty)
        // Failed restore must leave the saved list alone for a later retry.
        XCTAssertEqual(stateStore.loadState()?.trackPaths, [missing])
    }

    func testRestoreLoadsAllPresentTracks() throws {
        let suiteName = "winamp-restore-complete-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let bookmarkStore = SecurityScopedBookmarkStore(userDefaults: userDefaults)
        let stateStore = PlaylistStateStore(userDefaults: userDefaults)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("restore-complete-\(UUID().uuidString).mp3")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data([0x00]))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        bookmarkStore.saveBookmark(for: fileURL)
        stateStore.saveState(PersistedPlaylistState(
            trackPaths: [fileURL.path],
            currentIndex: 0,
            shuffleEnabled: false,
            repeatEnabled: false
        ))

        let manager = PlaylistManager(
            audioPlayer: mockPlayer,
            restoreBookmarks: true,
            restorePlaylist: true,
            bookmarkStore: SecurityScopedBookmarkStore(userDefaults: userDefaults),
            stateStore: stateStore,
            alertPresenter: SilentPlaylistAlertPresenter()
        )

        waitForMainQueue(after: 0.5)

        XCTAssertEqual(manager.tracks.count, 1)
        XCTAssertEqual(stateStore.loadState()?.trackPaths, [fileURL.path])
    }

    func testSaveM3UPlaylistSetsErrorMessageWhenWriteFails() {
        self.manager.tracks = self.makeTracks(1)
        let badURL = URL(fileURLWithPath: "/\(UUID().uuidString)/missing/playlist.m3u")

        self.manager.testing_saveM3UPlaylist(to: badURL)

        XCTAssertNotNil(self.manager.lastSaveErrorMessage)
    }

    func testSaveM3UPlaylistClearsErrorMessageOnSuccess() throws {
        self.manager.tracks = self.makeTracks(2)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("save-\(UUID().uuidString).m3u")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        self.manager.testing_saveM3UPlaylist(to: fileURL)

        XCTAssertNil(self.manager.lastSaveErrorMessage)
        let saved = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(saved.hasPrefix("#EXTM3U\n"))
        XCTAssertEqual(saved.components(separatedBy: "\n").filter { !$0.isEmpty }.count, 3)
    }

    func testSaveM3UUsesRelativePathsInsidePlaylistDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("m3u-relative-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let trackURL = directory.appendingPathComponent("song.mp3")
        FileManager.default.createFile(atPath: trackURL.path, contents: Data([0x00]))
        self.manager.tracks = [Track(title: "song", artist: "Artist", url: trackURL)]

        let playlistURL = directory.appendingPathComponent("playlist.m3u")
        self.manager.testing_saveM3UPlaylist(to: playlistURL)

        let saved = try String(contentsOf: playlistURL, encoding: .utf8)
        XCTAssertTrue(saved.contains("song.mp3"))
        XCTAssertFalse(saved.contains(directory.path))
    }

    func testM3UEntryUsesAbsolutePathOutsidePlaylistDirectory() {
        let playlistFile = URL(fileURLWithPath: "/tmp/playlists/list.m3u")
        let outsideTrack = URL(fileURLWithPath: "/Music/outside.mp3")
        XCTAssertEqual(
            self.manager.testing_m3uEntry(for: outsideTrack, relativeTo: playlistFile),
            outsideTrack.path
        )
    }

    func testRemoveTracksRemovesMultipleAndRemapsCurrent() {
        self.manager.tracks = self.makeTracks(5)
        self.manager.currentIndex = 3
        self.manager.removeTracks(at: IndexSet([1, 3]))
        XCTAssertEqual(self.manager.tracks.count, 3)
        XCTAssertEqual(self.manager.tracks.map(\.title), ["Track 0", "Track 2", "Track 4"])
        // Former index 3 removed while current — plays fallback at min removed slot.
        XCTAssertEqual(self.manager.currentIndex, 1)
    }

    func testCropToTracksKeepsOnlySelection() {
        self.manager.tracks = self.makeTracks(5)
        self.manager.currentIndex = 2
        self.manager.cropToTracks(at: IndexSet([1, 2, 4]))
        XCTAssertEqual(self.manager.tracks.map(\.title), ["Track 1", "Track 2", "Track 4"])
        XCTAssertEqual(self.manager.currentIndex, 1)
    }

    func testMoveSelectedTracksUpKeepsBlockOrder() {
        self.manager.tracks = self.makeTracks(5)
        self.manager.currentIndex = 2
        self.manager.moveSelectedTracks(indices: IndexSet([2, 3]), by: -1)
        XCTAssertEqual(self.manager.tracks.map(\.title), ["Track 0", "Track 2", "Track 3", "Track 1", "Track 4"])
        XCTAssertEqual(self.manager.currentIndex, 1)
    }

    func testSortTracksByTitlePreservesCurrentID() {
        self.manager.tracks = [
            Track(title: "C", artist: "A", url: URL(fileURLWithPath: "/tmp/c.mp3")),
            Track(title: "A", artist: "A", url: URL(fileURLWithPath: "/tmp/a.mp3")),
            Track(title: "B", artist: "A", url: URL(fileURLWithPath: "/tmp/b.mp3")),
        ]
        let currentID = self.manager.tracks[0].id
        self.manager.currentIndex = 0
        self.manager.sortTracks(by: .title)
        XCTAssertEqual(self.manager.tracks.map(\.title), ["A", "B", "C"])
        XCTAssertEqual(self.manager.tracks[self.manager.currentIndex].id, currentID)
    }

    func testReverseTracks() {
        self.manager.tracks = self.makeTracks(3)
        self.manager.currentIndex = 0
        let firstID = self.manager.tracks[0].id
        self.manager.reverseTracks()
        XCTAssertEqual(self.manager.tracks.map(\.title), ["Track 2", "Track 1", "Track 0"])
        XCTAssertEqual(self.manager.tracks[self.manager.currentIndex].id, firstID)
    }

    func testReplacePlaylistFromM3UReplacesTracks() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("winamp-replace-m3u-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let bundle = Bundle(for: PlaylistManagerTests.self)
        let wavURL = try XCTUnwrap(bundle.url(forResource: "short", withExtension: "wav"))
        let destWav = tempDirectory.appendingPathComponent("loaded-track.wav")
        try FileManager.default.copyItem(at: wavURL, to: destWav)

        let m3uContent = """
        #EXTM3U
        loaded-track.wav
        """
        let playlistURL = tempDirectory.appendingPathComponent("playlist.m3u")
        try m3uContent.write(to: playlistURL, atomically: true, encoding: .utf8)

        self.manager.tracks = self.makeTracks(3)
        self.manager.currentIndex = 1

        await self.manager.replacePlaylist(fromM3U: playlistURL)

        XCTAssertEqual(self.manager.tracks.count, 1)
        XCTAssertEqual(self.manager.tracks[0].url?.lastPathComponent, "loaded-track.wav")
        XCTAssertFalse(self.manager.tracks.contains { $0.title.hasPrefix("Track ") })
        XCTAssertEqual(self.manager.currentIndex, -1)
    }
}
