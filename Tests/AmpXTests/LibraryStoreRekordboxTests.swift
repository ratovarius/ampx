@testable import AmpX
import SwiftData
import XCTest

/// Store side of the rekordbox sync (rekordbox sync spec § `LibraryStore.applyRekordbox`, § Data model).
final class LibraryStoreRekordboxTests: XCTestCase {
    private typealias T = LibraryTestSupport
    private let dj = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
    private let other = UUID(uuidString: "00000000-0000-0000-0000-0000000000D2")!
    private let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let b = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let stamp = RekordboxFileStamp(size: 40, modifiedAt: Date(timeIntervalSince1970: 1000))

    private var container: ModelContainer!

    override func setUpWithError() throws {
        self.container = try LibraryContainerFactory.make(url: nil)
        try T.seedRoot(self.container, id: self.dj, path: "/Music/DJ")
        try T.seedRoot(self.container, id: self.other, path: "/Music/Other")
        try T.seedTrack(self.container, id: self.a, rootID: self.dj, path: "a.mp3")
        try T.seedTrack(self.container, id: self.b, rootID: self.other, path: "b.mp3")
    }

    private func values(bpm: Double = 126, key: String = "Fm", label: String? = "L") -> RekordboxRowValues {
        RekordboxRowValues(
            bpm: bpm, musicalKey: key, analysisSource: .rekordbox, rating: 3, ratingSource: .rekordbox,
            rekordboxPlayCount: 4, label: label, remixer: nil, composer: nil, grouping: nil, mix: nil, beatGrid: Data([1])
        )
    }

    private func plan(_ writes: [RekordboxRowWrite], matched: Int? = nil) -> RekordboxImportPlan {
        var report = RekordboxSyncReport(fileName: "collection.xml")
        report.matched = matched ?? writes.count
        report.updated = writes.count
        return RekordboxImportPlan(writes: writes, report: report)
    }

    private func track(_ id: UUID) throws -> LibraryTrack {
        try XCTUnwrap(try ModelContext(self.container).fetch(FetchDescriptor<LibraryTrack>()).first { $0.id == id })
    }

    func testSnapshotIncludesUnavailableRoots() async throws {
        let context = ModelContext(self.container)
        try XCTUnwrap(try context.fetch(FetchDescriptor<LibraryRoot>()).first { $0.id == self.other }).isAvailable = false
        try context.save()
        let store = T.makeStore(self, container: self.container)

        let snapshot = try await store.rekordboxSnapshot(caseSensitivity: [self.dj: false])

        XCTAssertEqual(Set(snapshot.roots.map(\.id)), [self.dj, self.other])
        XCTAssertEqual(snapshot.roots.first { $0.id == self.dj }?.path, "/Music/DJ")
        XCTAssertEqual(snapshot.roots.first { $0.id == self.dj }?.caseSensitive, false)
        XCTAssertEqual(snapshot.roots.first { $0.id == self.other }?.caseSensitive, true)
        XCTAssertEqual(Set(snapshot.rows.map(\.id)), [self.a, self.b])
    }

    func testApplyWritesValuesAndDerivesCamelot() async throws {
        let store = T.makeStore(self, container: self.container)
        let token = try await store.beginRekordboxSync(rootID: self.dj)

        try await store.applyRekordbox(
            self.plan([RekordboxRowWrite(rowID: self.a, rootID: self.dj, values: self.values())]),
            fileName: "collection.xml", stamp: self.stamp, token: token
        )

        let track = try self.track(self.a)
        XCTAssertEqual(track.bpm, 126)
        XCTAssertEqual(track.musicalKey, "Fm")
        XCTAssertEqual(track.camelotKey, "4A")
        XCTAssertEqual(track.analysisSource, .rekordbox)
        XCTAssertEqual(track.rating, 3)
        XCTAssertEqual(track.ratingSource, .rekordbox)
        XCTAssertEqual(track.rekordboxPlayCount, 4)
        XCTAssertEqual(track.label, "L")
        XCTAssertEqual(track.beatGrid, Data([1]))
    }

    func testApplyUpsertsSourceWithStampAndReport() async throws {
        let store = T.makeStore(self, container: self.container)
        let token = try await store.beginRekordboxSync(rootID: self.dj)
        try await store.applyRekordbox(self.plan([], matched: 0), fileName: "collection.xml", stamp: self.stamp, token: token)
        let second = RekordboxFileStamp(size: 41, modifiedAt: Date(timeIntervalSince1970: 2000))
        try await store.applyRekordbox(self.plan([], matched: 0), fileName: "export.xml", stamp: second, token: token)

        let sources = try await store.rekordboxSources()
        XCTAssertEqual(sources.count, 1)
        let source = try XCTUnwrap(sources.first)
        XCTAssertEqual(source.rootID, self.dj)
        XCTAssertEqual(source.fileName, "export.xml")
        XCTAssertTrue(source.isPresent)
        XCTAssertEqual(source.stamp, second)
        XCTAssertEqual(source.lastImportAt, T.fixedDate)
        XCTAssertEqual(source.lastReport?.fileName, "collection.xml")
    }

    func testApplyPublishesPerRootChanges() async throws {
        let store = T.makeStore(self, container: self.container)
        var changes = await store.changes().makeAsyncIterator()
        let token = try await store.beginRekordboxSync(rootID: self.dj)

        try await store.applyRekordbox(self.plan([
            RekordboxRowWrite(rowID: self.a, rootID: self.dj, values: self.values()),
            RekordboxRowWrite(rowID: self.b, rootID: self.other, values: self.values()),
        ]), fileName: "collection.xml", stamp: self.stamp, token: token)

        var received: [LibraryChange] = []
        for _ in 0 ..< 3 {
            if let change = await changes.next() {
                received.append(change)
            }
        }
        XCTAssertEqual(Set(received.map(String.init(describing:))), Set([
            LibraryChange.rowsChanged(rootID: self.dj), .rowsChanged(rootID: self.other), .rekordboxSourcesChanged,
        ].map(String.init(describing:))))
    }

    func testRevokedTokenWritesNothing() async throws {
        let store = T.makeStore(self, container: self.container)
        let token = try await store.beginRekordboxSync(rootID: self.dj)
        await store.revokeRekordboxSync(rootID: self.dj)

        do {
            try await store.applyRekordbox(
                self.plan([RekordboxRowWrite(rowID: self.a, rootID: self.dj, values: self.values())]),
                fileName: "collection.xml", stamp: self.stamp, token: token
            )
            XCTFail("revoked")
        } catch {
            XCTAssertEqual(error as? LibraryStoreError, .revokedToken)
        }
        XCTAssertNil(try self.track(self.a).bpm)
        let sources = try await store.rekordboxSources()
        XCTAssertTrue(sources.isEmpty)
    }

    func testRemoveRootRevokesItsTokenOnly() async throws {
        let store = T.makeStore(self, container: self.container)
        let djToken = try await store.beginRekordboxSync(rootID: self.dj)
        let otherToken = try await store.beginRekordboxSync(rootID: self.other)

        try await store.removeRoot(id: self.other)

        do {
            try await store.applyRekordbox(self.plan([]), fileName: "x.xml", stamp: self.stamp, token: otherToken)
            XCTFail("revoked")
        } catch {
            XCTAssertEqual(error as? LibraryStoreError, .revokedToken)
        }
        try await store.applyRekordbox(
            self.plan([RekordboxRowWrite(rowID: self.a, rootID: self.dj, values: self.values())]),
            fileName: "collection.xml", stamp: self.stamp, token: djToken
        )
        XCTAssertEqual(try self.track(self.a).bpm, 126)
    }

    func testRelocateRootRevokesToken() async throws {
        let store = T.makeRootStore(container: self.container, scope: ScopeSpy(log: EventLog()), flag: FlagSpy(log: EventLog()))
        let token = try await store.beginRekordboxSync(rootID: self.dj)
        let moved = try T.temporaryDirectory(self)

        try await store.relocateRoot(id: self.dj, to: moved)

        do {
            try await store.applyRekordbox(self.plan([]), fileName: "x.xml", stamp: self.stamp, token: token)
            XCTFail("revoked")
        } catch {
            XCTAssertEqual(error as? LibraryStoreError, .revokedToken)
        }
    }

    func testRemoveRootDeletesSource() async throws {
        let store = T.makeStore(self, container: self.container)
        let token = try await store.beginRekordboxSync(rootID: self.dj)
        try await store.applyRekordbox(self.plan([]), fileName: "collection.xml", stamp: self.stamp, token: token)

        try await store.removeRoot(id: self.dj)

        let sources = try await store.rekordboxSources()
        XCTAssertTrue(sources.isEmpty)
    }

    func testMarkAbsentKeepsValuesAndReport() async throws {
        let store = T.makeStore(self, container: self.container)
        let token = try await store.beginRekordboxSync(rootID: self.dj)
        try await store.applyRekordbox(
            self.plan([RekordboxRowWrite(rowID: self.a, rootID: self.dj, values: self.values())]),
            fileName: "collection.xml", stamp: self.stamp, token: token
        )

        try await store.markRekordboxSourceAbsent(rootID: self.dj)
        try await store.markRekordboxSourceAbsent(rootID: self.other) // no source: no-op

        let sources = try await store.rekordboxSources()
        let source = try XCTUnwrap(sources.first)
        XCTAssertFalse(source.isPresent)
        XCTAssertEqual(source.stamp, self.stamp)
        XCTAssertEqual(source.lastReport?.updated, 1)
        XCTAssertEqual(try self.track(self.a).bpm, 126)
    }

    func testApplySkipsDeletedRows() async throws {
        let store = T.makeStore(self, container: self.container)
        let token = try await store.beginRekordboxSync(rootID: self.dj)
        try await store.applyRekordbox(
            self.plan([
                RekordboxRowWrite(rowID: UUID(), rootID: self.dj, values: self.values()),
                RekordboxRowWrite(rowID: self.a, rootID: self.dj, values: self.values()),
            ]),
            fileName: "collection.xml", stamp: self.stamp, token: token
        )
        XCTAssertEqual(try self.track(self.a).bpm, 126)
    }

    func testFailedSaveRollsBackRowsAndSource() async throws {
        let store = T.makeStore(self, container: self.container, saveContext: { _ in throw CocoaError(.fileWriteUnknown) })
        let token = try await store.beginRekordboxSync(rootID: self.dj)

        do {
            try await store.applyRekordbox(
                self.plan([RekordboxRowWrite(rowID: self.a, rootID: self.dj, values: self.values())]),
                fileName: "collection.xml", stamp: self.stamp, token: token
            )
            XCTFail("save fails")
        } catch {}

        XCTAssertNil(try self.track(self.a).bpm)
        let sources = try await store.rekordboxSources()
        XCTAssertTrue(sources.isEmpty)
    }

    func testBeginOnUnknownRootThrows() async {
        let store = T.makeStore(self, container: self.container)
        do {
            _ = try await store.beginRekordboxSync(rootID: UUID())
            XCTFail("unknown root")
        } catch {
            XCTAssertEqual(error as? LibraryStoreError, .unknownRoot)
        }
    }
}
