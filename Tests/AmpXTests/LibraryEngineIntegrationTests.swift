@testable import AmpX
import SwiftData
import XCTest

/// The whole engine on real fixture files: real walk, real metadata loader, on-disk store, relaunch.
@MainActor
final class LibraryEngineIntegrationTests: XCTestCase {
    private typealias T = LibraryTestSupport

    /// Counts real loader calls so relaunch can prove unchanged files are not re-read.
    private final class CountingLoader: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var calls: Int {
            self.lock.withLock { self.count }
        }

        func reset() {
            self.lock.withLock { self.count = 0 }
        }

        var load: LibraryMetadataLoading {
            { url in
                self.lock.withLock { self.count += 1 }
                return await TrackMetadataLoader.load(from: url)
            }
        }
    }

    private var directory: URL!
    private var root: URL!
    private var loader: CountingLoader!
    private var scope: ScopeSpy!
    private var flag: FlagSpy!
    private var engines: [LibraryEngine] = []

    override func setUp() async throws {
        self.directory = try T.temporaryDirectory(self)
        self.root = self.directory.appendingPathComponent("DJ", isDirectory: true)
        let fixtures = try XCTUnwrap(Bundle(for: Self.self).resourceURL).appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        for name in ["tagged-v23.mp3", "tagged-v24.mp3", "tagged.flac", "tagged.wav", "tagged.aiff", "tagged.m4a", "title-only.mp3"] {
            let crate = name.hasPrefix("tagged") ? "Techno" : "Other"
            let destination = self.root.appendingPathComponent("\(crate)/\(name)")
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: fixtures.appendingPathComponent(name), to: destination)
        }
        self.loader = CountingLoader()
        let log = EventLog()
        self.scope = ScopeSpy(log: log)
        self.flag = FlagSpy(log: log)
    }

    override func tearDown() async throws {
        for engine in self.engines {
            await engine.stop()
        }
    }

    func testAddScanQueryEnqueueRelaunchRenameDeleteUnmount() async throws {
        // Add and scan.
        let engine = try await self.open()
        let rootID = try await engine.addRoot(url: self.root)
        await engine.waitUntilIdle()
        XCTAssertEqual(self.loader.calls, 7)

        var query = LibraryQuery()
        query.genres = [.text("Techno")]
        var result = try await engine.index.query(query, generation: 1)
        XCTAssertEqual(result.rows.count, 6)
        XCTAssertEqual(Set(result.rows.map(\.codec)), ["mp3", "flac", "wav", "aiff", "m4a"])
        XCTAssertTrue(result.rows.allSatisfy { $0.title == "Library Song" && $0.bpm == 130 && $0.musicalKey == "Am" })

        // Enqueue through the browser model.
        let audio = MockAudioPlayer()
        let bookmarks = SecurityScopedBookmarkStore(userDefaults: T.isolatedDefaults(self))
        let playlist = PlaylistManager(
            audioPlayer: audio, restoreBookmarks: false, restorePlaylist: false, bookmarkStore: bookmarks,
            stateStore: PlaylistStateStore(userDefaults: T.isolatedDefaults(self)), alertPresenter: SilentPlaylistAlertPresenter()
        )
        let model = LibraryBrowserModel(services: .live(engine), playlist: playlist, bookmarkStore: bookmarks, beep: {})
        defer { model.stop() }
        model.setQuery(query)
        await model.waitForRefresh()
        model.selection = Set(model.rows.map(\.id))
        await model.enqueue(append: false, clickedID: nil)
        XCTAssertEqual(playlist.tracks.count, 6)
        XCTAssertTrue(playlist.tracks.allSatisfy { $0.fileSize > 0 && $0.title == "Library Song" })
        XCTAssertEqual(audio.loadTrackCalls.count, 1)

        // Reserved fields to follow through rename.
        let renamedID = try XCTUnwrap(result.rows.first { $0.codec == "flac" }?.id)
        let context = ModelContext(engine.store.modelContainer)
        let track = try XCTUnwrap(try context.fetch(FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.id == renamedID })).first)
        track.playCount = 9
        track.rating = 5
        try context.save()

        // Relaunch: unchanged files are not re-read.
        await engine.stop()
        self.engines.removeAll()
        self.loader.reset()
        let relaunched = try await self.openIfConfigured()
        let reopened = try XCTUnwrap(relaunched)
        await reopened.waitUntilIdle()
        XCTAssertEqual(self.loader.calls, 0, "relaunch must not re-parse unchanged files")

        // Rename within the root keeps the row and its reserved fields.
        try FileManager.default.moveItem(
            at: self.root.appendingPathComponent("Techno/tagged.flac"),
            to: self.root.appendingPathComponent("Other/Renamed.flac")
        )
        await reopened.handle(.changed(rootID))
        await reopened.waitUntilIdle()
        let rows = try ModelContext(reopened.store.modelContainer).fetch(FetchDescriptor<LibraryTrack>())
        let moved = try XCTUnwrap(rows.first { $0.id == renamedID })
        XCTAssertEqual(moved.relativePath, "Other/Renamed.flac")
        XCTAssertEqual(moved.playCount, 9)
        XCTAssertEqual(moved.rating, 5)
        XCTAssertEqual(rows.count, 7)

        // Delete flags the row missing; unmount makes every row unavailable.
        try FileManager.default.removeItem(at: self.root.appendingPathComponent("Techno/tagged.wav"))
        await reopened.handle(.changed(rootID))
        await reopened.waitUntilIdle()
        var snapshot = try await self.rows(reopened, until: { $0.contains { !$0.isAvailable } })
        XCTAssertEqual(snapshot.filter { !$0.isAvailable }.map(\.codec), ["wav"])

        await reopened.handle(.unmounted(self.directory))
        snapshot = try await self.rows(reopened, until: { $0.allSatisfy { !$0.isAvailable } })
        XCTAssertTrue(snapshot.allSatisfy { !$0.isAvailable })
        XCTAssertEqual(snapshot.count, 7)
    }

    // MARK: - Helpers

    /// The index applies changes asynchronously: re-query on each new snapshot version until `condition` holds.
    private func rows(_ engine: LibraryEngine, until condition: ([LibraryRow]) -> Bool) async throws -> [LibraryRow] {
        let versions = await engine.index.versions()
        var rows = try await engine.index.query(LibraryQuery(), generation: 0).rows
        var iterator = versions.makeAsyncIterator()
        while !condition(rows), await iterator.next() != nil {
            rows = try await engine.index.query(LibraryQuery(), generation: 0).rows
        }
        return rows
    }

    private func configuration() -> LibraryEngineConfiguration {
        let scope = self.scope!
        var configuration = LibraryEngineConfiguration(
            startupFlag: self.flag,
            bookmarkStore: SecurityScopedBookmarkStore(userDefaults: T.isolatedDefaults(self))
        )
        configuration.storeURL = self.directory.appendingPathComponent("Store/Library.store")
        configuration.loadMetadata = self.loader.load
        configuration.watcherLatency = 0.1
        configuration.storeDependencies = { flag in
            var dependencies = LibraryStoreDependencies(startupFlag: flag)
            dependencies.scope = scope.scope
            dependencies.bookmarks = LibraryTestSupport.plainBookmarks
            return dependencies
        }
        return configuration
    }

    private func open() async throws -> LibraryEngine {
        let engine = try await LibraryEngine.open(self.configuration())
        self.engines.append(engine)
        return engine
    }

    private func openIfConfigured() async throws -> LibraryEngine? {
        let engine = try await LibraryEngine.openIfConfigured(self.configuration())
        if let engine {
            self.engines.append(engine)
        }
        return engine
    }
}
