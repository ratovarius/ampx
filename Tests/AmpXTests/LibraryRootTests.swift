@testable import AmpX
import SwiftData
import XCTest

/// Spec: "Roots and security scope", "Start-up and cost".
final class LibraryRootTests: XCTestCase {
    private typealias T = LibraryTestSupport

    private var container: ModelContainer!
    private var directory: URL!
    private var log: EventLog!
    private var scope: ScopeSpy!
    private var flag: FlagSpy!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        self.container = try LibraryContainerFactory.make(url: nil)
        self.directory = try T.temporaryDirectory(self)
        self.log = EventLog()
        self.scope = ScopeSpy(log: self.log)
        self.flag = FlagSpy(log: self.log)
        self.store = T.makeRootStore(container: self.container, scope: self.scope, flag: self.flag)
    }

    // MARK: - Overlap

    func testAddRejectsEqualAncestorDescendantAndSymlinkAlias() async throws {
        let dj = try self.folder("Music/DJ")
        _ = try await self.store.addRoot(url: dj)
        let alias = self.directory.appendingPathComponent("Alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: dj)

        for candidate in try [dj, self.folder("Music"), self.folder("Music/DJ/Techno"), alias] {
            await self.assertOverlap { _ = try await self.store.addRoot(url: candidate) }
        }
        _ = try await self.store.addRoot(url: self.folder("Music/DJ2")) // sibling with a shared prefix is fine
        let roots = try await self.store.roots()
        XCTAssertEqual(roots.count, 2)
    }

    func testRelocateRejectsOverlapExcludingSelf() async throws {
        let first = try await self.store.addRoot(url: self.folder("A"))
        _ = try await self.store.addRoot(url: self.folder("B"))
        await self.assertOverlap { try await self.store.relocateRoot(id: first, to: self.folder("B/Inner")) }
        await self.assertOverlap { try await self.store.relocateRoot(id: first, to: self.directory) }
        try await self.store.relocateRoot(id: first, to: self.folder("A/Deeper")) // inside itself only
        let roots = try await self.store.roots()
        XCTAssertTrue(roots.contains { $0.id == first && $0.url.lastPathComponent == "Deeper" })
    }

    // MARK: - Tokens and availability

    func testMarkUnavailableRevokesRunningToken() async throws {
        let id = try await self.store.addRoot(url: self.folder("DJ"))
        let token = try await self.store.beginScan(rootID: id)
        try await self.store.markUnavailable(id: id)
        do {
            try await self.store.applyParsed([], token: token)
            XCTFail("Unmount must revoke the old run")
        } catch LibraryStoreError.revokedToken {}
        let roots = try await self.store.roots()
        XCTAssertEqual(roots.first?.isAvailable, false)
    }

    func testRelocateAndRemoveRevokeTokens() async throws {
        let id = try await self.store.addRoot(url: self.folder("DJ"))
        var token = try await self.store.beginScan(rootID: id)
        try await self.store.relocateRoot(id: id, to: self.folder("Moved"))
        await self.assertRevoked { try await self.store.applyParsed([], token: token) }
        token = try await self.store.beginScan(rootID: id)
        try await self.store.removeRoot(id: id)
        do {
            try await self.store.applyParsed([], token: token)
            XCTFail("removal must revoke")
        } catch {}
    }

    func testUnavailableKeepsIsMissing() async throws {
        let id = try await self.store.addRoot(url: self.folder("DJ"))
        try T.seedTrack(self.container, id: UUID(), rootID: id, path: "a.mp3")
        try await self.store.markUnavailable(id: id)
        XCTAssertEqual(try T.tracks(self.container).map(\.isMissing), [false])
    }

    func testResolveSuccessMarksAvailableAndStartsScopeOnce() async throws {
        let dj = try self.folder("DJ")
        let id = try await self.store.addRoot(url: dj)
        try await self.store.markUnavailable(id: id)
        for _ in 0 ..< 3 {
            let token = try await self.store.beginScan(rootID: id)
            let snapshot = try await self.store.resolveRoot(token: token)
            XCTAssertTrue(snapshot.isAvailable)
            XCTAssertEqual(snapshot.url.resolvingSymlinksInPath(), dj.resolvingSymlinksInPath())
        }
        XCTAssertEqual(self.scope.openCounts.values.reduce(0, +), 1, "repeated resolution must not leak scope counts")
    }

    func testResolveFailureSavesUnavailable() async throws {
        let dj = try self.folder("DJ")
        let id = try await self.store.addRoot(url: dj)
        try FileManager.default.removeItem(at: dj)
        let token = try await self.store.beginScan(rootID: id)
        do {
            _ = try await self.store.resolveRoot(token: token)
            XCTFail("a missing folder is unavailable")
        } catch {
            XCTAssertEqual(error as? LibraryStoreError, .unavailableRoot)
        }
        let roots = try await self.store.roots()
        XCTAssertEqual(roots.first?.isAvailable, false)
    }

    func testResolveFailsWhenScopeCannotStart() async throws {
        let id = try await self.store.addRoot(url: self.folder("DJ"))
        try await self.store.markUnavailable(id: id) // releases the scope taken by add
        self.scope.allowStart = false
        let token = try await self.store.beginScan(rootID: id)
        do {
            _ = try await self.store.resolveRoot(token: token)
            XCTFail("no access is unavailable, even though the URL resolved")
        } catch {}
        let roots = try await self.store.roots()
        XCTAssertEqual(roots.first?.isAvailable, false)
    }

    // MARK: - Relocate and remove

    func testRelocatePreservesRowsAndHistory() async throws {
        let id = try await self.store.addRoot(url: self.folder("Old"))
        let row = UUID()
        let history = LibraryHistory(playCount: 5, lastPlayedAt: Date(timeIntervalSince1970: 3), rating: 4)
        try T.seedTrack(self.container, id: row, rootID: id, path: "Techno/a.mp3", history: history)
        try await self.store.relocateRoot(id: id, to: self.folder("New"))

        let tracks = try T.tracks(self.container)
        XCTAssertEqual(tracks.map(\.id), [row])
        XCTAssertEqual(tracks.first?.relativePath, "Techno/a.mp3")
        XCTAssertEqual(tracks.first?.history, history)
        let roots = try await self.store.roots()
        XCTAssertEqual(roots.map(\.id), [id])
        XCTAssertEqual(roots.first?.url.lastPathComponent, "New")
        XCTAssertEqual(self.log.events.filter { $0.hasPrefix("st") }, ["start:Old", "stop:Old", "start:New"])
    }

    func testRemoveDeletesOnlyThatRootsRows() async throws {
        let first = try await self.store.addRoot(url: self.folder("A"))
        let second = try await self.store.addRoot(url: self.folder("B"))
        try T.seedTrack(self.container, id: UUID(), rootID: first, path: "a.mp3")
        try T.seedTrack(self.container, id: UUID(), rootID: second, path: "b.mp3")
        let changes = await self.store.changes()
        try await self.store.removeRoot(id: first)

        XCTAssertEqual(try T.tracks(self.container).map(\.relativePath), ["b.mp3"])
        let roots = try await self.store.roots()
        XCTAssertEqual(roots.map(\.id), [second])
        var iterator = changes.makeAsyncIterator()
        let change = await iterator.next()
        XCTAssertEqual(change, .rootRemoved(rootID: first))
        XCTAssertEqual(self.scope.openCounts.count, 1)
    }

    // MARK: - Start-up flag

    func testAddSetsFlagBeforeInsert() async throws {
        _ = try await self.store.addRoot(url: self.folder("DJ"))
        let events = self.log.events
        let flagIndex = try XCTUnwrap(events.firstIndex(of: "flag:true"))
        let saveIndex = try XCTUnwrap(events.firstIndex(of: "save"))
        XCTAssertLessThan(flagIndex, saveIndex)
        XCTAssertTrue(self.flag.hasRoots)
    }

    func testRemoveLastRootClearsFlagAfterSave() async throws {
        let id = try await self.store.addRoot(url: self.folder("DJ"))
        let before = self.log.events.count
        try await self.store.removeRoot(id: id)
        XCTAssertEqual(Array(self.log.events.dropFirst(before)).filter { $0 == "save" || $0.hasPrefix("flag") }, ["save", "flag:false"])
        XCTAssertFalse(self.flag.hasRoots)
    }

    func testRemoveNonLastRootKeepsFlag() async throws {
        let first = try await self.store.addRoot(url: self.folder("A"))
        _ = try await self.store.addRoot(url: self.folder("B"))
        try await self.store.removeRoot(id: first)
        XCTAssertTrue(self.flag.hasRoots)
        XCTAssertFalse(self.log.events.contains("flag:false"))
    }

    func testEmptyStoreSelfClearsFlag() async throws {
        self.flag.setHasRoots(true)
        let cleared = try await self.store.clearStartupFlagIfEmpty()
        XCTAssertTrue(cleared)
        XCTAssertFalse(self.flag.hasRoots)
        _ = try await self.store.addRoot(url: self.folder("DJ"))
        let clearedAgain = try await self.store.clearStartupFlagIfEmpty()
        XCTAssertFalse(clearedAgain)
        XCTAssertTrue(self.flag.hasRoots)
    }

    // MARK: - Scope lifetime

    func testScopeStartsOncePerRootAndStopsOnRemove() async throws {
        let id = try await self.store.addRoot(url: self.folder("DJ"))
        XCTAssertEqual(self.scope.openCounts.count, 1)
        try await self.store.removeRoot(id: id)
        XCTAssertTrue(self.scope.openCounts.isEmpty)
    }

    func testStartAccessAndStopAllBalanceScopes() async throws {
        let first = try await self.store.addRoot(url: self.folder("A"))
        _ = try await self.store.addRoot(url: self.folder("B"))
        try FileManager.default.removeItem(at: self.directory.appendingPathComponent("B"))
        await self.store.stopAllAccess()
        XCTAssertTrue(self.scope.openCounts.isEmpty)

        let available = try await self.store.startAccessForAvailableRoots()
        XCTAssertEqual(available.map(\.id), [first])
        XCTAssertEqual(self.scope.openCounts.count, 1)
        let roots = try await self.store.roots()
        XCTAssertEqual(roots.filter(\.isAvailable).map(\.id), [first])
        await self.store.stopAllAccess()
        XCTAssertTrue(self.scope.openCounts.isEmpty)
    }

    // MARK: - Helpers

    private func folder(_ relative: String) throws -> URL {
        let url = self.directory.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func assertOverlap(_ body: () async throws -> Void, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("expected overlappingRoot", line: line)
        } catch {
            XCTAssertEqual(error as? LibraryStoreError, .overlappingRoot, line: line)
        }
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
