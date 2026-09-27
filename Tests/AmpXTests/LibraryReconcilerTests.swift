@testable import AmpX
import XCTest

/// Pure reconciliation (spec: "Scanning", steps 1 and 3–4; Revision 5 ambiguity basis).
final class LibraryReconcilerTests: XCTestCase {
    private typealias T = LibraryTestSupport

    private let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let x = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let d = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private let z = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    private let fp = Data([1])
    private let k = LibraryTestSupport.stat(1000, 10)
    private let k2 = LibraryTestSupport.stat(2000, 20)

    // MARK: - Reviewed cases

    func testUpdateBeforeInsertMovesOnFirstRun() {
        let rows = [
            T.key(id: self.a, path: "A.mp3", stat: self.k, fingerprint: self.fp),
            T.key(id: self.x, path: "X.mp3", stat: self.k, fingerprint: self.fp),
        ]
        let walk = T.walk(entries: [T.entry(path: "B.mp3", stat: self.k), T.entry(path: "X.mp3", stat: self.k2)])
        let plan = LibraryReconciler.reconcile(rows: rows, walk: walk, fingerprints: ["B.mp3": self.fp])
        XCTAssertEqual(plan.moves, [LibraryMove(id: self.a, relativePath: "B.mp3")])
        XCTAssertEqual(plan.staleIDs, [self.x])
        XCTAssertTrue(plan.newEntries.isEmpty)
        XCTAssertEqual(plan.foundIDs, [self.a, self.x])
        XCTAssertTrue(plan.missingIDs.isEmpty)
    }

    func testHardLinksNeverMove() {
        let rows = [T.key(id: self.a, path: "A.mp3", stat: self.k, fingerprint: self.fp)]
        let entries = [T.entry(path: "B.mp3", stat: self.k), T.entry(path: "C.mp3", stat: self.k)]
        let first = LibraryReconciler.reconcile(
            rows: rows,
            walk: T.walk(entries: entries),
            fingerprints: ["B.mp3": self.fp, "C.mp3": self.fp]
        )
        XCTAssertTrue(first.moves.isEmpty)
        XCTAssertEqual(first.missingIDs, [self.a])
        XCTAssertEqual(first.newEntries.map(\.relativePath), ["B.mp3", "C.mp3"])

        // Interrupted after inserting B: B now matches by path, C is still ambiguous with it.
        let retryRows = rows + [T.key(id: self.x, path: "B.mp3", stat: self.k, fingerprint: self.fp)]
        let retry = LibraryReconciler.reconcile(rows: retryRows, walk: T.walk(entries: entries), fingerprints: ["C.mp3": self.fp])
        XCTAssertTrue(retry.moves.isEmpty)
        XCTAssertEqual(retry.missingIDs, [self.a])
        XCTAssertEqual(retry.newEntries.map(\.relativePath), ["C.mp3"])
    }

    // MARK: - Ambiguity basis

    func testMatchedEntryWithSameStatBlocksMove() {
        let rows = [
            T.key(id: self.a, path: "A.mp3", stat: self.k, fingerprint: self.fp),
            T.key(id: self.x, path: "X.mp3", stat: self.k2, fingerprint: self.fp),
        ]
        let walk = T.walk(entries: [T.entry(path: "B.mp3", stat: self.k), T.entry(path: "X.mp3", stat: self.k)])
        let plan = LibraryReconciler.reconcile(rows: rows, walk: walk, fingerprints: ["B.mp3": self.fp])
        XCTAssertTrue(plan.moves.isEmpty)
        XCTAssertEqual(plan.missingIDs, [self.a])
        XCTAssertEqual(plan.staleIDs, [self.x])
    }

    func testMatchedRowStoredStatIsIgnored() {
        // X's stored stat equals K but it was modified; only its walked K2 counts.
        let rows = [
            T.key(id: self.a, path: "A.mp3", stat: self.k, fingerprint: self.fp),
            T.key(id: self.x, path: "X.mp3", stat: self.k, fingerprint: self.fp),
        ]
        let walk = T.walk(entries: [T.entry(path: "B.mp3", stat: self.k), T.entry(path: "X.mp3", stat: self.k2)])
        XCTAssertEqual(LibraryReconciler.candidatePaths(rows: rows, walk: walk), ["B.mp3"])
    }

    func testTwoUnmatchedRowsBlockMove() {
        let rows = [
            T.key(id: self.a, path: "A.mp3", stat: self.k, fingerprint: self.fp),
            T.key(id: self.d, path: "D.mp3", stat: self.k, fingerprint: self.fp),
        ]
        let plan = LibraryReconciler.reconcile(
            rows: rows,
            walk: T.walk(entries: [T.entry(path: "B.mp3", stat: self.k)]),
            fingerprints: ["B.mp3": self.fp]
        )
        XCTAssertTrue(plan.moves.isEmpty)
        XCTAssertEqual(plan.missingIDs, [self.a, self.d])
        XCTAssertEqual(plan.newEntries.map(\.relativePath), ["B.mp3"])
    }

    func testMissingRowFromEarlierScanCountsInU() {
        let rows = [
            T.key(id: self.a, path: "A.mp3", stat: self.k, fingerprint: self.fp),
            T.key(id: self.d, path: "Gone.mp3", stat: self.k, fingerprint: self.fp, missing: true),
        ]
        let plan = LibraryReconciler.reconcile(
            rows: rows,
            walk: T.walk(entries: [T.entry(path: "B.mp3", stat: self.k)]),
            fingerprints: ["B.mp3": self.fp]
        )
        XCTAssertTrue(plan.moves.isEmpty)
    }

    func testNilRowFingerprintBlocksMove() {
        let rows = [T.key(id: self.a, path: "A.mp3", stat: self.k, fingerprint: nil)]
        let walk = T.walk(entries: [T.entry(path: "B.mp3", stat: self.k)])
        XCTAssertTrue(LibraryReconciler.candidatePaths(rows: rows, walk: walk).isEmpty)
        XCTAssertTrue(LibraryReconciler.reconcile(rows: rows, walk: walk, fingerprints: ["B.mp3": self.fp]).moves.isEmpty)
    }

    func testFingerprintMismatchBlocksMove() {
        let rows = [T.key(id: self.a, path: "A.mp3", stat: self.k, fingerprint: self.fp)]
        let plan = LibraryReconciler.reconcile(
            rows: rows,
            walk: T.walk(entries: [T.entry(path: "B.mp3", stat: self.k)]),
            fingerprints: ["B.mp3": Data([2])]
        )
        XCTAssertTrue(plan.moves.isEmpty)
        XCTAssertEqual(plan.missingIDs, [self.a])
        XCTAssertEqual(plan.newEntries.map(\.relativePath), ["B.mp3"])
    }

    func testUnreadableFingerprintBlocksMove() {
        let rows = [T.key(id: self.a, path: "A.mp3", stat: self.k, fingerprint: self.fp)]
        let plan = LibraryReconciler.reconcile(rows: rows, walk: T.walk(entries: [T.entry(path: "B.mp3", stat: self.k)]), fingerprints: [:])
        XCTAssertTrue(plan.moves.isEmpty)
    }

    func testRenameTrackingDisabledBlocksMove() {
        let rows = [T.key(id: self.a, path: "A.mp3", stat: self.k, fingerprint: self.fp)]
        let walk = T.walk(entries: [T.entry(path: "B.mp3", stat: self.k)], renameTracking: false)
        XCTAssertTrue(LibraryReconciler.candidatePaths(rows: rows, walk: walk).isEmpty)
        let plan = LibraryReconciler.reconcile(rows: rows, walk: walk, fingerprints: ["B.mp3": self.fp])
        XCTAssertTrue(plan.moves.isEmpty)
        XCTAssertEqual(plan.missingIDs, [self.a])
    }

    // MARK: - Coverage

    func testPartialWalkNeverMovesAndSetsAsideUncovered() {
        // Hidden-link case: A's absence is covered, B is seen, a link C may sit in unreadable "z".
        let rows = [
            T.key(id: self.a, path: "x/A.mp3", stat: self.k, fingerprint: self.fp),
            T.key(id: self.z, path: "z/Old.mp3", stat: self.k2, fingerprint: self.fp),
        ]
        let walk = T.walk(entries: [T.entry(path: "y/B.mp3", stat: self.k)], coverage: .partial(uncoveredFolders: ["z"]))
        XCTAssertTrue(LibraryReconciler.candidatePaths(rows: rows, walk: walk).isEmpty)
        let plan = LibraryReconciler.reconcile(rows: rows, walk: walk, fingerprints: ["y/B.mp3": self.fp])
        XCTAssertTrue(plan.moves.isEmpty)
        XCTAssertEqual(plan.missingIDs, [self.a])
        XCTAssertFalse(plan.foundIDs.contains(self.z))
        XCTAssertEqual(plan.newEntries.map(\.relativePath), ["y/B.mp3"])
    }

    func testUncoveredPrefixIsComponentAware() {
        let rows = [T.key(id: self.a, path: "crate/a.mp3", stat: self.k), T.key(id: self.d, path: "crate2/a.mp3", stat: self.k2)]
        let walk = T.walk(entries: [], coverage: .partial(uncoveredFolders: ["crate"]))
        let plan = LibraryReconciler.reconcile(rows: rows, walk: walk, fingerprints: [:])
        XCTAssertEqual(plan.missingIDs, [self.d])
    }

    func testUnreadableRootSetsEverythingAside() {
        let rows = [T.key(id: self.a, path: "crate/a.mp3", stat: self.k)]
        let plan = LibraryReconciler.reconcile(
            rows: rows,
            walk: T.walk(entries: [], coverage: .partial(uncoveredFolders: [""])),
            fingerprints: [:]
        )
        XCTAssertTrue(plan.missingIDs.isEmpty)
    }

    func testAbortedWalkIsEmpty() {
        let rows = [T.key(id: self.a, path: "A.mp3", stat: self.k, fingerprint: self.fp)]
        let plan = LibraryReconciler.reconcile(
            rows: rows,
            walk: T.walk(entries: [T.entry(path: "B.mp3", stat: self.k)], coverage: .aborted),
            fingerprints: ["B.mp3": self.fp]
        )
        XCTAssertEqual(plan, .empty)
    }

    // MARK: - Path keys

    func testContentReplacedAtPathKeepsRow() {
        let rows = [T.key(id: self.a, path: "A.mp3", stat: self.k, fingerprint: self.fp)]
        let plan = LibraryReconciler.reconcile(
            rows: rows,
            walk: T.walk(entries: [T.entry(path: "A.mp3", stat: self.k2)]),
            fingerprints: [:]
        )
        XCTAssertEqual(plan.foundIDs, [self.a])
        XCTAssertEqual(plan.staleIDs, [self.a])
        XCTAssertTrue(plan.newEntries.isEmpty)
    }

    func testCaseOnlyRenameOnCaseInsensitiveVolumeIsSpellingUpdate() {
        let rows = [T.key(id: self.a, path: "Techno/Song.mp3", stat: self.k, fingerprint: self.fp)]
        let walk = T.walk(entries: [T.entry(path: "techno/song.mp3", stat: self.k)], caseSensitive: false)
        let plan = LibraryReconciler.reconcile(rows: rows, walk: walk, fingerprints: [:])
        XCTAssertEqual(plan.spellingUpdates, [LibraryMove(id: self.a, relativePath: "techno/song.mp3")])
        XCTAssertTrue(plan.moves.isEmpty)
        XCTAssertTrue(plan.newEntries.isEmpty)
        XCTAssertTrue(plan.staleIDs.isEmpty)
    }

    func testCaseOnlyRenameOnCaseSensitiveVolumeUsesRenameRule() {
        let rows = [T.key(id: self.a, path: "Techno/Song.mp3", stat: self.k, fingerprint: self.fp)]
        let walk = T.walk(entries: [T.entry(path: "techno/song.mp3", stat: self.k)], caseSensitive: true)
        let plan = LibraryReconciler.reconcile(rows: rows, walk: walk, fingerprints: ["techno/song.mp3": self.fp])
        XCTAssertEqual(plan.moves, [LibraryMove(id: self.a, relativePath: "techno/song.mp3")])
        XCTAssertTrue(plan.spellingUpdates.isEmpty)
    }

    func testNFDSpellingMatchesNFCRow() {
        let nfc = "Beyonc\u{00E9}.mp3"
        let nfd = "Beyonce\u{0301}.mp3"
        let rows = [T.key(id: self.a, path: nfc, stat: self.k)]
        let plan = LibraryReconciler.reconcile(rows: rows, walk: T.walk(entries: [T.entry(path: nfd, stat: self.k)]), fingerprints: [:])
        XCTAssertEqual(plan.foundIDs, [self.a])
        XCTAssertTrue(plan.newEntries.isEmpty)
        XCTAssertTrue(plan.missingIDs.isEmpty)
        XCTAssertEqual(plan.spellingUpdates, [LibraryMove(id: self.a, relativePath: nfd)])
    }

    func testCandidatePathsMatchReconcileEligibility() {
        let rows = [
            T.key(id: self.a, path: "A.mp3", stat: self.k, fingerprint: self.fp),
            T.key(id: self.x, path: "X.mp3", stat: self.k2, fingerprint: self.fp),
        ]
        let walk = T.walk(entries: [T.entry(path: "B.mp3", stat: self.k), T.entry(path: "C.mp3", stat: self.k2)])
        XCTAssertEqual(LibraryReconciler.candidatePaths(rows: rows, walk: walk), ["B.mp3", "C.mp3"])
        let plan = LibraryReconciler.reconcile(rows: rows, walk: walk, fingerprints: ["B.mp3": self.fp, "C.mp3": self.fp])
        XCTAssertEqual(plan.moves, [LibraryMove(id: self.a, relativePath: "B.mp3"), LibraryMove(id: self.x, relativePath: "C.mp3")])
    }

    // MARK: - Integrity repair

    func testMergeTwoDuplicates() {
        let rows = [
            T.key(
                id: self.x,
                path: "A.mp3",
                stat: self.k,
                history: LibraryHistory(playCount: 3, lastPlayedAt: Date(timeIntervalSince1970: 50), rating: 0),
                dateAdded: Date(timeIntervalSince1970: 2)
            ),
            T.key(
                id: self.a,
                path: "A.mp3",
                stat: self.k,
                history: LibraryHistory(playCount: 1, lastPlayedAt: nil, rating: 4),
                dateAdded: Date(timeIntervalSince1970: 1)
            ),
        ]
        XCTAssertEqual(LibraryReconciler.integrityMerges(rows: rows, caseSensitive: true), [
            LibraryIntegrityMerge(
                survivorID: self.a,
                deletedIDs: [self.x],
                history: LibraryHistory(playCount: 3, lastPlayedAt: Date(timeIntervalSince1970: 50), rating: 4)
            ),
        ])
    }

    func testMergeThreeDuplicatesCombinesHistory() {
        let date = Date(timeIntervalSince1970: 1)
        let rows = [
            T.key(
                id: self.d,
                path: "song.mp3",
                stat: self.k,
                history: LibraryHistory(playCount: 9, lastPlayedAt: Date(timeIntervalSince1970: 10), rating: 5),
                dateAdded: Date(timeIntervalSince1970: 3)
            ),
            T.key(
                id: self.x,
                path: "Song.mp3",
                stat: self.k,
                history: LibraryHistory(playCount: 2, lastPlayedAt: Date(timeIntervalSince1970: 90), rating: 2),
                dateAdded: date
            ),
            T.key(
                id: self.a,
                path: "SONG.mp3",
                stat: self.k,
                history: LibraryHistory(playCount: 1, lastPlayedAt: nil, rating: 0),
                dateAdded: date
            ),
        ]
        // Tie on dateAdded → smallest id (a) survives; its rating is 0 → first non-zero by (dateAdded, id): x's 2.
        XCTAssertEqual(LibraryReconciler.integrityMerges(rows: rows, caseSensitive: false), [
            LibraryIntegrityMerge(
                survivorID: self.a,
                deletedIDs: [self.x, self.d],
                history: LibraryHistory(playCount: 9, lastPlayedAt: Date(timeIntervalSince1970: 90), rating: 2)
            ),
        ])
        XCTAssertTrue(LibraryReconciler.integrityMerges(rows: rows, caseSensitive: true).isEmpty)
    }

    func testPathKeyFoldsCaseOnlyWhenInsensitive() {
        XCTAssertEqual(LibraryReconciler.pathKey("A/B.MP3", caseSensitive: false), "a/b.mp3")
        XCTAssertEqual(LibraryReconciler.pathKey("A/B.MP3", caseSensitive: true), "A/B.MP3")
        XCTAssertEqual(LibraryReconciler.pathKey("e\u{0301}", caseSensitive: true), "\u{00E9}")
    }
}
