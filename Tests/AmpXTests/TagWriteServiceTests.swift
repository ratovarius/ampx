@testable import AmpX
import SwiftData
import XCTest

/// DJ mode spec Revision 2 § Tag writing (service). Files are real; a fake `TagFileAccess` keeps each file's "tags" as
/// JSON in its contents, so atomic replacement, read-back and leftovers are all observable on disk.
final class TagWriteServiceTests: XCTestCase {
    private typealias T = LibraryTestSupport

    private final class FakeFiles: @unchecked Sendable {
        private let lock = NSLock()
        private var writes = 0
        /// Write a different BPM than asked (the read-back check must catch it).
        var corruptWrites = false
        /// Called after each write to a temporary copy, with the copy's URL.
        var afterWrite: (@Sendable (URL) -> Void)?

        var writeCount: Int {
            self.lock.withLock { self.writes }
        }

        static func make(_ fields: [TagField: String], at url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Dictionary(uniqueKeysWithValues: fields.map { ($0.key.rawValue, $0.value) })).write(to: url)
        }

        static func fields(at url: URL) throws -> [TagField: String] {
            let raw = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
            return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in TagField(rawValue: key).map { ($0, value) } })
        }

        var access: TagFileAccess {
            TagFileAccess(
                read: { try Self.fields(at: $0) },
                write: { [self] fields, url in
                    var current = try Self.fields(at: url)
                    for (field, value) in fields {
                        current[field] = field == .bpm && self.corruptWrites ? "1" : value
                    }
                    try Self.make(current, at: url)
                    self.lock.withLock { self.writes += 1 }
                    self.afterWrite?(url)
                },
                duration: { _ in 300 },
                isWritable: { FileManager.default.isWritableFile(atPath: $0.path) }
            )
        }
    }

    private var h: ScanHarness!
    private var files: FakeFiles!
    private var defaults: UserDefaults!
    private var service: TagWriteService!

    override func setUp() async throws {
        self.h = try await ScanHarness.make(self)
        self.files = FakeFiles()
        self.defaults = T.isolatedDefaults(self)
        self.service = TagWriteService(store: self.h.store, scanner: self.h.scanner, files: self.files.access, settings: TagWriteSettings(defaults: self.defaults))
    }

    override func tearDown() async throws {
        self.service.halt()
        await self.service.waitUntilIdle()
        await self.h.scanner.stop()
        let enumerator = FileManager.default.enumerator(at: self.h.rootURL, includingPropertiesForKeys: nil)
        let leftovers = (enumerator?.allObjects as? [URL] ?? []).filter { $0.lastPathComponent.contains(".ampx-tagwrite") }
        XCTAssertEqual(leftovers, [], "no temporary copy is ever left behind")
    }

    /// A rekordbox row and its file with `fileTags`.
    @discardableResult
    private func seed(
        _ path: String,
        bpm: Double = 128,
        key: String = "Am",
        label: String? = nil,
        fileTags: [TagField: String] = [:]
    ) throws -> (UUID, URL) {
        let id = UUID()
        try T.seedTrack(self.h.container, id: id, rootID: self.h.rootID, path: path)
        let context = ModelContext(self.h.container)
        let track = try XCTUnwrap(try context.fetch(FetchDescriptor<LibraryTrack>()).first { $0.id == id })
        track.bpm = bpm
        track.musicalKey = key
        track.label = label
        track.analysisSource = .rekordbox
        try context.save()
        let url = self.h.rootURL.appendingPathComponent(path)
        try FakeFiles.make(fileTags, at: url)
        return (id, url)
    }

    private func hash(_ id: UUID) throws -> Data? {
        try XCTUnwrap(try ModelContext(self.h.container).fetch(FetchDescriptor<LibraryTrack>()).first { $0.id == id }).tagsWrittenHash
    }

    func testWritesAtomicallyAndStoresHash() async throws {
        let (id, url) = try self.seed("a.mp3", label: "Drumcode", fileTags: [.bpm: "120", .remixer: "Keep"])
        let report = await self.service.write(rowIDs: nil, onlyDue: false)
        XCTAssertEqual(report, TagWriteReport(written: 1))
        XCTAssertEqual(try FakeFiles.fields(at: url), [.bpm: "128", .key: "Am", .label: "Drumcode", .remixer: "Keep"])
        XCTAssertEqual(try self.hash(id), TagWritePlanner.hash([.bpm: "128", .key: "Am", .label: "Drumcode"]))
        XCTAssertEqual(self.service.lastReport(), report)
    }

    func testFailedReadBackLeavesOriginalByteIdentical() async throws {
        let (id, url) = try self.seed("a.mp3", fileTags: [.bpm: "120"])
        let before = try Data(contentsOf: url)
        self.files.corruptWrites = true
        let report = await self.service.write(rowIDs: nil, onlyDue: false)
        XCTAssertEqual(report.failed, [url.path])
        XCTAssertEqual(report.written, 0)
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertNil(try self.hash(id))
    }

    func testReadOnlyFileIsSkipped() async throws {
        let (_, url) = try self.seed("a.mp3", fileTags: [.bpm: "120"])
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        let report = await self.service.write(rowIDs: nil, onlyDue: false)
        XCTAssertEqual(report.skippedReadOnly, [url.path])
        XCTAssertEqual(self.files.writeCount, 0)
    }

    func testHalfDoubleListedEveryRunAndNeverHashed() async throws {
        let (id, url) = try self.seed("dnb.mp3", bpm: 174, key: "Fm", label: "Hospital", fileTags: [.bpm: "87"])
        for _ in 0 ..< 2 {
            let report = await self.service.write(rowIDs: nil, onlyDue: true)
            XCTAssertEqual(report.halfDouble, [url.path])
        }
        XCTAssertEqual(try FakeFiles.fields(at: url), [.bpm: "87", .key: "Fm", .label: "Hospital"])
        XCTAssertNil(try self.hash(id))
    }

    func testUnchangedFileStoresHashWithoutWriting() async throws {
        let (id, _) = try self.seed("a.mp3", fileTags: [.bpm: "128.00", .key: "Am"])
        let report = await self.service.write(rowIDs: nil, onlyDue: false)
        XCTAssertEqual(report, TagWriteReport())
        XCTAssertEqual(self.files.writeCount, 0)
        XCTAssertNotNil(try self.hash(id))
    }

    func testOnlyDueSkipsRowsWithMatchingHash() async throws {
        let (_, url) = try self.seed("a.mp3", fileTags: [.bpm: "120"])
        _ = await self.service.write(rowIDs: nil, onlyDue: false)
        try FakeFiles.make([.bpm: "90"], at: url) // edited elsewhere; AmpX's values did not change
        _ = await self.service.write(rowIDs: nil, onlyDue: true)
        XCTAssertEqual(try FakeFiles.fields(at: url), [.bpm: "90"])
        _ = await self.service.write(rowIDs: nil, onlyDue: false)
        XCTAssertEqual(try FakeFiles.fields(at: url)[.bpm], "128")
    }

    func testDecisionUsesFileAtWriteTimeNotPreview() async throws {
        let (_, url) = try self.seed("a.mp3", fileTags: [.bpm: "128"])
        let summary = await self.service.preview(rowIDs: nil)
        XCTAssertEqual(summary.filesToUpdate, 1)
        XCTAssertEqual(summary.perField, [.key: 1])
        try FakeFiles.make([.bpm: "128", .key: "Am"], at: url) // fixed elsewhere after the summary
        let report = await self.service.write(rowIDs: nil, onlyDue: false)
        XCTAssertEqual(report.written, 0)
        XCTAssertEqual(self.files.writeCount, 0)
    }

    func testPreviewCountsFieldsAndLists() async throws {
        try self.seed("a.mp3", label: "L", fileTags: [:])
        let (_, dnb) = try self.seed("dnb.mp3", bpm: 174, fileTags: [.bpm: "87", .key: "Am"])
        let (_, locked) = try self.seed("locked.mp3", fileTags: [.bpm: "1"])
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }
        try T.seedTrack(self.h.container, id: UUID(), rootID: self.h.rootID, path: "not-rekordbox.mp3")

        let summary = await self.service.preview(rowIDs: nil)

        XCTAssertEqual(summary.filesToUpdate, 1)
        XCTAssertEqual(summary.perField, [.bpm: 1, .key: 1, .label: 1])
        XCTAssertEqual(summary.halfDouble, [dnb.path])
        XCTAssertEqual(summary.skippedReadOnly, [locked.path])
        XCTAssertEqual(summary.unreadable, 0)
    }

    func testHaltMidRunLeavesNoTempAndOriginalIntact() async throws {
        let (_, url) = try self.seed("a.mp3", fileTags: [.bpm: "120"])
        let before = try Data(contentsOf: url)
        let service = self.service!
        self.files.afterWrite = { _ in service.halt() }
        let report = await service.write(rowIDs: nil, onlyDue: false)
        XCTAssertEqual(report.written, 0)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testUnavailableRootRowsAreNotCandidates() async throws {
        let (_, url) = try self.seed("a.mp3", fileTags: [.bpm: "120"])
        try await self.h.store.markUnavailable(id: self.h.rootID)
        let report = await self.service.write(rowIDs: nil, onlyDue: false)
        XCTAssertEqual(report, TagWriteReport())
        XCTAssertEqual(try FakeFiles.fields(at: url), [.bpm: "120"])
    }

    func testRowIDsLimitTheRun() async throws {
        let (a, aURL) = try self.seed("a.mp3", fileTags: [.bpm: "120"])
        let (_, bURL) = try self.seed("b.mp3", fileTags: [.bpm: "120"])
        _ = await self.service.write(rowIDs: [a], onlyDue: false)
        XCTAssertEqual(try FakeFiles.fields(at: aURL)[.bpm], "128")
        XCTAssertEqual(try FakeFiles.fields(at: bURL)[.bpm], "120")
    }

    func testAutomaticWriteOnlyWhenEnabled() async throws {
        let (_, url) = try self.seed("a.mp3", fileTags: [.bpm: "120"])
        self.service.requestAutomaticWrite()
        await self.service.waitUntilIdle()
        XCTAssertEqual(try FakeFiles.fields(at: url)[.bpm], "120")

        self.defaults.set(true, forKey: TagWriteSettings.enabledKey)
        self.service.requestAutomaticWrite()
        await self.service.waitUntilIdle()
        XCTAssertEqual(try FakeFiles.fields(at: url)[.bpm], "128")
    }

    func testLiveWriteRefusedWhenOtherFramesWouldBeLost() async throws {
        let fixtures = try XCTUnwrap(Bundle(for: Self.self).resourceURL).appendingPathComponent("Library")
        let (id, url) = try self.seed("rvad.mp3", key: "F#m")
        try FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("rvad-v23.mp3"), to: url)
        let before = try Data(contentsOf: url)
        let live = TagWriteService(store: self.h.store, scanner: self.h.scanner, files: .live, settings: TagWriteSettings(defaults: self.defaults))

        let report = await live.write(rowIDs: [id], onlyDue: false)

        XCTAssertEqual(report.failed, [url.path])
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertNil(try self.hash(id))
    }

    func testStaleTemporaryCopyIsRemoved() async throws {
        let (_, url) = try self.seed("a.mp3", fileTags: [.bpm: "120"])
        let stale = url.deletingLastPathComponent().appendingPathComponent(".old.ampx-tagwrite.mp3")
        try Data([1, 2, 3]).write(to: stale)
        _ = await self.service.write(rowIDs: nil, onlyDue: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
    }

    func testFailedWriteAfterCopyLeavesNoTemp() async throws {
        let (_, url) = try self.seed("a.mp3", fileTags: [.bpm: "120"])
        var access = self.files.access
        access.write = { _, _ in throw CocoaError(.fileWriteUnknown) }
        let failing = TagWriteService(store: self.h.store, scanner: self.h.scanner, files: access, settings: nil)
        let report = await failing.write(rowIDs: nil, onlyDue: false)
        XCTAssertEqual(report.failed, [url.path])
    }

    func testLiveWriteOnRealMP3() async throws {
        let fixtures = try XCTUnwrap(Bundle(for: Self.self).resourceURL).appendingPathComponent("Library")
        let (id, url) = try self.seed("live.mp3", key: "F#m")
        try FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("tagged-v24.mp3"), to: url)
        let live = TagWriteService(store: self.h.store, scanner: self.h.scanner, files: .live, settings: TagWriteSettings(defaults: self.defaults))

        let report = await live.write(rowIDs: [id], onlyDue: false)

        XCTAssertEqual(report.written, 1)
        XCTAssertEqual(try TagFileIO.read(url)[.key], "F#m")
        XCTAssertEqual(try TagFileIO.read(url)[.bpm], "128")
    }
}
