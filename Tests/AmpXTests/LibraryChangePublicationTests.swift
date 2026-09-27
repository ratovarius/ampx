@testable import AmpX
import SwiftData
import XCTest

/// `LibraryIndex` against real store saves (spec: "Change publication").
final class LibraryChangePublicationTests: XCTestCase {
    private typealias T = LibraryTestSupport

    private final class ManualClock: @unchecked Sendable {
        private let lock = NSLock()
        private var instant = ContinuousClock.now

        var now: ContinuousClock.Instant {
            self.lock.withLock { self.instant }
        }

        func advance(_ duration: Duration) {
            self.lock.withLock { self.instant += duration }
        }
    }

    private var container: ModelContainer!
    private var store: LibraryStore!
    private var index: LibraryIndex!
    private var clock: ManualClock!
    private var trailingGate: TestBarrier!
    private var directory: URL!
    private var rootID: UUID!

    override func setUp() async throws {
        self.container = try LibraryContainerFactory.make(url: nil)
        let log = EventLog()
        self.store = T.makeRootStore(container: self.container, scope: ScopeSpy(log: log), flag: FlagSpy(log: log))
        self.directory = try T.temporaryDirectory(self)
        self.rootID = try await self.store.addRoot(url: self.folder("DJ"))
        self.clock = ManualClock()
        self.trailingGate = TestBarrier()
        let clock = self.clock!, gate = self.trailingGate!
        let timing = LibraryIndexTiming(throttle: .seconds(1), now: { clock.now }, sleep: { _ in await gate.wait() })
        self.index = await LibraryIndex(container: self.container, changes: self.store.changes(), timing: timing)
    }

    override func tearDown() async throws {
        await self.index.stop()
    }

    func testLazyBuildOnFirstQuery() async throws {
        try await self.insert(["a.mp3", "b.mp3"])
        let refetchesBefore = await self.index.refetchCount
        let result = try await self.index.query(LibraryQuery(), generation: 1)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(Set(result.rows.map(\.url.lastPathComponent)), ["a.mp3", "b.mp3"])
        XCTAssertTrue(result.rows.allSatisfy(\.isAvailable))
        XCTAssertEqual(refetchesBefore, 0)
    }

    func testSaveBeforeFirstQueryIsNotLost() async throws {
        try await self.insert(["a.mp3"]) // published before any snapshot exists
        let result = try await self.index.query(LibraryQuery(), generation: 1)
        XCTAssertEqual(result.rows.map(\.title), ["Parsed"])
    }

    func testRootRemovedEvictsImmediately() async throws {
        try await self.insert(["a.mp3"])
        _ = try await self.index.query(LibraryQuery(), generation: 1)
        var versions = await self.index.versions().makeAsyncIterator()
        try await self.store.removeRoot(id: self.rootID)
        _ = await versions.next()
        let result = try await self.index.query(LibraryQuery(), generation: 2)
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertTrue(result.facets.genres.isEmpty)
    }

    func testRootsChangedRebuildsURLsAndAvailability() async throws {
        try await self.insert(["crate/a.mp3"])
        _ = try await self.index.query(LibraryQuery(), generation: 1)
        var versions = await self.index.versions().makeAsyncIterator()

        try await self.store.markUnavailable(id: self.rootID)
        _ = await versions.next()
        var rows = try await self.index.query(LibraryQuery(), generation: 2).rows
        XCTAssertEqual(rows.map(\.isAvailable), [false])
        XCTAssertEqual(rows.first?.genre, "Techno", "facets still count unavailable rows")

        try await self.store.relocateRoot(id: self.rootID, to: self.folder("Moved"))
        _ = await versions.next()
        rows = try await self.index.query(LibraryQuery(), generation: 3).rows
        XCTAssertEqual(rows.first?.url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent, "Moved")

        let token = try await self.store.beginScan(rootID: self.rootID)
        _ = try await self.store.resolveRoot(token: token) // remount
        _ = await versions.next()
        rows = try await self.index.query(LibraryQuery(), generation: 4).rows
        XCTAssertEqual(rows.map(\.isAvailable), [true])
    }

    func testMissingRowIsUnavailable() async throws {
        try await self.insert(["a.mp3"])
        let id = try XCTUnwrap(try T.tracks(self.container).first?.id)
        _ = try await self.index.query(LibraryQuery(), generation: 1)
        var versions = await self.index.versions().makeAsyncIterator()
        let token = try await self.store.beginScan(rootID: self.rootID)
        try await self.store.applyStructure(
            LibraryReconciliation(moves: [], spellingUpdates: [], foundIDs: [], missingIDs: [id], newEntries: [], staleIDs: []),
            token: token, unreadableFolderCount: 0
        )
        _ = await versions.next()
        let rows = try await self.index.query(LibraryQuery(), generation: 2).rows
        XCTAssertEqual(rows.map(\.isAvailable), [false])
    }

    func testRowsChangedThrottledWithTrailingRefetch() async throws {
        _ = try await self.index.query(LibraryQuery(), generation: 1)
        var versions = await self.index.versions().makeAsyncIterator()
        try await self.insert(["0.mp3"]) // first change: immediate
        _ = await versions.next()
        for index in 1 ..< 5 {
            try await self.insert(["\(index).mp3"]) // within the second: coalesced
        }
        var refetches = await self.index.refetchCount
        XCTAssertEqual(refetches, 1)
        let value1 = try await self.index.query(LibraryQuery(), generation: 2)
        XCTAssertEqual(value1.rows.count, 1)

        await self.trailingGate.open() // the throttle window elapses
        _ = await versions.next()
        refetches = await self.index.refetchCount
        XCTAssertEqual(refetches, 2)
        let value2 = try await self.index.query(LibraryQuery(), generation: 3)
        XCTAssertEqual(value2.rows.count, 5)
    }

    func testRowsChangedAfterWindowRefetchesImmediately() async throws {
        _ = try await self.index.query(LibraryQuery(), generation: 1)
        var versions = await self.index.versions().makeAsyncIterator()
        try await self.insert(["0.mp3"])
        _ = await versions.next()
        self.clock.advance(.seconds(2))
        try await self.insert(["1.mp3"])
        _ = await versions.next()
        let refetches = await self.index.refetchCount
        XCTAssertEqual(refetches, 2)
    }

    func testRootChangeOverridesPendingRowRefetch() async throws {
        _ = try await self.index.query(LibraryQuery(), generation: 1)
        var versions = await self.index.versions().makeAsyncIterator()
        try await self.insert(["0.mp3"])
        _ = await versions.next()
        try await self.insert(["1.mp3"]) // pending trailing refetch
        try await self.store.markUnavailable(id: self.rootID) // immediate rebuild supersedes it
        _ = await versions.next()
        let value3 = try await self.index.query(LibraryQuery(), generation: 2)
        XCTAssertEqual(value3.rows.count, 2)
        let afterRebuild = await self.index.refetchCount
        await self.trailingGate.open()
        await self.index.waitForPendingRefetches()
        let final = await self.index.refetchCount
        XCTAssertEqual(final, afterRebuild, "the superseded trailing refetch must not run")
    }

    func testRejectedTokenBumpsNoVersion() async throws {
        _ = try await self.index.query(LibraryQuery(), generation: 1)
        let before = try await self.index.query(LibraryQuery(), generation: 2).snapshotVersion
        var versions = await self.index.versions().makeAsyncIterator()
        let token = try await self.store.beginScan(rootID: self.rootID)
        await self.store.revokeScan(rootID: self.rootID)
        try? await self.store.applyParsed([T.parseWrite(insert: true, path: "x.mp3")], token: token)
        try await self.insert(["y.mp3"])
        let next = await versions.next()
        XCTAssertEqual(next, before + 1)
    }

    func testIntegrityMergeUpdatesCounts() async throws {
        let a = UUID(), b = UUID()
        try T.seedTrack(self.container, id: a, rootID: self.rootID, path: "dup.mp3", dateAdded: Date(timeIntervalSince1970: 1))
        try T.seedTrack(self.container, id: b, rootID: self.rootID, path: "dup.mp3", dateAdded: Date(timeIntervalSince1970: 2))
        let value4 = try await self.index.query(LibraryQuery(), generation: 1)
        XCTAssertEqual(value4.rows.count, 2)
        var versions = await self.index.versions().makeAsyncIterator()
        let token = try await self.store.beginScan(rootID: self.rootID)
        try await self.store.applyIntegrityMerges(
            [LibraryIntegrityMerge(survivorID: a, deletedIDs: [b], history: LibraryHistory(playCount: 0, lastPlayedAt: nil, rating: 0))],
            token: token
        )
        _ = await versions.next()
        let value5 = try await self.index.query(LibraryQuery(), generation: 2)
        XCTAssertEqual(value5.rows.map(\.id), [a])
    }

    func testRowsLookupUsesLatestSnapshot() async throws {
        try await self.insert(["a.mp3", "b.mp3"])
        let ids = try Set(T.tracks(self.container).map(\.id))
        let rows = try await self.index.rows(ids: ids)
        XCTAssertEqual(Set(rows.map(\.id)), ids)
        let value6 = try await self.index.rows(ids: [UUID()])
        XCTAssertTrue(value6.isEmpty)
    }

    // MARK: - Helpers

    private func insert(_ paths: [String]) async throws {
        let token = try await self.store.beginScan(rootID: self.rootID)
        try await self.store.applyParsed(paths.map { T.parseWrite(insert: true, path: $0) }, token: token)
    }

    private func folder(_ name: String) throws -> URL {
        let url = self.directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
