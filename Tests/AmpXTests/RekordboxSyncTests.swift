@testable import AmpX
import SwiftData
import XCTest

/// Discovery, checks and turn-taking (rekordbox sync spec § Discovery, § `RekordboxSync`, § Error handling).
final class RekordboxSyncTests: XCTestCase {
    private typealias T = LibraryTestSupport

    private var h: ScanHarness!
    private var sync: RekordboxSync!
    private var root: String {
        self.h.fileSystem.root.path
    }

    override func setUp() async throws {
        self.h = try await ScanHarness.make(self)
        self.sync = RekordboxSync(store: self.h.store, scanner: self.h.scanner, fileSystem: self.h.fileSystem)
        await self.sync.start()
    }

    override func tearDown() async throws {
        await self.sync.stop()
        await self.h.scanner.stop()
    }

    // MARK: - Helpers

    private func seed(_ paths: [String], rootID: UUID? = nil) throws -> [UUID] {
        try paths.map { path in
            let id = UUID()
            try T.seedTrack(self.h.container, id: id, rootID: rootID ?? self.h.rootID, path: path)
            return id
        }
    }

    private func export(
        _ entries: [RekordboxXML.Entry],
        name: String = "collection.xml",
        modified: TimeInterval = 100,
        in root: String? = nil
    ) async {
        await self.h.fileSystem.setTopLevel((root ?? self.root) + "/" + name, data: RekordboxXML.make(entries), modified: modified)
    }

    private func check(_ rootID: UUID? = nil, force: Bool = false) async {
        await self.sync.requestCheck(rootID: rootID ?? self.h.rootID, force: force)
        await self.sync.waitUntilIdle()
    }

    private func track(_ id: UUID) throws -> LibraryTrack {
        try XCTUnwrap(try ModelContext(self.h.container).fetch(FetchDescriptor<LibraryTrack>()).first { $0.id == id })
    }

    private func sources() async throws -> [RekordboxSourceSnapshot] {
        try await self.h.store.rekordboxSources()
    }

    private func eventually(
        _ condition: @escaping () async throws -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async rethrows {
        for _ in 0 ..< 200 {
            if try await condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("condition not met", file: file, line: line)
    }

    // MARK: - Discovery

    func testNoXmlDoesNothingAndStaysHidden() async throws {
        _ = try self.seed(["a.mp3"])
        await self.check()
        let sources = try await self.sources()
        XCTAssertTrue(sources.isEmpty)
        let state = await self.sync.state()
        XCTAssertEqual(state.status, .hidden)
        let reads = await self.h.fileSystem.fullReads
        XCTAssertEqual(reads, 0)
    }

    func testNonRekordboxXmlIgnored() async throws {
        let ids = try self.seed(["a.mp3"])
        await self.h.fileSystem.setTopLevel(
            self.root + "/Library.xml", data: RekordboxXML.make([.init(path: self.root + "/a.mp3")], product: "Other"), modified: 1
        )
        await self.check()
        XCTAssertNil(try self.track(ids[0]).bpm)
        let sources = try await self.sources()
        XCTAssertTrue(sources.isEmpty)
    }

    func testXmlInSubfolderIgnored() async throws {
        let ids = try self.seed(["a.mp3"])
        await self.export([.init(path: self.root + "/a.mp3")], name: "sub/collection.xml")
        await self.check()
        XCTAssertNil(try self.track(ids[0]).bpm)
    }

    func testNewestExportChosen() async throws {
        let ids = try self.seed(["a.mp3"])
        await self.export([.init(path: self.root + "/a.mp3", bpm: 110)], name: "old.xml", modified: 100)
        await self.export([.init(path: self.root + "/a.mp3", bpm: 128)], name: "new.xml", modified: 200)
        await self.check()
        XCTAssertEqual(try self.track(ids[0]).bpm, 128)
        let sources = try await self.sources()
        XCTAssertEqual(sources.map(\.fileName), ["new.xml"])
    }

    func testAddingRootImports() async throws {
        await self.h.fileSystem.set("a.mp3", stat: T.stat(100, 1), fingerprint: Data([1]))
        await self.export([.init(path: self.root + "/a.mp3", bpm: 126, key: "Fm")])

        await self.h.scanner.requestScan(rootID: self.h.rootID)

        try await self.eventually {
            let rows = try ModelContext(self.h.container).fetch(FetchDescriptor<LibraryTrack>())
            return rows.first?.bpm == 126
        }
        await self.sync.waitUntilIdle()
        let track = try XCTUnwrap(try ModelContext(self.h.container).fetch(FetchDescriptor<LibraryTrack>()).first)
        XCTAssertEqual(track.camelotKey, "4A")
        XCTAssertEqual(track.analysisSource, .rekordbox)
        let sources = try await self.sources()
        XCTAssertEqual(sources.first?.isPresent, true)
        let state = await self.sync.state()
        XCTAssertEqual(state.status, .idle(lastSync: T.fixedDate))
    }

    // MARK: - Stamps

    func testUnchangedStampSkipsParse() async throws {
        _ = try self.seed(["a.mp3"])
        await self.export([.init(path: self.root + "/a.mp3")])
        await self.check()
        await self.check()
        let reads = await self.h.fileSystem.fullReads
        XCTAssertEqual(reads, 1)
    }

    func testChangedStampReimportsAfterScan() async throws {
        await self.h.fileSystem.set("a.mp3", stat: T.stat(100, 1), fingerprint: Data([1]))
        await self.export([.init(path: self.root + "/a.mp3", bpm: 120)], modified: 100)
        await self.h.scanner.requestScan(rootID: self.h.rootID)
        try await self.eventually { try ModelContext(self.h.container).fetch(FetchDescriptor<LibraryTrack>()).first?.bpm == 120 }

        await self.export([.init(path: self.root + "/a.mp3", bpm: 131)], modified: 200)
        await self.h.scanner.requestScan(rootID: self.h.rootID)

        try await self.eventually { try ModelContext(self.h.container).fetch(FetchDescriptor<LibraryTrack>()).first?.bpm == 131 }
    }

    func testForceReimportsUnchangedFile() async throws {
        _ = try self.seed(["a.mp3"])
        await self.export([.init(path: self.root + "/a.mp3")])
        await self.check()
        await self.check(force: true)
        let reads = await self.h.fileSystem.fullReads
        XCTAssertEqual(reads, 2)
        let sources = try await self.sources()
        XCTAssertEqual(sources.first?.lastReport?.matched, 1)
        XCTAssertEqual(sources.first?.lastReport?.updated, 0)
    }

    func testExportDisappearsSilently() async throws {
        let ids = try self.seed(["a.mp3"])
        await self.export([.init(path: self.root + "/a.mp3", bpm: 126)])
        await self.check()
        await self.h.fileSystem.removeTopLevel(self.root + "/collection.xml")
        await self.check()

        let sources = try await self.sources()
        XCTAssertEqual(sources.first?.isPresent, false)
        XCTAssertEqual(try self.track(ids[0]).bpm, 126)
        let state = await self.sync.state()
        XCTAssertEqual(state.status, .hidden)
    }

    func testUnreadableExportIsSilent() async throws {
        let ids = try self.seed(["a.mp3"])
        await self.export([.init(path: self.root + "/a.mp3", bpm: 126)])
        await self.h.fileSystem.setUnreadable(self.root + "/collection.xml")
        await self.check()
        XCTAssertNil(try self.track(ids[0]).bpm)
        let state = await self.sync.state()
        XCTAssertEqual(state.status, .hidden)
    }

    // MARK: - Failures

    func testTruncatedThenCompleteFileSyncs() async throws {
        let ids = try self.seed(["a.mp3"])
        let full = RekordboxXML.make([.init(path: self.root + "/a.mp3", bpm: 126)])
        await self.h.fileSystem.setTopLevel(self.root + "/collection.xml", data: full.prefix(full.count - 40), modified: 100)
        await self.check()
        XCTAssertNil(try self.track(ids[0]).bpm)
        var state = await self.sync.state()
        XCTAssertEqual(state.status, .hidden)

        await self.h.fileSystem.setTopLevel(self.root + "/collection.xml", data: full, modified: 101)
        await self.check()
        XCTAssertEqual(try self.track(ids[0]).bpm, 126)
        state = await self.sync.state()
        XCTAssertEqual(state.status, .idle(lastSync: T.fixedDate))
    }

    func testRepeatedParseFailureChangesNoState() async throws {
        let ids = try self.seed(["a.mp3"])
        await self.h.fileSystem.setTopLevel(
            self.root + "/collection.xml",
            data: Data("<DJ_PLAYLISTS><PRODUCT Name=\"rekordbox\"/>".utf8),
            modified: 100
        )
        await self.check()
        await self.check()
        XCTAssertNil(try self.track(ids[0]).bpm)
        let sources = try await self.sources()
        XCTAssertTrue(sources.isEmpty)
        let state = await self.sync.state()
        XCTAssertEqual(state.status, .hidden)
    }

    func testZeroMatchesStoresReportSilently() async throws {
        _ = try self.seed(["a.mp3"])
        await self.export([.init(path: "/Elsewhere/z.mp3")])
        await self.check()
        let sources = try await self.sources()
        XCTAssertEqual(sources.first?.lastReport?.matched, 0)
        XCTAssertEqual(sources.first?.lastReport?.unmatched, ["/Elsewhere/z.mp3"])
        let reads = await self.h.fileSystem.fullReads
        await self.check()
        let readsAfter = await self.h.fileSystem.fullReads
        XCTAssertEqual(reads, readsAfter, "an unmatched export is not re-read while unchanged")
    }

    // MARK: - Several roots

    private func addSecondRoot() async throws -> (id: UUID, path: String) {
        let url = try T.temporaryDirectory(self)
        let id = try await self.h.store.addRoot(url: url)
        return (id, url.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    func testChecksRunOldestExportFirst() async throws {
        let second = try await self.addSecondRoot()
        let ids = try self.seed(["a.mp3"])
        // Both exports list the first root's track; the second root's export is newer and must win.
        await self.export([.init(path: self.root + "/a.mp3", bpm: 110)], modified: 100)
        await self.export([.init(path: self.root + "/a.mp3", bpm: 128)], modified: 200, in: second.path)
        await self.sync.requestCheck(rootID: second.id)
        await self.sync.requestCheck(rootID: self.h.rootID)
        await self.sync.waitUntilIdle()
        XCTAssertEqual(try self.track(ids[0]).bpm, 128)
    }

    func testRemovingRootDuringCheckWritesNothing() async throws {
        _ = try self.seed(["a.mp3"])
        await self.export([.init(path: self.root + "/a.mp3", bpm: 126)])
        let gate = await self.h.fileSystem.blockNextRead()
        let rootID = self.h.rootID
        let sync = try XCTUnwrap(self.sync)
        let check = Task { await sync.requestCheck(rootID: rootID) }
        await gate.started.wait()
        try await self.h.store.removeRoot(id: rootID)
        await gate.release.open()
        await check.value
        await sync.waitUntilIdle()
        let sources = try await self.sources()
        XCTAssertTrue(sources.isEmpty)
    }

    func testOtherRootCheckSurvivesRemoval() async throws {
        let second = try await self.addSecondRoot()
        let otherIDs = try self.seed(["b.mp3"], rootID: second.id)
        _ = try self.seed(["a.mp3"])
        await self.export([.init(path: self.root + "/a.mp3", bpm: 126)], modified: 100)
        await self.export([.init(path: second.path + "/b.mp3", bpm: 99)], modified: 200, in: second.path)
        let gate = await self.h.fileSystem.blockNextRead() // the older export (first root) is read first
        let sync = try XCTUnwrap(self.sync)
        let (first, other) = (self.h.rootID, second.id)
        let check = Task {
            await sync.requestCheck(rootID: first)
            await sync.requestCheck(rootID: other)
        }
        await gate.started.wait()
        try await self.h.store.removeRoot(id: first)
        await gate.release.open()
        await check.value
        await sync.waitUntilIdle()
        XCTAssertEqual(try self.track(otherIDs[0]).bpm, 99)
    }

    // MARK: - Lifecycle

    func testStopWaitsForRunningJob() async throws {
        let ids = try self.seed(["a.mp3"])
        await self.export([.init(path: self.root + "/a.mp3", bpm: 126)])
        let gate = await self.h.fileSystem.blockNextRead()
        let sync = try XCTUnwrap(self.sync)
        let rootID = self.h.rootID
        Task { await sync.requestCheck(rootID: rootID) }
        await gate.started.wait()
        let log = EventLog()
        let stop = Task {
            await sync.stop()
            log.append("stopped")
        }
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        XCTAssertEqual(log.events, [])
        await gate.release.open()
        await stop.value
        XCTAssertEqual(log.events, ["stopped"])
        XCTAssertNil(try self.track(ids[0]).bpm, "a stopped sync writes nothing")
    }

    func testStatesStream() async throws {
        _ = try self.seed(["a.mp3"])
        await self.export([.init(path: self.root + "/a.mp3", bpm: 126)])
        var states = await self.sync.states().makeAsyncIterator()
        let first = await states.next()
        XCTAssertEqual(first?.status, .hidden)
        await self.check()
        var seen: [RekordboxSyncStatus] = []
        while let state = await states.next() {
            seen.append(state.status)
            if case .idle = state.status {
                break
            }
        }
        XCTAssertEqual(seen, [.syncing, .idle(lastSync: T.fixedDate)])
    }
}
