@testable import AmpX
import SwiftData
import XCTest

/// DJ mode spec Revision 2 § rekordbox phrases (import job).
final class RekordboxPhraseSyncTests: XCTestCase {
    private typealias T = LibraryTestSupport

    /// rekordbox's USBANLZ tree in memory: one folder per track with a DAT and an EXT.
    private final class FakeAnalysis: RekordboxAnalysisSource, @unchecked Sendable {
        private let lock = NSLock()
        private var files: [String: (data: Data, stamp: RekordboxFileStamp)] = [:]
        private var folderOrder: [URL] = []
        private var extReads = 0
        private var closes = 0

        func add(
            folder name: String,
            trackPath: String,
            ext: Data,
            modified: TimeInterval = 100,
            firstBeat: (Double, Double, Int)? = (0.2, 128, 1)
        ) {
            self.lock.withLock {
                let folder = URL(fileURLWithPath: "/USBANLZ/\(name)", isDirectory: true)
                if !self.folderOrder.contains(folder) {
                    self.folderOrder.append(folder)
                }
                let stamp = RekordboxFileStamp(size: Int64(ext.count), modifiedAt: Date(timeIntervalSince1970: modified))
                let dat = ANLZTestData.dat(path: trackPath, firstBeat: firstBeat)
                self.files[folder.appendingPathComponent("ANLZ0000.DAT").path] = (dat, stamp)
                self.files[folder.appendingPathComponent("ANLZ0000.EXT").path] = (ext, stamp)
            }
        }

        var extReadCount: Int {
            self.lock.withLock { self.extReads }
        }

        var closeCount: Int {
            self.lock.withLock { self.closes }
        }

        func trackFolders() async throws -> [URL] {
            self.lock.withLock { self.folderOrder }
        }

        func read(_ url: URL) async throws -> Data {
            try self.lock.withLock {
                if url.pathExtension == "EXT" {
                    self.extReads += 1
                }
                guard let file = self.files[url.path] else { throw CocoaError(.fileNoSuchFile) }
                return file.data
            }
        }

        func stamp(_ url: URL) async throws -> RekordboxFileStamp {
            try self.lock.withLock {
                guard let file = self.files[url.path] else { throw CocoaError(.fileNoSuchFile) }
                return file.stamp
            }
        }

        func close() {
            self.lock.withLock { self.closes += 1 }
        }
    }

    private final class Access: @unchecked Sendable {
        var source: FakeAnalysis?
    }

    private var h: ScanHarness!
    private var analysis: FakeAnalysis!
    private var access: Access!
    private var sync: RekordboxPhraseSync!

    private var root: String {
        self.h.fileSystem.root.path
    }

    override func setUp() async throws {
        self.h = try await ScanHarness.make(self)
        self.analysis = FakeAnalysis()
        self.access = Access()
        self.access.source = self.analysis
        let access = self.access!
        self.sync = RekordboxPhraseSync(
            store: self.h.store, scanner: self.h.scanner, fileSystem: self.h.fileSystem, source: { access.source }
        )
    }

    override func tearDown() async throws {
        await self.sync.halt()
        await self.h.scanner.stop()
    }

    /// A row whose rekordbox grid starts at `firstBeat` (seconds, bpm, beat); nil leaves it without a grid.
    private func seed(_ path: String, firstBeat: (Double, Double, Int)? = (0.2, 128, 1)) throws -> UUID {
        let id = UUID()
        try T.seedTrack(self.h.container, id: id, rootID: self.h.rootID, path: path)
        if let (start, bpm, beat) = firstBeat {
            let context = ModelContext(self.h.container)
            let track = try XCTUnwrap(try context.fetch(FetchDescriptor<LibraryTrack>()).first { $0.id == id })
            track.beatGrid = RekordboxBeatGrid.pack([RekordboxBeat(start: start, bpm: bpm, meter: "4/4", beat: beat)])
            try context.save()
        }
        return id
    }

    private func track(_ id: UUID) throws -> LibraryTrack {
        try XCTUnwrap(try ModelContext(self.h.container).fetch(FetchDescriptor<LibraryTrack>()).first { $0.id == id })
    }

    private func run() async {
        await self.sync.requestRun()
        await self.sync.waitUntilIdle()
    }

    private func ext(_ endBeat: Int) -> Data {
        ANLZTestData.ext(mood: 1, endBeat: endBeat, entries: [(1, 1), (785, 6)], masked: true)
    }

    func testImportsPhrasesForMatchedRows() async throws {
        let a = try self.seed("a.mp3"), b = try self.seed("Techno/b.mp3")
        self.analysis.add(folder: "P01/0001", trackPath: "?/a.mp3", ext: self.ext(836))
        self.analysis.add(folder: "P01/0002", trackPath: "?/b.mp3", ext: self.ext(500))
        self.analysis.add(folder: "P01/0003", trackPath: "?/c.mp3", ext: self.ext(10))

        await self.run()

        let phrasesA = try XCTUnwrap(try self.track(a).phrases.flatMap(RekordboxAnalysisFile.unpack))
        XCTAssertEqual(phrasesA.endBeat, 836)
        XCTAssertEqual(phrasesA.phrases.map(\.kind), [.intro, .outro])
        XCTAssertEqual(try self.track(b).phrases.flatMap(RekordboxAnalysisFile.unpack)?.endBeat, 500)
        XCTAssertNotNil(try self.track(a).phrasesStamp)
        XCTAssertEqual(self.analysis.closeCount, 1)
    }

    func testSkipsUnchangedStamp() async throws {
        _ = try self.seed("a.mp3")
        self.analysis.add(folder: "P01/0001", trackPath: "?/a.mp3", ext: self.ext(836))
        await self.run()
        XCTAssertEqual(self.analysis.extReadCount, 1)

        await self.run()
        XCTAssertEqual(self.analysis.extReadCount, 1, "unchanged EXT is not read again")

        self.analysis.add(folder: "P01/0001", trackPath: "?/a.mp3", ext: self.ext(900), modified: 200)
        await self.run()
        XCTAssertEqual(self.analysis.extReadCount, 2)
    }

    func testDecodeFailureStoresNilWithStamp() async throws {
        let a = try self.seed("a.mp3")
        self.analysis.add(folder: "P01/0001", trackPath: "?/a.mp3", ext: Data("PMAI".utf8) + Data(count: 40))
        await self.run()
        XCTAssertNil(try self.track(a).phrases)
        XCTAssertNotNil(try self.track(a).phrasesStamp)
    }

    func testNoAccessDoesNothing() async throws {
        let a = try self.seed("a.mp3")
        self.analysis.add(folder: "P01/0001", trackPath: "?/a.mp3", ext: self.ext(836))
        self.access.source = nil
        await self.run()
        XCTAssertNil(try self.track(a).phrases)
        XCTAssertEqual(self.analysis.extReadCount, 0)
    }

    func testMatchesNFDAndHashPaths() async throws {
        let a = try self.seed("R\u{E9}mix #1.mp3")
        self.analysis.add(folder: "P01/0001", trackPath: "?/Re\u{301}mix #1.mp3", ext: self.ext(836))
        await self.run()
        XCTAssertNotNil(try self.track(a).phrases)
    }

    func testSameNameInTwoFoldersResolvedByFirstBeat() async throws {
        let techno = try self.seed("Techno/track.mp3", firstBeat: (0.2, 128, 1))
        let house = try self.seed("House/track.mp3", firstBeat: (1.5, 122, 1))
        self.analysis.add(folder: "P01/0001", trackPath: "?/track.mp3", ext: self.ext(836), firstBeat: (1.5, 122, 1))
        self.analysis.add(folder: "P01/0002", trackPath: "?/track.mp3", ext: self.ext(500), firstBeat: (0.2, 128, 1))
        await self.run()
        XCTAssertEqual(try self.track(techno).phrases.flatMap(RekordboxAnalysisFile.unpack)?.endBeat, 500)
        XCTAssertEqual(try self.track(house).phrases.flatMap(RekordboxAnalysisFile.unpack)?.endBeat, 836)
    }

    func testIdenticalCopiesAreSkipped() async throws {
        let first = try self.seed("Techno/track.mp3")
        let second = try self.seed("Copies/track.mp3")
        self.analysis.add(folder: "P01/0001", trackPath: "?/track.mp3", ext: self.ext(836))
        self.analysis.add(folder: "P01/0002", trackPath: "?/track.mp3", ext: self.ext(836))
        await self.run()
        XCTAssertNil(try self.track(first).phrases, "ambiguous: never guessed")
        XCTAssertNil(try self.track(second).phrases)
    }

    func testFirstBeatMustAgree() async throws {
        let a = try self.seed("a.mp3", firstBeat: (0.2, 128, 1))
        self.analysis.add(folder: "P01/0001", trackPath: "?/a.mp3", ext: self.ext(836), firstBeat: (0.9, 128, 1))
        await self.run()
        XCTAssertNil(try self.track(a).phrases, "same name, different grid: another file")
    }

    func testRowWithoutGridMatchesUniqueName() async throws {
        let a = try self.seed("a.mp3", firstBeat: nil)
        self.analysis.add(folder: "P01/0001", trackPath: "?/a.mp3", ext: self.ext(836))
        await self.run()
        XCTAssertNotNil(try self.track(a).phrases)
    }

    func testRequestsCoalesce() async throws {
        _ = try self.seed("a.mp3")
        self.analysis.add(folder: "P01/0001", trackPath: "?/a.mp3", ext: self.ext(836))
        for _ in 0 ..< 3 {
            await self.sync.requestRun()
        }
        await self.sync.waitUntilIdle()
        XCTAssertLessThanOrEqual(self.analysis.closeCount, 2, "one run plus at most one follow-up")
        XCTAssertGreaterThanOrEqual(self.analysis.closeCount, 1)
    }

    func testRunsAfterRekordboxImport() async throws {
        _ = try self.seed("a.mp3")
        self.analysis.add(folder: "P01/0001", trackPath: "?/a.mp3", ext: self.ext(836))
        let rekordbox = RekordboxSync(store: self.h.store, scanner: self.h.scanner, fileSystem: self.h.fileSystem)
        let sync = self.sync!
        await rekordbox.setOnImported { await sync.requestRun() }
        await rekordbox.start()
        await self.h.fileSystem.setTopLevel(
            self.root + "/collection.xml", data: RekordboxXML.make([.init(path: self.root + "/a.mp3")]), modified: 100
        )

        await rekordbox.requestCheck(rootID: self.h.rootID)
        await rekordbox.waitUntilIdle()
        for _ in 0 ..< 200 where self.analysis.closeCount == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        await self.sync.waitUntilIdle()
        XCTAssertEqual(self.analysis.closeCount, 1)
        await rekordbox.stop()
    }
}
