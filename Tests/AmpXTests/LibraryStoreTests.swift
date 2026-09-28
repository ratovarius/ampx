@testable import AmpX
import SwiftData
import XCTest

/// `LibraryStore` transactions (spec: "Scanning" steps 1, 5–7; "Change publication").
final class LibraryStoreTests: XCTestCase {
    private typealias T = LibraryTestSupport
    private let rootID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let b = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let c = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    private var container: ModelContainer!

    override func setUpWithError() throws {
        self.container = try LibraryContainerFactory.make(url: nil)
        try T.seedRoot(self.container, id: self.rootID)
    }

    func testInsertUpdateRoundTripPreservesHistoryAndDateAdded() async throws {
        let history = LibraryHistory(playCount: 4, lastPlayedAt: Date(timeIntervalSince1970: 9), rating: 5)
        try T.seedTrack(
            self.container,
            id: self.a,
            rootID: self.rootID,
            path: "A.mp3",
            history: history,
            dateAdded: Date(timeIntervalSince1970: 3)
        )
        let store = T.makeStore(self, container: self.container)
        let token = try await store.beginScan(rootID: self.rootID)

        try await store.applyParsed([
            T.parseWrite(id: self.a, insert: false, path: "A.mp3", stat: T.stat(555, 2), title: "Updated"),
            T.parseWrite(id: self.b, insert: true, path: "B.mp3", title: "New"),
        ], token: token)

        let rows = try T.tracks(self.container)
        XCTAssertEqual(rows.map(\.title), ["Updated", "New"])
        XCTAssertEqual(rows[0].history, history)
        XCTAssertEqual(rows[0].dateAdded, Date(timeIntervalSince1970: 3))
        XCTAssertEqual(rows[0].fileSize, 555)
        XCTAssertEqual(rows[1].id, self.b)
        XCTAssertEqual(rows[1].dateAdded, T.fixedDate)
        XCTAssertEqual(rows[1].fingerprint, Data([7]))
        let keys = try await store.rowKeys(rootID: self.rootID)
        XCTAssertEqual(keys.first { $0.id == self.a }?.stat, T.stat(555, 2))
    }

    func testParsedMetadataFieldsAreStored() async throws {
        let store = T.makeStore(self, container: self.container)
        let token = try await store.beginScan(rootID: self.rootID)
        var write = T.parseWrite(id: self.a, insert: true, path: "A.flac")
        write = LibraryParseWrite(id: write.id, isInsert: true, relativePath: write.relativePath, stat: write.stat, metadata: {
            var metadata = write.metadata
            metadata.album = "Album"
            metadata.bpm = 128
            metadata.musicalKey = "Am"
            metadata.bitrate = 900_000
            metadata.bitrateIsDerived = true
            metadata.codec = "flac"
            return metadata
        }(), fingerprint: nil)
        try await store.applyParsed([write], token: token)

        let track = try XCTUnwrap(try ModelContext(self.container).fetch(FetchDescriptor<LibraryTrack>()).first)
        XCTAssertEqual(track.album, "Album")
        XCTAssertEqual(track.genre, "Techno")
        XCTAssertEqual(track.bpm, 128)
        XCTAssertEqual(track.musicalKey, "Am")
        XCTAssertEqual(track.bitrate, 900_000)
        XCTAssertTrue(track.bitrateIsDerived)
        XCTAssertEqual(track.codec, "flac")
        XCTAssertEqual(track.duration, 60)
        XCTAssertNil(track.contentFingerprint)
        XCTAssertEqual(track.schemaVersion, 2)
        XCTAssertEqual(track.analysisSource, .fileTag)
        XCTAssertEqual(track.camelotKey, "8A")
    }

    func testParsedWriteKeepsRekordboxBpmAndKey() async throws {
        try self.seedImported(source: .rekordbox)
        try await self.applyRetaggedWrite()

        let track = try XCTUnwrap(try ModelContext(self.container).fetch(FetchDescriptor<LibraryTrack>()).first)
        XCTAssertEqual(track.title, "Retitled")
        XCTAssertEqual(track.bpm, 126)
        XCTAssertEqual(track.musicalKey, "Fm")
        XCTAssertEqual(track.camelotKey, "4A")
        XCTAssertEqual(track.analysisSource, .rekordbox)
    }

    func testParsedWriteRefreshesFileTagValues() async throws {
        try self.seedImported(source: .fileTag)
        try await self.applyRetaggedWrite()

        let track = try XCTUnwrap(try ModelContext(self.container).fetch(FetchDescriptor<LibraryTrack>()).first)
        XCTAssertEqual(track.title, "Retitled")
        XCTAssertEqual(track.bpm, 120)
        XCTAssertEqual(track.musicalKey, "Am")
        XCTAssertEqual(track.camelotKey, "8A")
        XCTAssertEqual(track.analysisSource, .fileTag)
    }

    func testParsedWriteWithoutTagsClearsSource() async throws {
        try self.seedImported(source: .fileTag)
        let store = T.makeStore(self, container: self.container)
        let token = try await store.beginScan(rootID: self.rootID)
        try await store.applyParsed([T.parseWrite(id: self.a, insert: false, path: "A.mp3", title: "Plain")], token: token)

        let track = try XCTUnwrap(try ModelContext(self.container).fetch(FetchDescriptor<LibraryTrack>()).first)
        XCTAssertNil(track.bpm)
        XCTAssertNil(track.analysisSource)
        XCTAssertNil(track.camelotKey)
    }

    private func seedImported(source: AnalysisSource) throws {
        try T.seedTrack(self.container, id: self.a, rootID: self.rootID, path: "A.mp3")
        let context = ModelContext(self.container)
        let track = try XCTUnwrap(try context.fetch(FetchDescriptor<LibraryTrack>()).first)
        track.bpm = 126
        track.musicalKey = "Fm"
        track.camelotKey = "4A"
        track.analysisSource = source
        try context.save()
    }

    private func applyRetaggedWrite() async throws {
        let store = T.makeStore(self, container: self.container)
        let token = try await store.beginScan(rootID: self.rootID)
        let base = T.parseWrite(id: self.a, insert: false, path: "A.mp3", title: "Retitled")
        var metadata = base.metadata
        metadata.bpm = 120
        metadata.musicalKey = "Am"
        let write = LibraryParseWrite(
            id: base.id, isInsert: false, relativePath: base.relativePath, stat: base.stat, metadata: metadata, fingerprint: nil
        )
        try await store.applyParsed([write], token: token)
    }

    func testApplyParsedRejectsMoreThan200() async throws {
        let store = T.makeStore(self, container: self.container)
        let token = try await store.beginScan(rootID: self.rootID)
        let writes = (0 ..< 201).map { T.parseWrite(insert: true, path: "\($0).mp3") }
        do {
            try await store.applyParsed(writes, token: token)
            XCTFail("batches are at most 200 rows")
        } catch {
            XCTAssertEqual(error as? LibraryStoreError, .batchTooLarge(201))
        }
        try await store.applyParsed(Array(writes.prefix(200)), token: token)
        XCTAssertEqual(try T.tracks(self.container).count, 200)
    }

    func testInsertCollidingPathKeyThrows() async throws {
        try T.seedTrack(self.container, id: self.a, rootID: self.rootID, path: "Caf\u{00E9}.mp3")
        let store = T.makeStore(self, container: self.container)
        let token = try await store.beginScan(rootID: self.rootID)
        do {
            try await store.applyParsed([
                T.parseWrite(id: self.b, insert: true, path: "Other.mp3"),
                T.parseWrite(id: self.c, insert: true, path: "Cafe\u{0301}.mp3"),
            ], token: token)
            XCTFail("an insert at an existing path must never upsert")
        } catch {
            XCTAssertEqual(error as? LibraryStoreError, .pathCollision("Cafe\u{0301}.mp3"))
        }
        XCTAssertEqual(try T.tracks(self.container).map(\.id), [self.a])
    }

    func testStructureSaveIsAtomic() async throws {
        try T.seedTrack(self.container, id: self.a, rootID: self.rootID, path: "A.mp3")
        try T.seedTrack(self.container, id: self.b, rootID: self.rootID, path: "b.mp3")
        try T.seedTrack(self.container, id: self.c, rootID: self.rootID, path: "C.mp3")
        let store = T.makeStore(self, container: self.container)
        let token = try await store.beginScan(rootID: self.rootID)
        try await store.applyStructure(LibraryReconciliation(
            moves: [LibraryMove(id: self.a, relativePath: "Moved/A.mp3")],
            spellingUpdates: [LibraryMove(id: self.b, relativePath: "B.mp3")],
            foundIDs: [self.a, self.b], missingIDs: [self.c], newEntries: [], staleIDs: []
        ), token: token, unreadableFolderCount: 2)

        let rows = try T.tracks(self.container)
        XCTAssertEqual(rows.map(\.relativePath), ["B.mp3", "C.mp3", "Moved/A.mp3"])
        XCTAssertEqual(rows.map(\.isMissing), [false, true, false])
        let roots = try ModelContext(self.container).fetch(FetchDescriptor<LibraryRoot>())
        XCTAssertEqual(roots.first?.unreadableFolderCount, 2)
    }

    func testFoundClearsMissing() async throws {
        try T.seedTrack(self.container, id: self.a, rootID: self.rootID, path: "A.mp3")
        let store = T.makeStore(self, container: self.container)
        var token = try await store.beginScan(rootID: self.rootID)
        try await store.applyStructure(self.plan(missing: [self.a]), token: token, unreadableFolderCount: 0)
        token = try await store.beginScan(rootID: self.rootID)
        try await store.applyStructure(self.plan(found: [self.a]), token: token, unreadableFolderCount: 0)
        XCTAssertEqual(try T.tracks(self.container).first?.isMissing, false)
    }

    func testIntegrityMergeAppliesHistoryAndDeletes() async throws {
        try T.seedTrack(self.container, id: self.a, rootID: self.rootID, path: "A.mp3")
        try T.seedTrack(self.container, id: self.b, rootID: self.rootID, path: "A.mp3")
        let store = T.makeStore(self, container: self.container)
        let token = try await store.beginScan(rootID: self.rootID)
        let history = LibraryHistory(playCount: 8, lastPlayedAt: Date(timeIntervalSince1970: 77), rating: 3)
        try await store.applyIntegrityMerges(
            [LibraryIntegrityMerge(survivorID: self.a, deletedIDs: [self.b], history: history)],
            token: token
        )
        let rows = try T.tracks(self.container)
        XCTAssertEqual(rows.map(\.id), [self.a])
        XCTAssertEqual(rows.first?.history, history)
    }

    func testFailedSaveRollsBackAndPublishesNothing() async throws {
        try T.seedTrack(self.container, id: self.a, rootID: self.rootID, path: "A.mp3")
        let failures = SendableBox(1)
        let store = T.makeStore(self, container: self.container) { context in
            if failures.value > 0 {
                failures.value -= 1
                throw CocoaError(.fileWriteUnknown)
            }
            try context.save()
        }
        let changes = await store.changes()
        let token = try await store.beginScan(rootID: self.rootID)
        do {
            try await store.applyStructure(self.plan(missing: [self.a]), token: token, unreadableFolderCount: 0)
            XCTFail("injected save failure must propagate")
        } catch {}
        XCTAssertEqual(try T.tracks(self.container).first?.isMissing, false)

        // The next valid transaction starts clean and is the first change published.
        try await store.applyParsed([T.parseWrite(id: self.b, insert: true, path: "B.mp3")], token: token)
        XCTAssertEqual(try T.tracks(self.container).map(\.isMissing), [false, false])
        var iterator = changes.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first, .rowsChanged(rootID: self.rootID))
    }

    func testOneSaveCanPublishRootsAndRowsChanged() async throws {
        try T.seedTrack(self.container, id: self.a, rootID: self.rootID, path: "A.mp3")
        let store = T.makeStore(self, container: self.container)
        let changes = await store.changes()
        let token = try await store.beginScan(rootID: self.rootID)
        try await store.applyStructure(self.plan(missing: [self.a]), token: token, unreadableFolderCount: 1)
        var iterator = changes.makeAsyncIterator()
        var received: [LibraryChange] = []
        for _ in 0 ..< 2 {
            if let change = await iterator.next() {
                received.append(change)
            }
        }
        XCTAssertEqual(Set(received.map { "\($0)" }), ["rootsChanged(rootID: \(self.rootID))", "rowsChanged(rootID: \(self.rootID))"])
    }

    func testNoOpStructureSavePublishesNothing() async throws {
        try T.seedTrack(self.container, id: self.a, rootID: self.rootID, path: "A.mp3")
        let store = T.makeStore(self, container: self.container)
        let changes = await store.changes()
        let token = try await store.beginScan(rootID: self.rootID)
        try await store.applyStructure(self.plan(found: [self.a]), token: token, unreadableFolderCount: 0) // already found
        try await store.finishScan(token: token)
        var iterator = changes.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first, .rootsChanged(rootID: self.rootID)) // only finishScan's
    }

    func testTwoSubscribersBothReceive() async throws {
        let store = T.makeStore(self, container: self.container)
        let first = await store.changes()
        let second = await store.changes()
        let token = try await store.beginScan(rootID: self.rootID)
        try await store.applyParsed([T.parseWrite(insert: true, path: "A.mp3")], token: token)
        var one = first.makeAsyncIterator()
        var two = second.makeAsyncIterator()
        let received = await (one.next(), two.next())
        XCTAssertEqual(received.0, .rowsChanged(rootID: self.rootID))
        XCTAssertEqual(received.1, .rowsChanged(rootID: self.rootID))
    }

    func testFinishScanSetsLastCompletedScanAt() async throws {
        let store = T.makeStore(self, container: self.container)
        let token = try await store.beginScan(rootID: self.rootID)
        try await store.finishScan(token: token)
        let root = try XCTUnwrap(try ModelContext(self.container).fetch(FetchDescriptor<LibraryRoot>()).first)
        XCTAssertEqual(root.lastCompletedScanAt, T.fixedDate)
    }

    private func plan(found: Set<UUID> = [], missing: Set<UUID> = []) -> LibraryReconciliation {
        LibraryReconciliation(moves: [], spellingUpdates: [], foundIDs: found, missingIDs: missing, newEntries: [], staleIDs: [])
    }
}
