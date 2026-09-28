@testable import AmpX
import XCTest

/// Spec "Performance targets" and success criteria 2–4, measured on the real engine in the sandboxed host.
/// The `~/Music/DJ` run is opt-in: `TEST_RUNNER_AMPX_LIBRARY_GATE=1`. Results attach as `LIBRARY-GATE-*`.
@MainActor
final class LibraryPerformanceTests: XCTestCase {
    private typealias T = LibraryTestSupport

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var loads = 0
        private var fingerprints = 0

        var loadCount: Int {
            self.lock.withLock { self.loads }
        }

        var fingerprintCount: Int {
            self.lock.withLock { self.fingerprints }
        }

        func reset() {
            self.lock.withLock {
                self.loads = 0
                self.fingerprints = 0
            }
        }

        func countLoad() {
            self.lock.withLock { self.loads += 1 }
        }

        func countFingerprint() {
            self.lock.withLock { self.fingerprints += 1 }
        }
    }

    /// Real file system, counting content reads.
    private struct CountingFileSystem: LibraryFileSystem {
        let base = FoundationLibraryFileSystem()
        let counter: Counter

        func volume(at root: URL) async throws -> LibraryVolume {
            try await self.base.volume(at: root)
        }

        func walk(root: URL, volume: LibraryVolume) async throws -> LibraryWalk {
            try await self.base.walk(root: root, volume: volume)
        }

        func stat(at url: URL) async throws -> LibraryStat {
            try await self.base.stat(at: url)
        }

        func fingerprint(at url: URL) async throws -> Data {
            self.counter.countFingerprint()
            return try await self.base.fingerprint(at: url)
        }

        func isReachable(_ root: URL) async -> Bool {
            await self.base.isReachable(root)
        }
    }

    private struct CollectionReport: Encodable {
        var files = 0
        var firstScanSeconds = 0.0
        var noChangeRescanSeconds = 0.0
        var rescanLoads = 0
        var rescanFingerprints = 0
        var searchDuringScanMaxMs = 0.0
        var searchDuringScanSamples = 0
        var rowsVisibleDuringScan: [Int] = []
        var searchIdleMaxMs = 0.0
        var availabilityMs = 0.0
        var crates: [String: Int] = [:]
        var genreFacets: [String: Int] = [:]
    }

    private var engines: [LibraryEngine] = []
    private var models: [LibraryBrowserModel] = []

    override func tearDown() async throws {
        self.models.forEach { $0.stop() }
        for engine in self.engines {
            await engine.stop()
        }
    }

    func testRealCollectionBudgets() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["AMPX_LIBRARY_GATE"] == "1",
            "Set TEST_RUNNER_AMPX_LIBRARY_GATE=1 to measure ~/Music/DJ"
        )
        let home = try String(cString: XCTUnwrap(getpwuid(getuid())).pointee.pw_dir)
        let dj = URL(fileURLWithPath: home).appendingPathComponent("Music/DJ", isDirectory: true)
        let counter = Counter()
        let engine = try await self.engine(counter: counter, loader: { url in
            counter.countLoad()
            return await TrackMetadataLoader.load(from: url)
        })
        let model = self.model(engine)
        var report = CollectionReport()

        // First scan, with searches issued while it runs.
        let scanStart = ContinuousClock.now
        let rootID = try await engine.addRoot(url: dj)
        let scanning = Task { await engine.waitUntilIdle() }
        // Sample only while the snapshot is partially filled: the scan is running and saving batches.
        let terms = ["techno", "house", "mix", "original", "remix", "a", "deep", "trance"]
        while report.searchDuringScanSamples < 40 {
            let visible = try await engine.index.query(LibraryQuery(), generation: 0).rows.count
            if visible >= 2232 {
                break
            }
            guard visible > 0 else {
                await Task.yield()
                continue
            }
            for term in terms {
                let elapsed = await self.searchMilliseconds(model, term)
                report.searchDuringScanMaxMs = max(report.searchDuringScanMaxMs, elapsed)
                report.searchDuringScanSamples += 1
            }
            report.rowsVisibleDuringScan.append(visible)
        }
        await scanning.value
        report.firstScanSeconds = (ContinuousClock.now - scanStart) / .seconds(1)

        // Success criterion 2: every crate folder is a genre facet with that folder's file count.
        report.crates = try self.crateCounts(dj)
        let facets = try await engine.index.query(LibraryQuery(), generation: 0).facets.genres
        report.genreFacets = Dictionary(uniqueKeysWithValues: facets.map { key, count in
            if case let .text(name) = key {
                (name, count)
            } else {
                ("(No Genre)", count)
            }
        })
        report.files = report.crates.values.reduce(0, +)
        XCTAssertEqual(report.files, 2232)
        XCTAssertEqual(report.crates.count, 18)
        XCTAssertEqual(report.genreFacets, report.crates, "genre facets must equal crate folders and their counts")

        // No-change rescan: stat-only.
        counter.reset()
        let rescanStart = ContinuousClock.now
        await engine.scanner.requestScan(rootID: rootID)
        await engine.waitUntilIdle()
        report.noChangeRescanSeconds = (ContinuousClock.now - rescanStart) / .seconds(1)
        report.rescanLoads = counter.loadCount
        report.rescanFingerprints = counter.fingerprintCount

        // Idle search.
        for term in ["techno", "house", "mix", "original", "remix", "a", "deep", "trance"] {
            report.searchIdleMaxMs = await max(report.searchIdleMaxMs, self.searchMilliseconds(model, term))
        }

        // Availability: store save → browser rows unavailable.
        model.setQuery(LibraryQuery())
        await model.waitForRefresh()
        let availabilityStart = ContinuousClock.now
        try await engine.store.markUnavailable(id: rootID)
        while model.rows.contains(where: \.isAvailable) {
            await Task.yield()
        }
        report.availabilityMs = (ContinuousClock.now - availabilityStart) / .milliseconds(1)

        self.emitGate("collection", report)
        XCTAssertLessThan(report.firstScanSeconds, 60)
        XCTAssertLessThan(report.noChangeRescanSeconds, 2)
        XCTAssertEqual(report.rescanLoads, 0)
        XCTAssertEqual(report.rescanFingerprints, 0)
        XCTAssertGreaterThan(report.searchDuringScanSamples, 0, "no search ran while the scan was filling the index")
        XCTAssertLessThan(report.searchDuringScanMaxMs, 100)
        XCTAssertLessThan(report.searchIdleMaxMs, 100)
        XCTAssertLessThan(report.availabilityMs, 100)
    }

    func testNoChangeRescan11kUnderFiveSeconds() async throws {
        try AmpXTestEnvironment.skipOnCI("writes 11,000 files; on a runner it takes minutes and starves the parallel test worker")
        let root = try T.temporaryDirectory(self).appendingPathComponent("Archive", isDirectory: true)
        let payload = Data(repeating: 1, count: 1024)
        for folder in 0 ..< 110 {
            let folderURL = root.appendingPathComponent("crate-\(folder)", isDirectory: true)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            for file in 0 ..< 100 {
                try payload.write(to: folderURL.appendingPathComponent("track-\(file).mp3"))
            }
        }
        let counter = Counter()
        let engine = try await self.engine(counter: counter, loader: { url in
            counter.countLoad()
            var metadata = TrackMetadataLoader.Metadata(title: url.lastPathComponent, artist: "Artist", duration: 1, fileSize: 1024)
            metadata.codec = "mp3"
            return metadata
        })
        let firstStart = ContinuousClock.now
        let rootID = try await engine.addRoot(url: root)
        await engine.waitUntilIdle()
        let firstSeconds = (ContinuousClock.now - firstStart) / .seconds(1)
        XCTAssertEqual(counter.loadCount, 11000)

        counter.reset()
        let start = ContinuousClock.now
        await engine.scanner.requestScan(rootID: rootID)
        await engine.waitUntilIdle()
        let seconds = (ContinuousClock.now - start) / .seconds(1)
        self.emitGate("rescan11k", ["firstScanSeconds": firstSeconds, "noChangeRescanSeconds": seconds])
        if AmpXTestEnvironment.enforcesTimeBudgets {
            XCTAssertLessThan(seconds, 5)
        }
        XCTAssertEqual(counter.loadCount, 0)
        XCTAssertEqual(counter.fingerprintCount, 0)
    }

    // MARK: - Helpers

    private func searchMilliseconds(_ model: LibraryBrowserModel, _ term: String) async -> Double {
        let start = ContinuousClock.now
        model.setQuery(LibraryQuery(search: term))
        await model.waitForRefresh()
        return (ContinuousClock.now - start) / .milliseconds(1)
    }

    private func crateCounts(_ root: URL) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for crate in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            where !FoundationLibraryFileSystem.reservedFolders.contains(crate.lastPathComponent)
        {
            let files = FileManager.default.enumerator(at: crate, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])?
                .compactMap { $0 as? URL }
                .filter { M3UParser.isSupportedAudioExtension($0.pathExtension) } ?? []
            if !files.isEmpty {
                counts[crate.lastPathComponent] = files.count
            }
        }
        return counts
    }

    private func engine(counter: Counter, loader: @escaping LibraryMetadataLoading) async throws -> LibraryEngine {
        let log = EventLog()
        let scope = ScopeSpy(log: log)
        var configuration = LibraryEngineConfiguration(
            startupFlag: FlagSpy(log: log),
            bookmarkStore: SecurityScopedBookmarkStore(userDefaults: T.isolatedDefaults(self))
        )
        configuration.storeURL = nil
        configuration.fileSystem = CountingFileSystem(counter: counter)
        configuration.loadMetadata = loader
        configuration.storeDependencies = { flag in
            var dependencies = LibraryStoreDependencies(startupFlag: flag)
            dependencies.scope = scope.scope
            dependencies.bookmarks = LibraryTestSupport.plainBookmarks
            return dependencies
        }
        let engine = try await LibraryEngine.open(configuration)
        self.engines.append(engine)
        return engine
    }

    private func model(_ engine: LibraryEngine) -> LibraryBrowserModel {
        let playlist = PlaylistManager(
            audioPlayer: MockAudioPlayer(), restoreBookmarks: false, restorePlaylist: false,
            stateStore: PlaylistStateStore(userDefaults: T.isolatedDefaults(self)), alertPresenter: SilentPlaylistAlertPresenter()
        )
        let model = LibraryBrowserModel(services: .live(engine), playlist: playlist, bookmarkStore: engine.bookmarkStore, beep: {})
        self.models.append(model)
        return model
    }
}
