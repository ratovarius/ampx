@testable import AmpX
import XCTest

/// rekordbox sync against the real `~/Music/DJ` and its `collection.xml` (rekordbox sync spec § Testing,
/// success criteria 1 and 5). Opt-in: `TEST_RUNNER_AMPX_LIBRARY_GATE=1`. Results attach as `LIBRARY-GATE-rekordbox`.
final class RekordboxCollectionGateTests: XCTestCase {
    private typealias T = LibraryTestSupport

    /// The real file system, counting full reads of exports.
    private final class ReadCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var reads = 0
        var count: Int {
            self.lock.withLock { self.reads }
        }

        func increment() {
            self.lock.withLock { self.reads += 1 }
        }
    }

    private struct CountingFileSystem: LibraryFileSystem {
        let base = FoundationLibraryFileSystem()
        let counter: ReadCounter

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
            try await self.base.fingerprint(at: url)
        }

        func isReachable(_ root: URL) async -> Bool {
            await self.base.isReachable(root)
        }

        func topLevelFiles(in root: URL, pathExtension: String) async throws -> [LibraryTopLevelFile] {
            try await self.base.topLevelFiles(in: root, pathExtension: pathExtension)
        }

        func readPrefix(of url: URL, length: Int) async throws -> Data {
            try await self.base.readPrefix(of: url, length: length)
        }

        func readAll(of url: URL) async throws -> Data {
            self.counter.increment()
            return try await self.base.readAll(of: url)
        }
    }

    private struct Report: Encodable {
        var firstSyncSeconds = 0.0
        var rows = 0
        var rowsWithRekordboxValues = 0
        var matched = 0
        var updated = 0
        var unmatched = 0
        var ambiguous = 0
        var droppedWithoutLocation = 0
        var noLongerInRekordbox = 0
        var unchangedCheckReads = 0
        var forcedResyncSeconds = 0.0
        var forcedResyncUpdated = 0
        var readSeconds = 0.0
        var parseSeconds = 0.0
        var snapshotSeconds = 0.0
        var planSeconds = 0.0
        var packSeconds = 0.0
        var bareXMLParserSeconds = 0.0
        var planWithoutGridsSeconds = 0.0
    }

    /// Counts elements only: the floor any `XMLParser`-based parser pays.
    private final class BareDelegate: NSObject, XMLParserDelegate {
        var elements = 0

        func parser(_: XMLParser, didStartElement _: String, namespaceURI _: String?, qualifiedName _: String?,
                    attributes _: [String: String] = [:])
        {
            self.elements += 1
        }
    }

    private var engine: LibraryEngine?

    override func tearDown() async throws {
        await self.engine?.stop()
    }

    func testRealCollectionSync() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["AMPX_LIBRARY_GATE"] == "1",
            "Set TEST_RUNNER_AMPX_LIBRARY_GATE=1 to sync ~/Music/DJ/collection.xml"
        )
        let home = try String(cString: XCTUnwrap(getpwuid(getuid())).pointee.pw_dir)
        let dj = URL(fileURLWithPath: home).appendingPathComponent("Music/DJ", isDirectory: true)
        let counter = ReadCounter()
        let log = EventLog()
        let scope = ScopeSpy(log: log)
        var configuration = LibraryEngineConfiguration(
            startupFlag: FlagSpy(log: log),
            bookmarkStore: SecurityScopedBookmarkStore(userDefaults: T.isolatedDefaults(self))
        )
        configuration.storeURL = nil
        configuration.fileSystem = CountingFileSystem(counter: counter)
        configuration.storeDependencies = { flag in
            var dependencies = LibraryStoreDependencies(startupFlag: flag)
            dependencies.scope = scope.scope
            dependencies.bookmarks = LibraryTestSupport.plainBookmarks
            return dependencies
        }
        let engine = try await LibraryEngine.open(configuration)
        self.engine = engine
        var report = Report()

        // Success criterion 1: adding the folder is the only step.
        let start = ContinuousClock.now
        let rootID = try await engine.addRoot(url: dj)
        var source: RekordboxSourceSnapshot?
        let deadline = Date().addingTimeInterval(180)
        while source?.lastReport == nil, Date() < deadline {
            await engine.waitUntilIdle()
            source = try await engine.store.rekordboxSources().first { $0.rootID == rootID }
            if source?.lastReport == nil {
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        report.firstSyncSeconds = (ContinuousClock.now - start) / .seconds(1)
        let synced = try XCTUnwrap(source?.lastReport, "collection.xml was not imported")
        XCTAssertEqual(source?.fileName, "collection.xml")

        let snapshot = try await engine.store.rekordboxSnapshot()
        let rows = snapshot.rows.filter { $0.rootID == rootID }
        report.rows = rows.count
        report.rowsWithRekordboxValues = rows.filter {
            $0.bpm != nil && $0.musicalKey.flatMap(CamelotKey.from(musicalKey:)) != nil && $0.analysisSource == .rekordbox
        }.count
        report.matched = synced.matched
        report.updated = synced.updated
        report.unmatched = synced.unmatched.count
        report.ambiguous = synced.ambiguous.count
        report.droppedWithoutLocation = synced.droppedWithoutLocation
        report.noLongerInRekordbox = synced.noLongerInRekordbox.count

        // An unchanged export is not read again.
        let readsBefore = counter.count
        await engine.rekordbox.requestCheck(rootID: rootID)
        await engine.rekordbox.waitUntilIdle()
        report.unchangedCheckReads = counter.count - readsBefore

        // Success criterion 5: a forced re-sync of the unchanged export writes nothing.
        let forcedStart = ContinuousClock.now
        await engine.rekordbox.requestCheck(rootID: rootID, force: true)
        await engine.rekordbox.waitUntilIdle()
        report.forcedResyncSeconds = (ContinuousClock.now - forcedStart) / .seconds(1)
        report.forcedResyncUpdated = try await engine.store.rekordboxSources().first { $0.rootID == rootID }?.lastReport?.updated ?? -1

        // Where a sync's time goes.
        let xml = dj.appendingPathComponent("collection.xml")
        var mark = ContinuousClock.now
        let data = try await FoundationLibraryFileSystem().readAll(of: xml)
        report.readSeconds = (ContinuousClock.now - mark) / .seconds(1)
        mark = ContinuousClock.now
        let collection = try RekordboxCollectionParser.parse(data)
        report.parseSeconds = (ContinuousClock.now - mark) / .seconds(1)
        mark = ContinuousClock.now
        let library = try await engine.store.rekordboxSnapshot()
        report.snapshotSeconds = (ContinuousClock.now - mark) / .seconds(1)
        mark = ContinuousClock.now
        _ = RekordboxImportPlanner.plan(collection, fileName: "collection.xml", sourceRootID: rootID, library: library)
        report.planSeconds = (ContinuousClock.now - mark) / .seconds(1)
        mark = ContinuousClock.now
        for track in collection.tracks {
            _ = RekordboxBeatGrid.pack(track.beatGrid)
        }
        report.packSeconds = (ContinuousClock.now - mark) / .seconds(1)
        mark = ContinuousClock.now
        let bare = XMLParser(data: data)
        let bareDelegate = BareDelegate()
        bare.delegate = bareDelegate
        _ = bare.parse()
        report.bareXMLParserSeconds = (ContinuousClock.now - mark) / .seconds(1)
        let gridless = RekordboxCollection(
            productVersion: collection.productVersion,
            tracks: collection.tracks.map {
                RekordboxTrack(
                    path: $0.path, size: $0.size, duration: $0.duration, bpm: $0.bpm, tonality: $0.tonality, rating: $0.rating,
                    playCount: $0.playCount, label: $0.label, remixer: $0.remixer, composer: $0.composer, grouping: $0.grouping,
                    mix: $0.mix, beatGrid: []
                )
            },
            droppedWithoutLocation: 0
        )
        mark = ContinuousClock.now
        _ = RekordboxImportPlanner.plan(gridless, fileName: "collection.xml", sourceRootID: rootID, library: library)
        report.planWithoutGridsSeconds = (ContinuousClock.now - mark) / .seconds(1)

        self.emitGate("rekordbox", report)
        XCTAssertEqual(report.rows, 2232)
        XCTAssertEqual(report.rowsWithRekordboxValues, 2232)
        XCTAssertEqual(report.matched + report.unmatched + report.ambiguous, 2449 - report.droppedWithoutLocation)
        XCTAssertEqual(report.unchangedCheckReads, 0)
        XCTAssertEqual(report.forcedResyncUpdated, 0)
        XCTAssertLessThan(report.forcedResyncSeconds, 2)
    }
}
