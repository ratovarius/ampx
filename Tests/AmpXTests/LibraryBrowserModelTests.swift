@testable import AmpX
import XCTest

/// `LibraryBrowserModel` (spec: "Index and query semantics" — staleness/selection; "Actions").
@MainActor
final class LibraryBrowserModelTests: XCTestCase {
    /// Query service whose results the test delivers per generation, in any order.
    private final class ScriptedQueries: @unchecked Sendable {
        private let lock = NSLock()
        private var pending: [UInt64: CheckedContinuation<LibraryResult, Error>] = [:]
        private var count = 0

        var requestCount: Int {
            self.lock.withLock { self.count }
        }

        func query(_: LibraryQuery, _ generation: UInt64) async throws -> LibraryResult {
            try await withCheckedThrowingContinuation { continuation in
                self.lock.withLock {
                    self.count += 1
                    self.pending[generation] = continuation
                }
            }
        }

        func waitForRequest(_ generation: UInt64) async {
            while self.lock.withLock({ self.pending[generation] == nil }) {
                await Task.yield()
            }
        }

        func deliver(_ generation: UInt64, rows: [LibraryRow]) {
            let continuation = self.lock.withLock { self.pending.removeValue(forKey: generation) }
            continuation?.resume(returning: LibraryQuery().evaluate(rows: rows, snapshotVersion: 0, generation: generation))
        }

        func cancelAll() {
            let all = self.lock.withLock { () -> [CheckedContinuation<LibraryResult, Error>] in
                defer { self.pending.removeAll() }
                return Array(self.pending.values)
            }
            all.forEach { $0.resume(throwing: CancellationError()) }
        }
    }

    /// Immediate services over mutable rows: `current` answers queries, `latest` answers enqueue re-checks.
    private final class LiveRows: @unchecked Sendable {
        private let lock = NSLock()
        private var currentRows: [LibraryRow] = []
        private var latestRows: [LibraryRow]?
        var roots: [LibraryRootSnapshot] = []

        var current: [LibraryRow] {
            get { self.lock.withLock { self.currentRows } }
            set { self.lock.withLock { self.currentRows = newValue } }
        }

        var latest: [LibraryRow] {
            get { self.lock.withLock { self.latestRows ?? self.currentRows } }
            set { self.lock.withLock { self.latestRows = newValue } }
        }
    }

    private let rootID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private var scripted: ScriptedQueries!
    private var live: LiveRows!
    private var versions: AsyncStream<UInt64>.Continuation!
    private var beeps = 0
    private var audio: MockAudioPlayer!
    private var bookmarkDefaults: UserDefaults!
    private var bookmarkStore: SecurityScopedBookmarkStore!
    private var playlist: PlaylistManager!
    private var models: [LibraryBrowserModel] = []
    private var rootURL: URL!

    override func setUp() async throws {
        self.scripted = ScriptedQueries()
        self.live = LiveRows()
        self.audio = MockAudioPlayer()
        self.bookmarkDefaults = LibraryTestSupport.isolatedDefaults(self)
        self.bookmarkStore = SecurityScopedBookmarkStore(userDefaults: self.bookmarkDefaults)
        self.playlist = PlaylistManager(
            audioPlayer: self.audio,
            restoreBookmarks: false,
            restorePlaylist: false,
            bookmarkStore: self.bookmarkStore,
            stateStore: PlaylistStateStore(userDefaults: LibraryTestSupport.isolatedDefaults(self)),
            alertPresenter: SilentPlaylistAlertPresenter()
        )
        self.rootURL = try LibraryTestSupport.temporaryDirectory(self)
        self.live.roots = [self.rootSnapshot(url: self.rootURL)]
    }

    override func tearDown() async throws {
        self.models.forEach { $0.stop() }
        self.scripted.cancelAll()
    }

    // MARK: - Generations and selection

    func testLateOlderGenerationIsDropped() async {
        let model = self.makeModel(scripted: true)
        model.setQuery(LibraryQuery(search: "first"))
        await self.scripted.waitForRequest(1)
        model.setQuery(LibraryQuery(search: "second"))
        await self.scripted.waitForRequest(2)

        self.scripted.deliver(2, rows: [self.row(2, title: "Second")])
        await model.waitForRefresh()
        self.scripted.deliver(1, rows: [self.row(1, title: "First")])
        await Task.yield()
        XCTAssertEqual(model.rows.map(\.title), ["Second"])
        XCTAssertEqual(model.query.search, "second")
    }

    func testSelectionSurvivesRefreshAndDropsVanishedIDs() async {
        let model = self.makeModel()
        let a = self.row(1), b = self.row(2), c = self.row(3)
        self.live.current = [a, b, c]
        model.refresh()
        await model.waitForRefresh()
        model.selection = [a.id, c.id]
        model.focusedID = c.id

        self.live.current = [a, b]
        model.refresh()
        await model.waitForRefresh()
        XCTAssertEqual(model.selection, [a.id])
        XCTAssertNil(model.focusedID, "a vanished focused row is dropped")
    }

    func testFocusedIDSurvivesWhenPresent() async {
        let model = self.makeModel()
        let a = self.row(1)
        self.live.current = [a]
        model.refresh()
        await model.waitForRefresh()
        model.focusedID = a.id
        model.refresh()
        await model.waitForRefresh()
        XCTAssertEqual(model.focusedID, a.id)
    }

    func testVersionBumpRerunsCurrentQuery() async {
        let model = self.makeModel()
        model.setQuery(LibraryQuery(search: "song"))
        await model.waitForRefresh()
        XCTAssertTrue(model.rows.isEmpty)

        self.live.current = [self.row(1)]
        self.versions.yield(1)
        while model.rows.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(model.rows.count, 1)
        XCTAssertEqual(model.roots.map(\.id), [self.rootID])
    }

    func testStopCancelsTasks() async {
        let model = self.makeModel(scripted: true)
        model.refresh()
        await self.scripted.waitForRequest(1)
        model.stop()
        self.versions.yield(1)
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        XCTAssertEqual(self.scripted.requestCount, 1)
        self.scripted.deliver(1, rows: [self.row(1)])
        await Task.yield()
        XCTAssertTrue(model.rows.isEmpty)
    }

    /// A version published right after `stop()` is still buffered in the stream when the cancelled
    /// subscription reads it; it must not start a refresh (the CI flake of `testStopCancelsTasks`).
    func testVersionBufferedAtStopStartsNoRefresh() async {
        let model = self.makeModel(scripted: true)
        model.stop()
        self.versions.yield(1)
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        XCTAssertEqual(self.scripted.requestCount, 0)
    }

    // MARK: - Enqueue

    func testEnterReplacesAndPlaysFirstInDisplayedOrder() async {
        let model = try? await self.loadedModel([self.row(1, title: "B"), self.row(2, title: "A"), self.row(3, title: "C")])
        guard let model else { return XCTFail("model") }
        self.playlist.addTracks([Track(title: "Old", artist: "Old")])
        model.selection = Set(model.rows.map(\.id))
        await model.enqueue(append: false, clickedID: nil)
        XCTAssertEqual(self.playlist.tracks.map(\.title), ["A", "B", "C"])
        XCTAssertEqual(self.playlist.currentIndex, 0)
        XCTAssertEqual(self.audio.loadTrackCalls.last?.title, "A")
    }

    func testCommandEnterAppends() async throws {
        let model = try await self.loadedModel([self.row(1, title: "A")])
        self.playlist.addTracks([Track(title: "Old", artist: "Old")])
        model.selection = [model.rows[0].id]
        await model.enqueue(append: true, clickedID: nil)
        XCTAssertEqual(self.playlist.tracks.map(\.title), ["Old", "A"])
        XCTAssertTrue(self.audio.loadTrackCalls.isEmpty)
    }

    func testClickOutsideSelectionEnqueuesOnlyClicked() async throws {
        let model = try await self.loadedModel([self.row(1, title: "A"), self.row(2, title: "B")])
        model.selection = [model.rows[0].id]
        await model.enqueue(append: true, clickedID: model.rows[1].id)
        XCTAssertEqual(self.playlist.tracks.map(\.title), ["B"])
    }

    func testClickInsideSelectionEnqueuesSelection() async throws {
        let model = try await self.loadedModel([self.row(1, title: "A"), self.row(2, title: "B")])
        model.selection = Set(model.rows.map(\.id))
        await model.enqueue(append: true, clickedID: model.rows[1].id)
        XCTAssertEqual(self.playlist.tracks.map(\.title), ["A", "B"])
    }

    func testUnavailableOnlyBeepsAndKeepsPlaylist() async throws {
        let model = try await self.loadedModel([self.row(1, title: "Gone", available: false)])
        self.playlist.addTracks([Track(title: "Old", artist: "Old")])
        model.selection = [model.rows[0].id]
        await model.enqueue(append: false, clickedID: nil)
        XCTAssertEqual(self.beeps, 1)
        XCTAssertEqual(self.playlist.tracks.map(\.title), ["Old"])
    }

    func testStaleResultRecheckedAgainstLatestRows() async throws {
        let a = self.row(1, title: "A"), b = self.row(2, title: "B")
        let model = try await self.loadedModel([a, b])
        self.live.latest = [self.row(1, title: "A", available: false), b] // unmount published after the result
        model.selection = [a.id, b.id]
        await model.enqueue(append: true, clickedID: nil)
        XCTAssertEqual(self.playlist.tracks.map(\.title), ["B"])
    }

    func testRemovedRootCannotBeEnqueued() async throws {
        let model = try await self.loadedModel([self.row(1, title: "A")])
        self.live.latest = [] // root removed
        model.selection = [model.rows[0].id]
        await model.enqueue(append: true, clickedID: nil)
        XCTAssertTrue(self.playlist.tracks.isEmpty)
        XCTAssertEqual(self.beeps, 1)
    }

    func testEnqueueRegistersRootBookmark() async throws {
        let model = try await self.loadedModel([self.row(1, title: "A")])
        model.selection = [model.rows[0].id]
        await model.enqueue(append: true, clickedID: nil)
        let saved = self.bookmarkDefaults.array(forKey: "AmpXSecurityScopedBookmarks") as? [Data]
        XCTAssertEqual(saved?.count, 1)
    }

    func testSameRowTwiceYieldsDistinctTracks() async throws {
        let model = try await self.loadedModel([self.row(1, title: "A")])
        model.selection = [model.rows[0].id]
        await model.enqueue(append: true, clickedID: nil)
        await model.enqueue(append: true, clickedID: nil)
        XCTAssertEqual(self.playlist.tracks.count, 2)
        XCTAssertNotEqual(self.playlist.tracks[0].id, self.playlist.tracks[1].id)
        XCTAssertEqual(self.playlist.tracks[0].fileSize, 1000)
    }

    func testRelocatedRootUsesLatestURL() async throws {
        let a = self.row(1, title: "A")
        let model = try await self.loadedModel([a])
        let moved = self.rootURL.appendingPathComponent("Moved", isDirectory: true)
        self.live.latest = [self.row(1, title: "A", root: moved)]
        model.selection = [a.id]
        await model.enqueue(append: true, clickedID: nil)
        XCTAssertEqual(self.playlist.tracks.first?.url, moved.appendingPathComponent("1.mp3"))
    }

    // MARK: - Helpers

    private func makeModel(scripted: Bool = false) -> LibraryBrowserModel {
        let (stream, continuation) = AsyncStream.makeStream(of: UInt64.self)
        self.versions = continuation
        let live = self.live!
        let queries = self.scripted!
        let query: @Sendable (LibraryQuery, UInt64) async throws -> LibraryResult
        if scripted {
            query = { try await queries.query($0, $1) }
        } else {
            query = { request, generation in request.evaluate(rows: live.current, snapshotVersion: 0, generation: generation) }
        }
        let services = LibraryBrowserServices(
            query: query,
            rows: { ids in live.latest.filter { ids.contains($0.id) } },
            versions: { stream },
            progress: { AsyncStream<ScanProgress> { $0.finish() } },
            roots: { live.roots }
        )
        let model = LibraryBrowserModel(
            services: services, playlist: self.playlist, bookmarkStore: self.bookmarkStore,
            beep: { [weak self] in self?.beeps += 1 }
        )
        self.models.append(model)
        return model
    }

    private func loadedModel(_ rows: [LibraryRow]) async throws -> LibraryBrowserModel {
        let model = self.makeModel()
        self.live.current = rows
        model.setQuery(LibraryQuery(sort: .title))
        await model.waitForRefresh()
        return model
    }

    private func row(_ id: Int, title: String = "Song", available: Bool = true, root: URL? = nil) -> LibraryRow {
        LibraryRow(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))!,
            rootID: self.rootID, url: (root ?? self.rootURL).appendingPathComponent("\(id).mp3"),
            title: title, artist: "Artist", album: "", albumArtist: "",
            genre: nil, trackNumber: nil, duration: 120, fileSize: 1000,
            bpm: nil, musicalKey: nil, bitrate: 0, bitrateIsDerived: false, codec: "mp3",
            isAvailable: available,
            searchKey: LibraryRow.makeSearchKey(title: title, artist: "Artist", album: "", albumArtist: "")
        )
    }

    private func rootSnapshot(url: URL) -> LibraryRootSnapshot {
        LibraryRootSnapshot(
            id: self.rootID,
            url: url,
            displayPath: url.path,
            isAvailable: true,
            unreadableFolderCount: 0,
            lastCompletedScanAt: nil
        )
    }
}
