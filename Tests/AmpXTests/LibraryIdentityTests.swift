@testable import AmpX
import XCTest

/// Row identity through real scans (spec: "Row identity", "Interruption", success criterion 7).
final class LibraryIdentityTests: XCTestCase {
    private typealias T = LibraryTestSupport
    private let a = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let b = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    private let x = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!
    private let hardLinked = UUID(uuidString: "00000000-0000-0000-0000-00000000000D")!
    private let history = LibraryHistory(playCount: 7, lastPlayedAt: Date(timeIntervalSince1970: 70), rating: 5)

    func testRenameKeepsIDAndHistoryWithNoInsertBeforeStructureSave() async throws {
        let h = try await ScanHarness.make(self)
        try T.seedTrack(
            h.container,
            id: self.a,
            rootID: h.rootID,
            path: "A.mp3",
            stat: T.stat(10, 1),
            history: self.history,
            fingerprint: Data([1])
        )
        await h.fileSystem.set("Renamed/B.mp3", stat: T.stat(10, 1), fingerprint: Data([1]))
        _ = try await h.scanner.scanOnce(rootID: h.rootID)
        let rows = try h.tracks()
        XCTAssertEqual(rows.map(\.id), [self.a])
        XCTAssertEqual(rows.first?.relativePath, "Renamed/B.mp3")
        XCTAssertEqual(rows.first?.history, self.history)
        XCTAssertEqual(h.loader.callCount, 0, "a move is not re-parsed")
    }

    func testPathSwapKeepsRowsOnPaths() async throws {
        let h = try await ScanHarness.make(self)
        try T.seedTrack(h.container, id: self.a, rootID: h.rootID, path: "a.mp3", stat: T.stat(10, 1), history: self.history)
        try T.seedTrack(h.container, id: self.b, rootID: h.rootID, path: "b.mp3", stat: T.stat(20, 2))
        await h.fileSystem.set("a.mp3", stat: T.stat(20, 2), fingerprint: Data([2]))
        await h.fileSystem.set("b.mp3", stat: T.stat(10, 1), fingerprint: Data([1]))
        _ = try await h.scanner.scanOnce(rootID: h.rootID)
        let rows = try h.tracks()
        XCTAssertEqual(rows.map(\.id), [self.a, self.b])
        XCTAssertEqual(rows.first?.history, self.history)
        XCTAssertEqual(h.loader.callCount, 2)
    }

    func testContentReplacedAtPathKeepsRow() async throws {
        let h = try await ScanHarness.make(self)
        try T.seedTrack(
            h.container,
            id: self.a,
            rootID: h.rootID,
            path: "a.mp3",
            stat: T.stat(10, 1),
            history: self.history,
            fingerprint: Data([1])
        )
        await h.fileSystem.set("a.mp3", stat: T.stat(99, 9), fingerprint: Data([9]))
        _ = try await h.scanner.scanOnce(rootID: h.rootID)
        let rows = try h.tracks()
        XCTAssertEqual(rows.map(\.id), [self.a])
        XCTAssertEqual(rows.first?.fingerprint, Data([9]))
        XCTAssertEqual(rows.first?.fileSize, 99)
        XCTAssertEqual(rows.first?.history, self.history)
    }

    func testCaseOnlyRenameKeepsRowOnBothVolumeKinds() async throws {
        for caseSensitive in [false, true] {
            let h = try await ScanHarness.make(self)
            await h.fileSystem.configure(caseSensitive: caseSensitive)
            try T.seedTrack(
                h.container,
                id: self.a,
                rootID: h.rootID,
                path: "Techno/Song.mp3",
                stat: T.stat(10, 1),
                history: self.history,
                fingerprint: Data([1])
            )
            await h.fileSystem.set("techno/song.mp3", stat: T.stat(10, 1), fingerprint: Data([1]))
            _ = try await h.scanner.scanOnce(rootID: h.rootID)
            let rows = try h.tracks()
            XCTAssertEqual(rows.map(\.id), [self.a], "caseSensitive: \(caseSensitive)")
            XCTAssertEqual(rows.map(\.relativePath), ["techno/song.mp3"], "caseSensitive: \(caseSensitive)")
        }
    }

    /// Update-before-insert and hard-link inventories plus 300 unrelated files, interrupted after the structure
    /// save and around every batch boundary, reach the uninterrupted result on retry.
    func testInterruptionAtEveryBatchBoundaryMatchesUninterrupted() async throws {
        let reference = try await self.runInventory(interruptAt: nil)
        XCTAssertEqual(reference.count, 305)
        XCTAssertEqual(reference.first { $0.relativePath == "B.mp3" }?.id, self.a.uuidString)
        XCTAssertEqual(reference.first { $0.relativePath == "H.mp3" }?.isMissing, true)
        // 303 parses at batch size 200: call 1 = right after the structure save, 200/201 straddle the boundary.
        for interruptAt in [1, 2, 200, 201, 202, 303] {
            let retried = try await self.runInventory(interruptAt: interruptAt)
            XCTAssertEqual(retried, reference, "interrupted at parse call \(interruptAt)")
        }
    }

    // MARK: - Inventory

    private struct Normalized: Equatable {
        let relativePath: String
        /// Original ids kept; freshly minted ids are compared by path only.
        let id: String
        let title: String
        let isMissing: Bool
        let history: LibraryHistory
    }

    private func runInventory(interruptAt: Int?) async throws -> [Normalized] {
        let storeURL = try T.temporaryDirectory(self).appendingPathComponent("Library.store")
        let first = try await ScanHarness.make(self, storeURL: storeURL)
        let k = T.stat(1000, 10), k2 = T.stat(2000, 20), k3 = T.stat(3000, 30)
        try T.seedTrack(
            first.container,
            id: self.a,
            rootID: first.rootID,
            path: "A.mp3",
            stat: k,
            history: self.history,
            fingerprint: Data([1])
        )
        try T.seedTrack(first.container, id: self.x, rootID: first.rootID, path: "X.mp3", stat: k, fingerprint: Data([1]))
        try T.seedTrack(
            first.container,
            id: self.hardLinked,
            rootID: first.rootID,
            path: "H.mp3",
            stat: k3,
            history: self.history,
            fingerprint: Data([3])
        )
        let fileSystem = first.fileSystem
        await fileSystem.set("B.mp3", stat: k, fingerprint: Data([1])) // A renamed, content unchanged
        await fileSystem.set("X.mp3", stat: k2, fingerprint: Data([2])) // X modified
        await fileSystem.set("H1.mp3", stat: k3, fingerprint: Data([3])) // H renamed + hard link
        await fileSystem.set("H2.mp3", stat: k3, fingerprint: Data([3]))
        for index in 0 ..< 300 {
            await fileSystem.set(String(format: "New/%03d.mp3", index), stat: T.stat(Int64(10000 + index), 1), fingerprint: Data([4]))
        }

        if let interruptAt {
            first.loader.interrupt(atCall: interruptAt)
            do {
                _ = try await Task { try await first.scanner.scanOnce(rootID: first.rootID) }.value
                XCTFail("interruption at \(interruptAt) should end the run")
            } catch {}
            // Relaunch: a fresh container and store on the same file, same file-system state.
            let second = try await ScanHarness.make(
                self,
                storeURL: storeURL,
                rootURL: first.rootURL,
                rootID: first.rootID,
                fileSystem: fileSystem
            )
            _ = try await second.scanner.scanOnce(rootID: second.rootID)
            return try self.normalize(second.tracks())
        }
        _ = try await first.scanner.scanOnce(rootID: first.rootID)
        return try self.normalize(first.tracks())
    }

    private func normalize(_ rows: [LibraryTestSupport.TrackState]) -> [Normalized] {
        let original: Set<UUID> = [self.a, self.x, self.hardLinked]
        return rows.map {
            Normalized(
                relativePath: $0.relativePath,
                id: original.contains($0.id) ? $0.id.uuidString : "new",
                title: $0.title, isMissing: $0.isMissing, history: $0.history
            )
        }
    }
}
