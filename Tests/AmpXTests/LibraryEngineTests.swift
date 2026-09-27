@testable import AmpX
import SwiftData
import XCTest

/// Spec: "Start-up and cost", "Roots and security scope", scan triggers.
final class LibraryEngineTests: XCTestCase {
    private typealias T = LibraryTestSupport

    /// Records walked root folder names; every walk finds one file.
    private actor RecordingFileSystem: LibraryFileSystem {
        private(set) var walked: [String] = []

        func volume(at _: URL) async throws -> LibraryVolume {
            LibraryVolume(caseSensitive: true, typeName: "apfs")
        }

        func walk(root: URL, volume: LibraryVolume) async throws -> LibraryWalk {
            self.walked.append(root.lastPathComponent)
            return LibraryWalk(entries: [LibraryEntry(relativePath: "x.mp3", stat: T.stat(1, 1))], coverage: .complete, volume: volume)
        }

        func stat(at _: URL) async throws -> LibraryStat {
            T.stat(1, 1)
        }

        func fingerprint(at _: URL) async throws -> Data {
            Data([1])
        }

        func isReachable(_ root: URL) async -> Bool {
            FileManager.default.fileExists(atPath: root.path)
        }
    }

    private var directory: URL!
    private var storeURL: URL!
    private var log: EventLog!
    private var scope: ScopeSpy!
    private var flag: FlagSpy!
    private var fileSystem: RecordingFileSystem!
    private var engines: [LibraryEngine] = []

    override func setUpWithError() throws {
        self.directory = try T.temporaryDirectory(self)
        self.storeURL = self.directory.appendingPathComponent("Store/Library.store")
        self.log = EventLog()
        self.scope = ScopeSpy(log: self.log)
        self.flag = FlagSpy(log: self.log)
        self.fileSystem = RecordingFileSystem()
    }

    override func tearDown() async throws {
        for engine in self.engines {
            await engine.stop()
        }
    }

    // MARK: - Start-up

    func testFlagFalseOpensNoContainer() async throws {
        let engine = try await LibraryEngine.openIfConfigured(self.configuration())
        XCTAssertNil(engine)
        XCTAssertFalse(FileManager.default.fileExists(atPath: self.storeURL.path))
    }

    func testFlagTrueEmptyStoreSelfClears() async throws {
        self.flag.setHasRoots(true)
        let engine = try await LibraryEngine.openIfConfigured(self.configuration())
        XCTAssertNil(engine)
        XCTAssertFalse(self.flag.hasRoots)
        XCTAssertTrue(self.scope.openCounts.isEmpty)
    }

    func testStartupQueuesOneScanPerAvailableRoot() async throws {
        let first = try await self.open()
        _ = try await first.addRoot(url: self.folder("A"))
        _ = try await first.addRoot(url: self.folder("B"))
        await first.waitUntilIdle()
        await first.stop()
        self.engines.removeAll()
        try FileManager.default.removeItem(at: self.directory.appendingPathComponent("B"))

        let fileSystem = RecordingFileSystem()
        self.fileSystem = fileSystem
        let reopened = try await LibraryEngine.openIfConfigured(self.configuration())
        let engine = try XCTUnwrap(reopened)
        self.engines.append(engine)
        await engine.waitUntilIdle()
        let walked = await fileSystem.walked
        XCTAssertEqual(walked, ["A"])
        XCTAssertEqual(engine.watcher.activeStreamCount, 1)
        let roots = try await engine.roots()
        XCTAssertEqual(roots.map(\.isAvailable), [true, false])
    }

    // MARK: - Root operations

    func testAddScansAndPublishes() async throws {
        let engine = try await self.open()
        let versions = await engine.index.versions()
        _ = try await engine.index.query(LibraryQuery(), generation: 0) // build an (empty) snapshot
        _ = try await engine.addRoot(url: self.folder("DJ"))
        await engine.waitUntilIdle()
        // Root and row changes may land in one refetch or two (throttle); wait for the snapshot with the row.
        var rows = try await engine.index.query(LibraryQuery(), generation: 1).rows
        var iterator = versions.makeAsyncIterator()
        while rows.isEmpty, await iterator.next() != nil {
            rows = try await engine.index.query(LibraryQuery(), generation: 1).rows
        }
        XCTAssertEqual(rows.map(\.title), ["x"])
        XCTAssertEqual(engine.watcher.activeStreamCount, 1)
        XCTAssertTrue(self.flag.hasRoots)
    }

    func testRemoveCancelsScanAndUnbinds() async throws {
        let engine = try await self.open()
        let id = try await engine.addRoot(url: self.folder("DJ"))
        await engine.waitUntilIdle()
        try await engine.removeRoot(id: id)
        XCTAssertEqual(engine.watcher.activeStreamCount, 0)
        let roots = try await engine.roots()
        XCTAssertTrue(roots.isEmpty)
        XCTAssertFalse(self.flag.hasRoots)
        XCTAssertTrue(self.scope.openCounts.isEmpty)
    }

    func testRelocateRebindsAndRescans() async throws {
        let engine = try await self.open()
        let id = try await engine.addRoot(url: self.folder("Old"))
        await engine.waitUntilIdle()
        try await engine.relocateRoot(id: id, to: self.folder("New"))
        await engine.waitUntilIdle()
        let walked = await self.fileSystem.walked
        XCTAssertEqual(walked, ["Old", "New"])
        XCTAssertEqual(engine.watcher.activeStreamCount, 1)
    }

    // MARK: - Watch events

    func testChangedEventRequestsScan() async throws {
        let engine = try await self.open()
        let id = try await engine.addRoot(url: self.folder("DJ"))
        await engine.waitUntilIdle()
        await engine.handle(.changed(id))
        await engine.waitUntilIdle()
        let walked = await self.fileSystem.walked
        XCTAssertEqual(walked, ["DJ", "DJ"])
    }

    func testUnmountEventMarksRootsUnderVolumeUnavailable() async throws {
        let engine = try await self.open()
        let onVolume = try await engine.addRoot(url: self.folder("Volume/Crates"))
        let elsewhere = try await engine.addRoot(url: self.folder("Volume2/Crates"))
        await engine.waitUntilIdle()
        await engine.handle(.unmounted(self.directory.appendingPathComponent("Volume")))
        let roots = try await engine.roots()
        XCTAssertEqual(roots.first { $0.id == onVolume }?.isAvailable, false)
        XCTAssertEqual(roots.first { $0.id == elsewhere }?.isAvailable, true)
    }

    func testMountEventRescansUnavailableRoots() async throws {
        let engine = try await self.open()
        let id = try await engine.addRoot(url: self.folder("Volume/Crates"))
        await engine.waitUntilIdle()
        await engine.handle(.unmounted(self.directory.appendingPathComponent("Volume")))
        await engine.handle(.mounted(self.directory.appendingPathComponent("Volume")))
        await engine.waitUntilIdle()
        let roots = try await engine.roots()
        XCTAssertEqual(roots.first { $0.id == id }?.isAvailable, true)
        let walked = await self.fileSystem.walked
        XCTAssertEqual(walked, ["Crates", "Crates"])
    }

    func testRootChangedReResolves() async throws {
        let engine = try await self.open()
        let dj = try self.folder("DJ")
        let id = try await engine.addRoot(url: dj)
        await engine.waitUntilIdle()
        try FileManager.default.removeItem(at: dj)
        await engine.handle(.rootChanged(id))
        await engine.waitUntilIdle()
        let roots = try await engine.roots()
        XCTAssertEqual(roots.first?.isAvailable, false)
        XCTAssertEqual(engine.watcher.activeStreamCount, 0, "an unavailable root is not watched")
    }

    func testStopReleasesScopesWatchersAndTasks() async throws {
        let engine = try await self.open()
        _ = try await engine.addRoot(url: self.folder("A"))
        _ = try await engine.addRoot(url: self.folder("B"))
        await engine.waitUntilIdle()
        await engine.stop()
        XCTAssertEqual(engine.watcher.activeStreamCount, 0)
        XCTAssertTrue(self.scope.openCounts.isEmpty)
    }

    // MARK: - Helpers

    private func configuration() -> LibraryEngineConfiguration {
        let scope = self.scope!
        var configuration = LibraryEngineConfiguration(
            startupFlag: self.flag,
            bookmarkStore: SecurityScopedBookmarkStore(userDefaults: T.isolatedDefaults(self))
        )
        configuration.storeURL = self.storeURL
        configuration.fileSystem = self.fileSystem
        configuration.loadMetadata = FakeMetadataLoader().load
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

    private func folder(_ relative: String) throws -> URL {
        let url = self.directory.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
