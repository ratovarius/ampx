@testable import AmpX
import SwiftData
import XCTest

/// Spec: "Scan tokens" — revoked tokens are rejected by the store, whenever the save arrives.
final class LibraryScanTokenTests: XCTestCase {
    private typealias T = LibraryTestSupport
    private let rootID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private let rowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private var container: ModelContainer!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        self.container = try LibraryContainerFactory.make(url: nil)
        try T.seedRoot(self.container, id: self.rootID)
        try T.seedTrack(self.container, id: self.rowID, rootID: self.rootID, path: "A.mp3")
        self.store = T.makeStore(self, container: self.container)
    }

    func testRevokedTokenRejectsStructureAndParse() async throws {
        let changes = await self.store.changes()
        let token = try await self.store.beginScan(rootID: self.rootID)
        await self.store.revokeScan(rootID: self.rootID)

        await self.assertRevoked { try await self.store.applyStructure(self.missingPlan(), token: token, unreadableFolderCount: 3) }
        await self.assertRevoked { try await self.store.applyParsed([T.parseWrite(insert: true, path: "B.mp3")], token: token) }
        await self.assertRevoked { try await self.store.applyIntegrityMerges([], token: token) }
        await self.assertRevoked { try await self.store.finishScan(token: token) }

        XCTAssertEqual(try T.tracks(self.container).map(\.relativePath), ["A.mp3"])
        XCTAssertEqual(try T.tracks(self.container).first?.isMissing, false)
        // Nothing was published: the first change seen is from the next accepted save.
        let fresh = try await self.store.beginScan(rootID: self.rootID)
        try await self.store.applyStructure(self.missingPlan(), token: fresh, unreadableFolderCount: 0)
        var iterator = changes.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first, .rowsChanged(rootID: self.rootID))
    }

    func testReissuedTokenKeepsOldRejected() async throws {
        let old = try await self.store.beginScan(rootID: self.rootID)
        let new = try await self.store.beginScan(rootID: self.rootID)
        XCTAssertNotEqual(old, new)
        await self.assertRevoked { try await self.store.applyParsed([], token: old) }
        try await self.store.applyParsed([], token: new)
    }

    func testDeletedRootRejectsToken() async throws {
        let token = try await self.store.beginScan(rootID: self.rootID)
        let context = ModelContext(self.container)
        try context.delete(model: LibraryRoot.self)
        try context.save()
        do {
            try await self.store.applyParsed([T.parseWrite(insert: true, path: "B.mp3")], token: token)
            XCTFail("a save for a deleted root must be rejected")
        } catch {}
        XCTAssertEqual(try T.tracks(self.container).map(\.relativePath), ["A.mp3"])
    }

    func testUnknownRootCannotBeginScan() async {
        do {
            _ = try await self.store.beginScan(rootID: UUID())
            XCTFail("expected unknownRoot")
        } catch {
            XCTAssertEqual(error as? LibraryStoreError, .unknownRoot)
        }
    }

    func testLateWriteAfterReissueIsRejected() async throws {
        let old = try await self.store.beginScan(rootID: self.rootID)
        let barrier = TestBarrier()
        let store = try XCTUnwrap(self.store)
        let late = Task {
            await barrier.wait()
            try await store.applyParsed([LibraryTestSupport.parseWrite(insert: true, path: "Late.mp3")], token: old)
        }
        _ = try await self.store.beginScan(rootID: self.rootID) // remount / new run
        await barrier.open()
        do {
            try await late.value
            XCTFail("a save suspended across a reissue must be rejected")
        } catch {
            XCTAssertEqual(error as? LibraryStoreError, .revokedToken)
        }
        XCTAssertFalse(try T.tracks(self.container).contains { $0.relativePath == "Late.mp3" })
    }

    // MARK: - Helpers

    private func missingPlan() -> LibraryReconciliation {
        LibraryReconciliation(moves: [], spellingUpdates: [], foundIDs: [], missingIDs: [self.rowID], newEntries: [], staleIDs: [])
    }

    private func assertRevoked(_ body: () async throws -> Void, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("expected revokedToken", line: line)
        } catch {
            XCTAssertEqual(error as? LibraryStoreError, .revokedToken, line: line)
        }
    }
}
