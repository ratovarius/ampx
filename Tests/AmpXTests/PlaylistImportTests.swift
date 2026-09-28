@testable import AmpX
import XCTest

@MainActor
final class PlaylistImportTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUpWithError() throws {
        super.setUp()
        self.suiteName = "winamp-import-\(UUID().uuidString)"
        self.userDefaults = try XCTUnwrap(UserDefaults(suiteName: self.suiteName))
    }

    override func tearDown() {
        self.userDefaults.removePersistentDomain(forName: self.suiteName)
        super.tearDown()
    }

    func testImportDroppedURLSavesBookmarkAndAddsTrack() async {
        let store = SecurityScopedBookmarkStore(userDefaults: userDefaults)
        let mockPlayer = MockAudioPlayer()
        let manager = PlaylistManager(
            audioPlayer: mockPlayer,
            restoreBookmarks: false,
            restorePlaylist: false,
            bookmarkStore: store,
            alertPresenter: SilentPlaylistAlertPresenter()
        )

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("drop-\(UUID().uuidString).mp3")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data([0x00]))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        manager.importDroppedURL(fileURL)
        await waitForTrackCount(1, on: manager)

        XCTAssertEqual(manager.tracks.count, 1)
        XCTAssertEqual(manager.tracks.first?.url, fileURL)
        XCTAssertEqual(store.bookmarkCount, 1)
    }

    func testImportDroppedURLIgnoresUnsupportedExtension() {
        let mockPlayer = MockAudioPlayer()
        let manager = PlaylistManager(
            audioPlayer: mockPlayer,
            restoreBookmarks: false,
            restorePlaylist: false,
            alertPresenter: SilentPlaylistAlertPresenter()
        )

        let fileURL = URL(fileURLWithPath: "/tmp/clip.ogg")
        manager.importDroppedURL(fileURL)

        XCTAssertTrue(manager.tracks.isEmpty)
    }

    func testImportDroppedFolderAddsTracksFromSubfolders() async throws {
        let store = SecurityScopedBookmarkStore(userDefaults: userDefaults)
        let mockPlayer = MockAudioPlayer()
        let manager = PlaylistManager(
            audioPlayer: mockPlayer,
            restoreBookmarks: false,
            restorePlaylist: false,
            bookmarkStore: store,
            alertPresenter: SilentPlaylistAlertPresenter()
        )

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("drop-folder-\(UUID().uuidString)", isDirectory: true)
        let nested = folder.appendingPathComponent("disc-1", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let first = folder.appendingPathComponent("01.mp3")
        let second = nested.appendingPathComponent("02.wav")
        FileManager.default.createFile(atPath: first.path, contents: Data([0x00]))
        FileManager.default.createFile(atPath: second.path, contents: Data([0x00]))
        defer { try? FileManager.default.removeItem(at: folder) }

        manager.importDroppedURL(folder)

        await waitForTrackCount(2, on: manager)

        XCTAssertEqual(manager.tracks.count, 2)
        XCTAssertEqual(Set(manager.tracks.compactMap { $0.url?.lastPathComponent }), Set(["01.mp3", "02.wav"]))
        XCTAssertEqual(store.bookmarkCount, 1)
    }

    /// A Library drag of many rows: the root's bookmark already covers every file, so the drop saves no
    /// per-file bookmarks (each save re-resolves the whole store) and the tracks land in dropped order.
    func testDroppedFilesUnderScopedFolderAddInOrderWithoutPerFileBookmarks() async throws {
        let store = SecurityScopedBookmarkStore(userDefaults: userDefaults)
        let manager = PlaylistManager(
            audioPlayer: MockAudioPlayer(),
            restoreBookmarks: false,
            restorePlaylist: false,
            bookmarkStore: store,
            alertPresenter: SilentPlaylistAlertPresenter()
        )
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("drop-many-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = (0 ..< 40).map { folder.appendingPathComponent(String(format: "%02d.mp3", $0)) }
        for file in files {
            FileManager.default.createFile(atPath: file.path, contents: Data([0x00]))
        }
        store.saveBookmark(for: folder)
        XCTAssertEqual(store.bookmarkCount, 1)

        let dropped = Array(files.reversed())
        manager.importDroppedURLs(dropped)
        await waitForTrackCount(40, on: manager)

        XCTAssertEqual(manager.tracks.map(\.url), dropped)
        XCTAssertEqual(store.bookmarkCount, 1)
    }
}
