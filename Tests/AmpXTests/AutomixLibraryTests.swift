@testable import AmpX
import SwiftData
import XCTest

/// DJ mode spec Revision 2 § Delivery 2: what Automix reads from the library.
final class AutomixLibraryTests: XCTestCase {
    private typealias T = LibraryTestSupport

    private var container: ModelContainer!
    private var index: LibraryIndex!
    private var library: LibraryEngineAutomixLibrary!
    private let rootID = UUID()

    override func setUp() async throws {
        self.container = try LibraryContainerFactory.make(url: nil)
        try T.seedRoot(self.container, id: self.rootID, path: "/Music/DJ")
        self.index = LibraryIndex(container: self.container, changes: AsyncStream { $0.finish() })
        self.library = LibraryEngineAutomixLibrary(index: self.index, store: T.makeStore(self, container: self.container))
    }

    override func tearDown() async throws {
        await self.index.stop()
    }

    @discardableResult
    private func seed(
        _ path: String,
        genre: String = "Techno",
        grid: Bool = true,
        phrases: Bool = true,
        missing: Bool = false
    ) throws -> UUID {
        let id = UUID()
        try T.seedTrack(self.container, id: id, rootID: self.rootID, path: path)
        let context = ModelContext(self.container)
        let track = try XCTUnwrap(try context.fetch(FetchDescriptor<LibraryTrack>()).first { $0.id == id })
        track.genre = genre
        track.duration = 300
        track.bpm = 128
        track.isMissing = missing
        if grid {
            track.beatGrid = RekordboxBeatGrid.pack([RekordboxBeat(start: 0.1, bpm: 128, meter: "4/4", beat: 1)])
            track.tempoSpread = 0
        }
        if phrases {
            let analysis = RekordboxPhraseAnalysis(mood: 1, endBeat: 600, phrases: [RekordboxPhrase(beat: 1, kind: .intro)])
            track.phrases = RekordboxAnalysisFile.pack(analysis)
        }
        try context.save()
        return id
    }

    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: "/Music/DJ/\(path)")
    }

    func testTrackForLibraryURLHasGridPhrasesAndClass() async throws {
        let id = try self.seed("a.mp3")
        let (row, track) = await self.library.track(url: self.url("a.mp3"), duration: 299.5)
        XCTAssertEqual(row?.id, id)
        XCTAssertEqual(track.trackClass, .steady)
        XCTAssertEqual(track.duration, 299.5)
        XCTAssertEqual(try XCTUnwrap(track.grid).localBPM(at: 10), 128)
        XCTAssertEqual(track.phrases?.endBeat, 600)
    }

    func testTrackForUnknownURLIsUnknown() async throws {
        try self.seed("a.mp3")
        let (row, track) = await self.library.track(url: URL(fileURLWithPath: "/Downloads/x.mp3"), duration: 200)
        XCTAssertNil(row)
        XCTAssertEqual(track, .unknown(duration: 200))
    }

    func testUnavailableRowIsUnknown() async throws {
        try self.seed("a.mp3", missing: true)
        let (_, track) = await self.library.track(url: self.url("a.mp3"), duration: 300)
        XCTAssertEqual(track, .unknown(duration: 300))
    }

    func testPoolCurrentViewAppliesFilter() async throws {
        let techno = try self.seed("a.mp3")
        try self.seed("b.mp3", genre: "House")
        var filter = LibraryQuery()
        filter.genres = [.text("Techno")]
        let pool = await self.library.pool(.currentView, filter: filter)
        XCTAssertEqual(pool.map(\.id), [techno])
    }

    func testPoolWholeLibraryIgnoresFilter() async throws {
        try self.seed("a.mp3")
        try self.seed("b.mp3", genre: "House")
        var filter = LibraryQuery()
        filter.genres = [.text("Techno")]
        let pool = await self.library.pool(.wholeLibrary, filter: filter)
        XCTAssertEqual(pool.count, 2)
    }

    func testPoolExcludesUnavailable() async throws {
        let present = try self.seed("a.mp3")
        try self.seed("b.mp3", missing: true)
        let pool = await self.library.pool(.wholeLibrary, filter: nil)
        XCTAssertEqual(pool.map(\.id), [present])
    }

    /// PR 17 review: the MISSING view keeps only unavailable rows, which the pool never holds.
    func testPoolCurrentViewIgnoresMissingView() async throws {
        let techno = try self.seed("a.mp3")
        try self.seed("b.mp3", genre: "House")
        try self.seed("c.mp3", missing: true)
        var filter = LibraryQuery()
        filter.genres = [.text("Techno")]
        filter.onlyUnavailable = true
        let pool = await self.library.pool(.currentView, filter: filter)
        XCTAssertEqual(pool.map(\.id), [techno])
    }

    /// PR 17 review: an AUTO pick's root is bookmarked, so the restored Playlist can still open it.
    func testRegisterRootSavesRootBookmark() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let rootID = UUID()
        try T.seedRoot(self.container, id: rootID, path: directory.path)
        let defaults = T.isolatedDefaults(self)
        let library = LibraryEngineAutomixLibrary(
            index: self.index,
            store: T.makeStore(self, container: self.container),
            bookmarkStore: SecurityScopedBookmarkStore(userDefaults: defaults)
        )
        let id = UUID()
        try T.seedTrack(self.container, id: id, rootID: rootID, path: "a.mp3")
        let found = try await self.index.row(url: directory.appendingPathComponent("a.mp3"))
        let row = try XCTUnwrap(found)
        await library.registerRoot(of: row)
        XCTAssertEqual((defaults.array(forKey: "AmpXSecurityScopedBookmarks") as? [Data])?.count, 1)
    }

    func testPoolWithoutPersistedFilterIsWholeLibrary() async throws {
        try self.seed("a.mp3")
        try self.seed("b.mp3", genre: "House")
        let pool = await self.library.pool(.currentView, filter: nil)
        XCTAssertEqual(pool.count, 2)
    }
}
