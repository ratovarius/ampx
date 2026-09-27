@testable import AmpX
import SwiftData
import XCTest

/// One full-root scan run (spec: "Scanning", steps 0–7).
final class LibraryScannerTests: XCTestCase {
    private typealias T = LibraryTestSupport

    func testNoChangeScanReadsNothing() async throws {
        let h = try await ScanHarness.make(self)
        for index in 0 ..< 3 {
            let path = "crate/\(index).mp3"
            try T.seedTrack(
                h.container,
                id: UUID(),
                rootID: h.rootID,
                path: path,
                stat: T.stat(100 + Int64(index), 1),
                fingerprint: Data([1])
            )
            await h.fileSystem.set(path, stat: T.stat(100 + Int64(index), 1), fingerprint: Data([1]))
        }
        let outcome = try await h.scanner.scanOnce(rootID: h.rootID)

        XCTAssertEqual(outcome, LibraryScanOutcome(coverage: .complete, needsFollowUp: false))
        let parseCount = h.loader.callCount
        let fingerprintCount = await h.fileSystem.fingerprintCount
        let statCount = await h.fileSystem.statCount
        XCTAssertEqual(parseCount, 0)
        XCTAssertEqual(fingerprintCount, 0)
        XCTAssertEqual(statCount, 0)
        let root = try await h.root()
        XCTAssertEqual(root.lastCompletedScanAt, T.fixedDate)
    }

    func testNewFilesInsertedInBatchesOf200() async throws {
        let h = try await ScanHarness.make(self)
        for index in 0 ..< 450 {
            await h.fileSystem.set(String(format: "crate/%03d.mp3", index), stat: T.stat(Int64(1000 + index), 1), fingerprint: Data([2]))
        }
        let changes = await h.store.changes()
        let progress = await h.scanner.progress()
        _ = try await h.scanner.scanOnce(rootID: h.rootID)

        XCTAssertEqual(try h.tracks().count, 450)
        XCTAssertEqual(try h.tracks().first?.title, "000")
        var rowSaves = 0
        for await change in changes {
            if change == .rowsChanged(rootID: h.rootID) {
                rowSaves += 1
            }
            if change == .rootsChanged(rootID: h.rootID) {
                break
            } // finishScan
        }
        XCTAssertEqual(rowSaves, 3)
        var last: ScanProgress?
        for await event in progress {
            last = event
            if event.phase == .parsing, event.done == event.total {
                break
            }
        }
        XCTAssertEqual(last, ScanProgress(rootID: h.rootID, phase: .parsing, done: 450, total: 450))
    }

    func testPartialWalkInsertsButNeverMoves() async throws {
        let h = try await ScanHarness.make(self)
        let a = UUID()
        try T.seedTrack(h.container, id: a, rootID: h.rootID, path: "x/A.mp3", stat: T.stat(10, 1), fingerprint: Data([1]))
        let hidden = UUID()
        try T.seedTrack(h.container, id: hidden, rootID: h.rootID, path: "z/Old.mp3", stat: T.stat(20, 1))
        await h.fileSystem.set("y/B.mp3", stat: T.stat(10, 1), fingerprint: Data([1]))
        await h.fileSystem.configure(coverage: .partial(uncoveredFolders: ["z"]))

        let outcome = try await h.scanner.scanOnce(rootID: h.rootID)
        XCTAssertEqual(outcome.coverage, .partial(uncoveredFolders: ["z"]))
        let rows = try h.tracks()
        XCTAssertEqual(rows.map(\.relativePath), ["x/A.mp3", "y/B.mp3", "z/Old.mp3"])
        XCTAssertEqual(rows.map(\.isMissing), [true, false, false])
        XCTAssertNotEqual(rows[1].id, a)
        let root = try await h.root()
        XCTAssertNil(root.lastCompletedScanAt)
        XCTAssertEqual(root.unreadableFolderCount, 1)
    }

    func testAbortedWalkSavesNothingAfterRepair() async throws {
        let h = try await ScanHarness.make(self)
        try T.seedTrack(h.container, id: UUID(), rootID: h.rootID, path: "A.mp3")
        await h.fileSystem.configure(coverage: .aborted)
        let outcome = try await h.scanner.scanOnce(rootID: h.rootID)
        XCTAssertEqual(outcome.coverage, .aborted)
        XCTAssertEqual(try h.tracks().map(\.isMissing), [false])
        let root = try await h.root()
        XCTAssertNil(root.lastCompletedScanAt)
    }

    func testFileChangedDuringReadIsLeftStaleAndRequestsFollowUp() async throws {
        let h = try await ScanHarness.make(self)
        await h.fileSystem.set("Growing.mp3", stat: T.stat(100, 1), fingerprint: Data([1]), statAfterRead: T.stat(200, 2))
        await h.fileSystem.set("Stable.mp3", stat: T.stat(300, 1), fingerprint: Data([2]))
        let outcome = try await h.scanner.scanOnce(rootID: h.rootID)
        XCTAssertTrue(outcome.needsFollowUp)
        XCTAssertEqual(try h.tracks().map(\.relativePath), ["Stable.mp3"])
    }

    func testCorruptFileInsertsDegradedRow() async throws {
        let h = try await ScanHarness.make(self)
        await h.fileSystem.set("Broken.mp3", stat: T.stat(0, 1), fingerprint: nil)
        h.loader.fail("Broken.mp3")
        let outcome = try await h.scanner.scanOnce(rootID: h.rootID)
        XCTAssertEqual(outcome.coverage, .complete)
        let row = try XCTUnwrap(try ModelContext(h.container).fetch(FetchDescriptor<LibraryTrack>()).first)
        XCTAssertEqual(row.relativePath, "Broken.mp3")
        XCTAssertEqual(row.duration, 0)
        XCTAssertNil(row.contentFingerprint)
    }

    func testVanishedRootAbortsWithoutDegradedRow() async throws {
        let h = try await ScanHarness.make(self)
        await h.fileSystem.set("A.mp3", stat: T.stat(10, 1), fingerprint: Data([1]))
        h.loader.fail("A.mp3")
        let fileSystem = h.fileSystem
        h.loader.onCall { _ in await fileSystem.configure(reachable: false) }
        do {
            _ = try await h.scanner.scanOnce(rootID: h.rootID)
            XCTFail("an unreachable root aborts the run")
        } catch {}
        XCTAssertTrue(try h.tracks().isEmpty)
        let root = try await h.root()
        XCTAssertFalse(root.isAvailable)
    }

    func testRevokedMidParseRejectsRemainingBatches() async throws {
        let h = try await ScanHarness.make(self, batchSize: 2)
        for name in ["a", "b", "c", "d"] {
            try await h.fileSystem.set(
                "\(name).mp3",
                stat: T.stat(Int64(XCTUnwrap(name.unicodeScalars.first?.value)), 1),
                fingerprint: Data([1])
            )
        }
        let store = h.store
        let rootID = h.rootID
        h.loader.onCall { call in
            if call == 3 {
                await store.revokeScan(rootID: rootID)
            }
        }
        do {
            _ = try await h.scanner.scanOnce(rootID: h.rootID)
            XCTFail("a revoked run ends at its next save")
        } catch {
            XCTAssertEqual(error as? LibraryStoreError, .revokedToken)
        }
        XCTAssertEqual(try h.tracks().map(\.relativePath), ["a.mp3", "b.mp3"])
    }

    func testDuplicateRowsRepairedBeforeMatching() async throws {
        let h = try await ScanHarness.make(self)
        let older = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        try T.seedTrack(
            h.container,
            id: older,
            rootID: h.rootID,
            path: "A.mp3",
            history: LibraryHistory(playCount: 1, lastPlayedAt: nil, rating: 0),
            dateAdded: Date(timeIntervalSince1970: 1)
        )
        try T.seedTrack(
            h.container,
            id: UUID(),
            rootID: h.rootID,
            path: "A.mp3",
            history: LibraryHistory(playCount: 6, lastPlayedAt: nil, rating: 3),
            dateAdded: Date(timeIntervalSince1970: 2)
        )
        await h.fileSystem.set("A.mp3", stat: T.stat(100, 1))
        _ = try await h.scanner.scanOnce(rootID: h.rootID)
        let rows = try h.tracks()
        XCTAssertEqual(rows.map(\.id), [older])
        XCTAssertEqual(rows.first?.history, LibraryHistory(playCount: 6, lastPlayedAt: nil, rating: 3))
        _ = try await h.scanner.scanOnce(rootID: h.rootID) // second scan is a no-op
        XCTAssertEqual(try h.tracks().map(\.id), [older])
    }

    func testUnavailableRootSavesUnavailableAndThrows() async throws {
        let h = try await ScanHarness.make(self)
        try FileManager.default.removeItem(at: h.rootURL)
        do {
            _ = try await h.scanner.scanOnce(rootID: h.rootID)
            XCTFail("step 0 fails for a missing folder")
        } catch {
            XCTAssertEqual(error as? LibraryStoreError, .unavailableRoot)
        }
        let walks = await h.fileSystem.walkCount
        XCTAssertEqual(walks, 0)
    }
}
