@testable import AmpX
import SwiftData
import XCTest

/// The composed Library window body (Library Module spec § Layout, Behaviour).
@MainActor
final class LibraryModuleContentTests: XCTestCase {
    private typealias T = LibraryTestSupport

    /// Every root walks to the same scripted entries.
    private struct StaticFileSystem: LibraryFileSystem {
        let entries: [String]

        func volume(at _: URL) async throws -> LibraryVolume {
            LibraryVolume(caseSensitive: true, typeName: "apfs")
        }

        func walk(root _: URL, volume: LibraryVolume) async throws -> LibraryWalk {
            LibraryWalk(
                entries: self.entries.enumerated().map { LibraryEntry(relativePath: $1, stat: T.stat(Int64(1000 + $0), 1)) },
                coverage: .complete, volume: volume
            )
        }

        func stat(at url: URL) async throws -> LibraryStat {
            let index = self.entries.firstIndex { url.path.hasSuffix("/" + $0) } ?? 0
            return T.stat(Int64(1000 + index), 1)
        }

        func fingerprint(at _: URL) async throws -> Data {
            Data([1])
        }

        func isReachable(_ root: URL) async -> Bool {
            FileManager.default.fileExists(atPath: root.path)
        }
    }

    private final class FakePanels: LibraryPanelPresenting {
        var folder: URL?
        var confirm = true
        private(set) var confirmations: [(String, String)] = []
        private(set) var errors: [String] = []

        func chooseFolder(title _: String) async -> URL? {
            self.folder
        }

        func confirmRemove(message: String, info: String) async -> Bool {
            self.confirmations.append((message, info))
            return self.confirm
        }

        func showError(_ message: String) {
            self.errors.append(message)
        }
    }

    private var directory: URL!
    private var storeURL: URL!
    private var flag: FlagSpy!
    private var panels: FakePanels!
    private var audio: MockAudioPlayer!
    private var playlist: PlaylistManager!
    private var defaults: UserDefaults!
    private var controllers: [LibraryController] = []
    private var contents: [LibraryModuleContent] = []

    override func setUpWithError() throws {
        self.directory = try T.temporaryDirectory(self)
        self.storeURL = self.directory.appendingPathComponent("Store/Library.store")
        self.flag = FlagSpy(log: EventLog())
        self.panels = FakePanels()
        self.audio = MockAudioPlayer()
        self.defaults = T.isolatedDefaults(self)
        self.playlist = PlaylistManager(
            audioPlayer: self.audio, restoreBookmarks: false, restorePlaylist: false,
            bookmarkStore: SecurityScopedBookmarkStore(userDefaults: T.isolatedDefaults(self)),
            stateStore: PlaylistStateStore(userDefaults: T.isolatedDefaults(self)), alertPresenter: SilentPlaylistAlertPresenter()
        )
    }

    override func tearDown() async throws {
        self.contents.forEach { $0.windowDidClose() }
        for controller in self.controllers {
            await controller.stop()
        }
    }

    private func makeController(entries: [String] = ["a.mp3", "b.mp3", "c.mp3"]) -> LibraryController {
        let scope = ScopeSpy()
        var configuration = LibraryEngineConfiguration(
            startupFlag: self.flag, bookmarkStore: SecurityScopedBookmarkStore(userDefaults: T.isolatedDefaults(self))
        )
        configuration.storeURL = self.storeURL
        configuration.fileSystem = StaticFileSystem(entries: entries)
        configuration.loadMetadata = FakeMetadataLoader().load
        configuration.watcherLatency = 0.1
        configuration.storeDependencies = { flag in
            var dependencies = LibraryStoreDependencies(startupFlag: flag)
            dependencies.scope = scope.scope
            dependencies.bookmarks = LibraryTestSupport.plainBookmarks
            return dependencies
        }
        let controller = LibraryController(configuration: configuration)
        self.controllers.append(controller)
        return controller
    }

    private func makeContent(controller: LibraryController?) -> LibraryModuleContent {
        let content = LibraryModuleContent(
            skin: ClassicModernSkin(), controller: controller, playlist: self.playlist, audioPlayer: nil,
            panels: self.panels, defaults: self.defaults
        )
        content.frame = CGRect(origin: .zero, size: CGSize(width: 1000, height: 470))
        content.layoutSubtreeIfNeeded()
        self.contents.append(content)
        return content
    }

    private func folder(_ name: String) throws -> URL {
        let url = self.directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Waits (bounded) until `condition` holds, yielding to let tasks and streams run.
    private func eventually(_ condition: () -> Bool, timeout: TimeInterval = 5, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "condition not met in \(timeout) s", line: line)
    }

    /// A content whose engine has one root with the given entries, scanned and shown.
    private func readyContent(entries: [String] = ["a.mp3", "b.mp3", "c.mp3"]) async throws
        -> (LibraryModuleContent, LibraryController, UUID)
    {
        let controller = self.makeController(entries: entries)
        let content = self.makeContent(controller: controller)
        let engine = try await controller.ensureEngine()
        let rootID = try await engine.addRoot(url: self.folder("DJ"))
        await engine.waitUntilIdle()
        await self.eventually { content.table.rows.count == entries.count }
        return (content, controller, rootID)
    }

    // MARK: - Layout

    func testFramesAtMinimumDefaultWide() {
        for size in [CGSize(width: 910, height: 391.5), CGSize(width: 1000, height: 471.5), CGSize(width: 1800, height: 900)] {
            let frames = LibraryModuleLayout.frames(size: size)
            let all = [frames.toolbar, frames.genre, frames.artist, frames.table, frames.sidebar, frames.footer]
            let bounds = CGRect(origin: .zero, size: size)
            XCTAssertTrue(all.allSatisfy { bounds.contains($0) && $0.width > 0 && $0.height > 0 }, "\(size)")
            XCTAssertEqual(frames.genre.width, 230)
            XCTAssertEqual(frames.sidebar.width, LibraryMixesSidebarView.width)
            XCTAssertGreaterThanOrEqual(frames.table.width, 370, "\(size)")
            XCTAssertLessThanOrEqual(frames.genre.maxX, frames.table.minX)
            XCTAssertLessThanOrEqual(frames.table.maxX, frames.sidebar.minX)
            XCTAssertLessThanOrEqual(frames.genre.maxY, frames.artist.minY)
            XCTAssertLessThanOrEqual(frames.toolbar.maxY, frames.table.minY)
            XCTAssertLessThanOrEqual(frames.table.maxY, frames.footer.minY)
        }
    }

    // MARK: - Query mapping

    func testQueryIgnoresMarkedText() {
        let content = self.makeContent(controller: nil)
        let search = content.toolbar.search
        search.insertText("caf", replacementRange: NSRange(location: NSNotFound, length: 0))
        search.setMarkedText(
            "´",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(content.filter.search, "caf")
        search.insertText("é", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(content.filter.search, "café")
    }

    func testSearchFacetBpmMissingDriveQuery() {
        let content = self.makeContent(controller: nil)
        content.toolbar.search.insertText("deep", replacementRange: NSRange(location: NSNotFound, length: 0))
        content.genreList.counts = [.text("House"): 3, .text("Techno"): 2]
        content.genreList.onClick?(.text("House"), false)
        content.toolbar.bpmMin.insertText("130", replacementRange: NSRange(location: NSNotFound, length: 0))
        content.toolbar.bpmMin.insertNewline(nil)
        content.toolbar.bpmMax.insertText("120", replacementRange: NSRange(location: NSNotFound, length: 0))
        content.toolbar.bpmMax.insertNewline(nil)
        content.footer.onToggleMissing?()
        content.table.onSortClick?(.bpm)
        let query = content.filter.query
        XCTAssertEqual(query.search, "deep")
        XCTAssertEqual(query.genres, [.text("House")])
        XCTAssertEqual(query.bpmRange, 120 ... 130)
        XCTAssertTrue(query.onlyUnavailable)
        XCTAssertEqual(query.sort, .bpm)
        XCTAssertEqual(content.genreList.selected, [.text("House")])

        content.toolbar.clearButton.action?()
        XCTAssertEqual(content.filter.query, LibraryQuery(sort: .bpm))
        XCTAssertEqual(content.toolbar.search.committedText, "")
    }

    func testFooterShowsScanOnlyWhileRunning() {
        let id = UUID()
        let walking = ScanProgress(rootID: id, phase: .walking, done: 0, total: 0)
        XCTAssertEqual(LibraryModuleContent.displayedProgress(walking), walking)
        XCTAssertNil(LibraryModuleContent.displayedProgress(ScanProgress(rootID: id, phase: .parsing, done: 3, total: 3)))
        XCTAssertNil(LibraryModuleContent.displayedProgress(ScanProgress(rootID: id, phase: .finished, done: 0, total: 0)))
        XCTAssertNil(LibraryModuleContent.displayedProgress(nil))
    }

    // MARK: - Actions

    func testDoubleClickReplacesAndPlays() async throws {
        let (content, _, _) = try await self.readyContent()
        self.playlist.addTracks([Track(title: "Old", artist: "Old")])
        let target = content.table.rows[1]
        content.table.onActivate?(target.id)
        await self.eventually { self.playlist.tracks.map(\.title) == [target.title] }
        XCTAssertEqual(self.audio.loadTrackCalls.last?.title, target.title)
    }

    func testEnqueueAppendsSelection() async throws {
        let (content, _, _) = try await self.readyContent()
        self.playlist.addTracks([Track(title: "Old", artist: "Old")])
        var selection = LibrarySelection()
        selection.selectAll(order: content.table.rows.map(\.id))
        content.table.selection = selection
        content.table.onSelectionChange?(selection)
        content.footer.enqueueButton.action?()
        await self.eventually { self.playlist.tracks.count == 4 }
        XCTAssertEqual(self.playlist.tracks.first?.title, "Old")
        XCTAssertTrue(self.audio.loadTrackCalls.isEmpty)
    }

    func testSelectAllEnqueuesInDisplayOrder() async {
        let rows = (0 ..< 11000).map { index in
            LibraryRow(
                id: UUID(), rootID: UUID(), url: URL(fileURLWithPath: "/Music/\(index).mp3"),
                title: String(format: "%05d", index), artist: "Artist", album: "", albumArtist: "",
                genre: nil, trackNumber: nil, duration: 60, fileSize: 1, bpm: nil, musicalKey: nil,
                bitrate: 0, bitrateIsDerived: false, codec: "mp3", isAvailable: true,
                searchKey: String(format: "%05d", index)
            )
        }
        let services = LibraryBrowserServices(
            query: { query, generation in query.evaluate(rows: rows, snapshotVersion: 0, generation: generation) },
            rows: { ids in rows.filter { ids.contains($0.id) } },
            versions: { AsyncStream { _ in } },
            progress: { AsyncStream { _ in } },
            roots: { [] }
        )
        let content = self.makeContent(controller: nil)
        content.attach(model: LibraryBrowserModel(services: services, playlist: self.playlist, bookmarkStore: .shared, beep: {}))
        content.table.onSortClick?(.title)
        await self.eventually { content.table.rows.count == 11000 }

        let start = ContinuousClock.now
        content.selectAllRows()
        await content.enqueueSelection(append: false)
        let elapsed = (ContinuousClock.now - start) / .seconds(1)
        XCTAssertEqual(self.playlist.tracks.count, 11000)
        XCTAssertEqual(self.playlist.tracks.prefix(3).map(\.title), ["00000", "00001", "00002"])
        XCTAssertLessThan(elapsed, 1)
    }

    // MARK: - States and roots

    func testEmptyStateThenAddFolderOpensEngine() async throws {
        let controller = self.makeController()
        let content = self.makeContent(controller: controller)
        await controller.startIfConfigured()
        XCTAssertTrue(content.isShowingEmptyState)
        // Drawn by the table: the content's own drawing sits under the opaque table.
        await self.eventually { content.table.placeholder == "No library folders yet" }
        self.panels.folder = try self.folder("DJ")
        await content.addFolder()
        XCTAssertEqual(controller.state, .ready)
        let roots = try await controller.engine?.roots()
        XCTAssertEqual(roots?.count, 1)
        await self.eventually { content.table.rows.count == 3 && !content.isShowingEmptyState }
        await self.eventually { content.table.placeholder == nil }
    }

    func testEngineErrorShowsErrorState() async throws {
        try FileManager.default.createDirectory(at: self.storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try LibraryTestSchemaV3.makeContainer(url: self.storeURL)
        self.flag.setHasRoots(true)
        let controller = self.makeController()
        let content = self.makeContent(controller: controller)
        await controller.startIfConfigured()
        await self.eventually { content.errorMessage != nil }
        XCTAssertEqual(content.errorMessage, "This library was saved by a newer version of AmpX and was left untouched.")
        await self.eventually { content.table.placeholder == content.errorMessage }
    }

    func testRemoveAsksAndRemoves() async throws {
        let (content, controller, rootID) = try await self.readyContent()
        self.panels.confirm = false
        await content.removeRoot(rootID)
        XCTAssertEqual(self.panels.confirmations.first?.0, "Remove \"DJ\" from the library?")
        XCTAssertEqual(
            self.panels.confirmations.first?.1,
            "Its 3 tracks and their ratings and play counts will be removed. The files are not deleted."
        )
        var roots = try await controller.engine?.roots()
        XCTAssertEqual(roots?.count, 1, "declined")
        self.panels.confirm = true
        await content.removeRoot(rootID)
        roots = try await controller.engine?.roots()
        XCTAssertEqual(roots?.count, 0)
    }

    func testOverlapErrorShown() async throws {
        let (content, _, _) = try await self.readyContent()
        self.panels.folder = self.directory.appendingPathComponent("DJ")
        await content.addFolder()
        XCTAssertEqual(self.panels.errors, ["That folder overlaps a folder already in the library."])
    }

    func testRootsMenuListsRoots() async throws {
        let (content, _, _) = try await self.readyContent()
        await self.eventually { content.rootsMenu().items.count == 3 }
        XCTAssertEqual(content.rootsMenu().items.last?.title, "DJ")
    }

    // MARK: - Persistence and lifetime

    func testPreferencesPersistColumnsSortMixesMode() {
        let content = self.makeContent(controller: nil)
        var columns = LibraryColumnSet.default
        columns.toggle(.number)
        content.table.onColumnsChange?(columns)
        content.table.onSortClick?(.genre)
        content.sidebar.selectedButton.action?()

        let reopened = self.makeContent(controller: nil)
        XCTAssertEqual(reopened.table.columns, columns)
        XCTAssertEqual(reopened.filter.query.sort, .genre)
        XCTAssertTrue(reopened.sidebar.followsSelection)
    }

    func testWindowCloseKeepsEngineRunning() async throws {
        let (content, controller, _) = try await self.readyContent()
        XCTAssertNotNil(content.model)
        content.windowDidClose()
        XCTAssertNil(content.model)
        XCTAssertNotNil(controller.engine)
    }

    // MARK: - rekordbox

    private func rekordboxContent() async -> (LibraryModuleContent, AsyncStream<RekordboxSyncState>.Continuation, LibraryRootSnapshot) {
        let root = LibraryRootSnapshot(
            id: UUID(), url: URL(fileURLWithPath: "/Music/DJ", isDirectory: true), displayPath: "/Music/DJ",
            isAvailable: true, unreadableFolderCount: 0, lastCompletedScanAt: nil
        )
        let services = LibraryBrowserServices(
            query: { query, generation in query.evaluate(rows: [], snapshotVersion: 0, generation: generation) },
            rows: { _ in [] },
            versions: { AsyncStream { _ in } },
            progress: { AsyncStream { _ in } },
            roots: { [root] }
        )
        let content = self.makeContent(controller: nil)
        content.attach(model: LibraryBrowserModel(services: services, playlist: self.playlist, bookmarkStore: .shared, beep: {}))
        await self.eventually { content.model?.roots.count == 1 }
        let (stream, continuation) = AsyncStream.makeStream(of: RekordboxSyncState.self)
        content.attachRekordbox(stream)
        return (content, continuation, root)
    }

    private func syncedState(_ root: LibraryRootSnapshot, matched: Int = 5) -> RekordboxSyncState {
        var report = RekordboxSyncReport(fileName: "collection.xml")
        report.matched = matched
        let source = RekordboxSourceSnapshot(
            rootID: root.id, fileName: "collection.xml", isPresent: true,
            stamp: RekordboxFileStamp(size: 1, modifiedAt: .distantPast), lastImportAt: Date(), lastReport: report
        )
        return RekordboxSyncState(status: .idle(lastSync: source.lastImportAt), sources: [source])
    }

    func testIndicatorAppearsAfterImport() async {
        let (content, states, root) = await self.rekordboxContent()
        XCTAssertTrue(content.footer.rekordboxButton.isHidden)
        states.yield(self.syncedState(root))
        await self.eventually { !content.footer.rekordboxButton.isHidden }
        XCTAssertTrue(content.footer.rekordboxButton.label?.hasPrefix("REKORDBOX ") == true)
    }

    func testRootsItemOpensReport() async throws {
        let (content, states, root) = await self.rekordboxContent()
        states.yield(self.syncedState(root, matched: 7))
        await self.eventually { content.rekordboxState.sources.count == 1 }
        let submenu = try XCTUnwrap(content.rootsMenu().items.first { $0.submenu != nil }?.submenu)
        let index = try XCTUnwrap(submenu.items.firstIndex { $0.title == "View rekordbox Report" })
        submenu.performActionForItem(at: index)
        XCTAssertFalse(content.reportView.isHidden)
        XCTAssertEqual(content.reportView.report?.matched, 7)
        content.reportView.closeButton.action?()
        XCTAssertTrue(content.reportView.isHidden)
    }

    func testIndicatorClickOpensLatestReport() async {
        let (content, states, root) = await self.rekordboxContent()
        states.yield(self.syncedState(root, matched: 3))
        await self.eventually { !content.footer.rekordboxButton.isHidden }
        content.footer.rekordboxButton.action?()
        XCTAssertFalse(content.reportView.isHidden)
        XCTAssertEqual(content.reportView.report?.matched, 3)
    }

    func testNoExportShowsNothing() async throws {
        let (content, states, _) = await self.rekordboxContent()
        states.yield(RekordboxSyncState(status: .hidden, sources: []))
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        XCTAssertTrue(content.footer.rekordboxButton.isHidden)
        XCTAssertTrue(content.reportView.isHidden)
        let submenu = try XCTUnwrap(content.rootsMenu().items.first { $0.submenu != nil }?.submenu)
        XCTAssertFalse(submenu.items.contains { $0.title.hasPrefix("rekordbox") || $0.title == "View rekordbox Report" })
        XCTAssertTrue(self.panels.errors.isEmpty)
    }
}
