@testable import AmpX
import SwiftData
import XCTest

/// Spec: "Scan scheduling" — one scan at a time, FIFO, one follow-up per run, store-side revocation.
final class LibraryScanSchedulingTests: XCTestCase {
    private typealias T = LibraryTestSupport

    /// Walk order by root folder name; roots named in `blocked` hold their first walk until released.
    private actor SchedulingFileSystem: LibraryFileSystem {
        private(set) var order: [String] = []
        private var started: [String: TestBarrier] = [:]
        private var release: [String: TestBarrier] = [:]

        func block(_ name: String) -> (started: TestBarrier, release: TestBarrier) {
            let pair = (TestBarrier(), TestBarrier())
            self.started[name] = pair.0
            self.release[name] = pair.1
            return pair
        }

        func volume(at _: URL) async throws -> LibraryVolume {
            LibraryVolume(caseSensitive: true, typeName: "apfs")
        }

        func walk(root: URL, volume: LibraryVolume) async throws -> LibraryWalk {
            let name = root.lastPathComponent
            self.order.append(name)
            if let started = self.started.removeValue(forKey: name), let release = self.release.removeValue(forKey: name) {
                await started.open()
                await release.wait()
            }
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

    private var container: ModelContainer!
    private var store: LibraryStore!
    private var fileSystem: SchedulingFileSystem!
    private var scanner: LibraryScanner!
    private var directory: URL!

    override func setUpWithError() throws {
        self.container = try LibraryContainerFactory.make(url: nil)
        let log = EventLog()
        self.store = T.makeRootStore(container: self.container, scope: ScopeSpy(log: log), flag: FlagSpy(log: log))
        self.fileSystem = SchedulingFileSystem()
        self.scanner = LibraryScanner(store: self.store, fileSystem: self.fileSystem, loadMetadata: FakeMetadataLoader().load)
        self.directory = try T.temporaryDirectory(self)
    }

    func testRequestsWhileRunningCollapseToOneFollowUp() async throws {
        let a = try await self.addRoot("A"), b = try await self.addRoot("B")
        let gate = await self.fileSystem.block("A")
        await self.scanner.requestScan(rootID: a)
        await gate.started.wait()
        for _ in 0 ..< 3 {
            await self.scanner.requestScan(rootID: a)
        }
        await self.scanner.requestScan(rootID: b)
        await gate.release.open()
        await self.scanner.waitUntilIdle()

        let order = await self.fileSystem.order
        XCTAssertEqual(order, ["A", "B", "A"])
        let maxRuns = await self.scanner.maxConcurrentRuns
        XCTAssertEqual(maxRuns, 1)
    }

    func testQueuedRequestsCoalesce() async throws {
        let a = try await self.addRoot("A"), b = try await self.addRoot("B")
        let gate = await self.fileSystem.block("A")
        await self.scanner.requestScan(rootID: a)
        await gate.started.wait()
        for _ in 0 ..< 3 {
            await self.scanner.requestScan(rootID: b)
        }
        await gate.release.open()
        await self.scanner.waitUntilIdle()
        let order = await self.fileSystem.order
        XCTAssertEqual(order, ["A", "B"])
    }

    func testTwoRootsBothScanned() async throws {
        let a = try await self.addRoot("A"), b = try await self.addRoot("B")
        await self.scanner.requestScan(rootID: a)
        await self.scanner.requestScan(rootID: b)
        await self.scanner.waitUntilIdle()
        let order = await self.fileSystem.order
        XCTAssertEqual(order, ["A", "B"])
        XCTAssertEqual(try T.tracks(self.container).count, 2)
    }

    func testCancelQueuedRootNeverStarts() async throws {
        let a = try await self.addRoot("A"), b = try await self.addRoot("B")
        let gate = await self.fileSystem.block("A")
        await self.scanner.requestScan(rootID: a)
        await gate.started.wait()
        await self.scanner.requestScan(rootID: b)
        await self.scanner.cancelScans(rootID: b)
        await gate.release.open()
        await self.scanner.waitUntilIdle()
        let order = await self.fileSystem.order
        XCTAssertEqual(order, ["A"])
    }

    func testCancelRunningRevokesBeforeCancelling() async throws {
        let a = try await self.addRoot("A")
        let gate = await self.fileSystem.block("A")
        await self.scanner.requestScan(rootID: a)
        await gate.started.wait()
        await self.scanner.requestScan(rootID: a) // a pending follow-up is dropped too
        await self.scanner.cancelScans(rootID: a)
        await gate.release.open()
        await self.scanner.waitUntilIdle()
        XCTAssertTrue(try T.tracks(self.container).isEmpty, "a cancelled run saves nothing")
        let order = await self.fileSystem.order
        XCTAssertEqual(order, ["A"])
    }

    func testErrorInOneRootContinuesQueue() async throws {
        let a = try await self.addRoot("A"), b = try await self.addRoot("B")
        try FileManager.default.removeItem(at: self.directory.appendingPathComponent("A"))
        await self.scanner.requestScan(rootID: a)
        await self.scanner.requestScan(rootID: b)
        await self.scanner.waitUntilIdle()
        let order = await self.fileSystem.order
        XCTAssertEqual(order, ["B"])
        let roots = try await self.store.roots()
        XCTAssertEqual(roots.first { $0.id == a }?.isAvailable, false)
    }

    func testStopCancelsEverything() async throws {
        let a = try await self.addRoot("A"), b = try await self.addRoot("B")
        let gate = await self.fileSystem.block("A")
        await self.scanner.requestScan(rootID: a)
        await gate.started.wait()
        await self.scanner.requestScan(rootID: b)
        let scanner = try XCTUnwrap(self.scanner)
        let stopping = Task { await scanner.stop() }
        await gate.release.open()
        await stopping.value
        let order = await self.fileSystem.order
        XCTAssertEqual(order, ["A"])
        XCTAssertTrue(try T.tracks(self.container).isEmpty)
    }

    // MARK: - Follow-ups with real scan content

    func testChangeInWalkedDirectoryIsPickedUpByFollowUp() async throws {
        let h = try await ScanHarness.make(self)
        await h.fileSystem.set("crate/a.mp3", stat: T.stat(10, 1), fingerprint: Data([1]))
        let gate = TestBarrier()
        await h.fileSystem.configure(walkBarrier: gate)
        await h.scanner.requestScan(rootID: h.rootID)
        while await h.fileSystem.walkCount == 0 {
            await Task.yield()
        }
        await h.fileSystem.set("crate/b.mp3", stat: T.stat(20, 1), fingerprint: Data([2])) // after the walk passed
        await h.scanner.requestScan(rootID: h.rootID)
        await gate.open()
        await h.scanner.waitUntilIdle()
        XCTAssertEqual(try h.tracks().map(\.relativePath), ["crate/a.mp3", "crate/b.mp3"])
        let walks = await h.fileSystem.walkCount
        XCTAssertEqual(walks, 2)
    }

    func testFileChangedDuringReadGetsOneFollowUp() async throws {
        let h = try await ScanHarness.make(self)
        await h.fileSystem.set("Growing.mp3", stat: T.stat(100, 1), fingerprint: Data([1]))
        let fileSystem = h.fileSystem
        h.loader.onCall { call in
            // The download finishes while the first read is in progress.
            if call == 1 {
                await fileSystem.set("Growing.mp3", stat: T.stat(200, 2), fingerprint: Data([1]))
            }
        }
        await h.scanner.requestScan(rootID: h.rootID)
        await h.scanner.waitUntilIdle()
        XCTAssertEqual(try h.tracks().map(\.fileSize), [200])
        let walks = await h.fileSystem.walkCount
        XCTAssertEqual(walks, 2)
    }

    // MARK: - Exclusive jobs (rekordbox sync spec § Turn-taking with scans)

    func testExclusiveJobWaitsForRunningScan() async throws {
        let scanner = try XCTUnwrap(self.scanner)
        let a = try await self.addRoot("A")
        let gate = await self.fileSystem.block("A")
        let log = EventLog()
        await self.scanner.requestScan(rootID: a)
        await gate.started.wait()
        let job = Task { await scanner.performExclusive { log.append("job") } }
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        XCTAssertEqual(log.events, [])
        await gate.release.open()
        await job.value
        XCTAssertEqual(log.events, ["job"])
        let maxRuns = await self.scanner.maxConcurrentRuns
        XCTAssertEqual(maxRuns, 1)
    }

    func testScanWaitsForExclusiveJob() async throws {
        let scanner = try XCTUnwrap(self.scanner)
        let a = try await self.addRoot("A")
        let started = TestBarrier(), release = TestBarrier()
        let job = Task {
            await scanner.performExclusive {
                await started.open()
                await release.wait()
            }
        }
        await started.wait()
        await self.scanner.requestScan(rootID: a)
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        let walkedWhileJobRan = await self.fileSystem.order
        XCTAssertEqual(walkedWhileJobRan, [])
        await release.open()
        await job.value
        await self.scanner.waitUntilIdle()
        let order = await self.fileSystem.order
        XCTAssertEqual(order, ["A"])
        let maxRuns = await self.scanner.maxConcurrentRuns
        XCTAssertEqual(maxRuns, 1)
    }

    func testExclusiveJobsRunInOrder() async throws {
        let scanner = try XCTUnwrap(self.scanner)
        let log = EventLog()
        let a = try await self.addRoot("A")
        let gate = await self.fileSystem.block("A")
        await self.scanner.requestScan(rootID: a)
        await gate.started.wait()
        let first = Task { await scanner.performExclusive { log.append("1") } }
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        let second = Task { await scanner.performExclusive { log.append("2") } }
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        await gate.release.open()
        await first.value
        await second.value
        XCTAssertEqual(log.events, ["1", "2"])
    }

    func testStopDropsQueuedExclusiveJob() async throws {
        let scanner = try XCTUnwrap(self.scanner)
        let log = EventLog()
        let a = try await self.addRoot("A")
        let gate = await self.fileSystem.block("A")
        await self.scanner.requestScan(rootID: a)
        await gate.started.wait()
        let job = Task { await scanner.performExclusive { log.append("job") } }
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        let stop = Task { await scanner.stop() }
        await gate.release.open()
        await stop.value
        await job.value
        XCTAssertEqual(log.events, [])
    }

    private func addRoot(_ name: String) async throws -> UUID {
        let url = self.directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return try await self.store.addRoot(url: url)
    }
}
