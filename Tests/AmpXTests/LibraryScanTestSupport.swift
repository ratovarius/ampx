@testable import AmpX
import Foundation
import SwiftData
import XCTest

/// Scripted file system: walks, stats and fingerprints by relative path under one root.
actor FakeLibraryFileSystem: LibraryFileSystem {
    struct File {
        var stat: LibraryStat
        var fingerprint: Data?
        /// Stat reported after the read, when the file changes during parsing.
        var statAfterRead: LibraryStat?
    }

    let root: URL
    private(set) var files: [String: File] = [:]
    var coverage: LibraryCoverage = .complete
    var volume = LibraryVolume(caseSensitive: true, typeName: "apfs")
    var reachable = true
    var walkBarrier: TestBarrier?
    private(set) var walkCount = 0
    private(set) var statCount = 0
    private(set) var fingerprintCount = 0

    init(root: URL) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    func set(_ path: String, stat: LibraryStat, fingerprint: Data? = nil, statAfterRead: LibraryStat? = nil) {
        self.files[path] = File(stat: stat, fingerprint: fingerprint, statAfterRead: statAfterRead)
    }

    func remove(_ path: String) {
        self.files[path] = nil
    }

    func configure(coverage: LibraryCoverage? = nil, caseSensitive: Bool? = nil, reachable: Bool? = nil, walkBarrier: TestBarrier? = nil) {
        if let coverage {
            self.coverage = coverage
        }
        if let caseSensitive {
            self.volume = LibraryVolume(caseSensitive: caseSensitive, typeName: "apfs")
        }
        if let reachable {
            self.reachable = reachable
        }
        if let walkBarrier {
            self.walkBarrier = walkBarrier
        }
    }

    func volume(at _: URL) async throws -> LibraryVolume {
        self.volume
    }

    func walk(root _: URL, volume: LibraryVolume) async throws -> LibraryWalk {
        self.walkCount += 1
        // Snapshot first: changes made while the walk is blocked land in folders it has "already walked".
        let entries = self.files.map { LibraryEntry(relativePath: $0.key, stat: $0.value.stat) }
            .sorted { $0.relativePath < $1.relativePath }
        let coverage = self.coverage
        if let barrier = self.walkBarrier {
            self.walkBarrier = nil
            await barrier.wait()
        }
        guard self.reachable else { throw CocoaError(.fileNoSuchFile) }
        return LibraryWalk(entries: coverage == .aborted ? [] : entries, coverage: coverage, volume: volume)
    }

    func stat(at url: URL) async throws -> LibraryStat {
        self.statCount += 1
        guard let file = self.files[self.relative(url)] else { throw CocoaError(.fileNoSuchFile) }
        return file.statAfterRead ?? file.stat
    }

    func fingerprint(at url: URL) async throws -> Data {
        self.fingerprintCount += 1
        guard let fingerprint = self.files[self.relative(url)]?.fingerprint else { throw CocoaError(.fileReadCorruptFile) }
        return fingerprint
    }

    func isReachable(_: URL) async -> Bool {
        self.reachable
    }

    // MARK: - Top-level files (rekordbox discovery)

    private var topLevel: [String: (data: Data, stamp: RekordboxFileStamp)] = [:]
    private var unreadable: Set<String> = []
    var readBarrier: (started: TestBarrier, release: TestBarrier)?
    var prefixBarrier: (started: TestBarrier, release: TestBarrier)?
    private(set) var fullReads = 0

    /// `path` is absolute; only files directly inside a queried root are listed.
    func setTopLevel(_ path: String, data: Data, modified: TimeInterval) {
        self.topLevel[path] = (data, RekordboxFileStamp(size: Int64(data.count), modifiedAt: Date(timeIntervalSince1970: modified)))
    }

    func removeTopLevel(_ path: String) {
        self.topLevel[path] = nil
    }

    func setUnreadable(_ path: String) {
        self.unreadable.insert(path)
    }

    /// Blocks discovery (the 4 KB sniff), which runs before a check takes its token.
    func blockNextPrefixRead() -> (started: TestBarrier, release: TestBarrier) {
        let pair = (TestBarrier(), TestBarrier())
        self.prefixBarrier = pair
        return pair
    }

    func blockNextRead() -> (started: TestBarrier, release: TestBarrier) {
        let pair = (TestBarrier(), TestBarrier())
        self.readBarrier = pair
        return pair
    }

    func topLevelFiles(in root: URL, pathExtension: String) async throws -> [LibraryTopLevelFile] {
        let prefix = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        return self.topLevel.compactMap { path, file in
            guard path.hasPrefix(prefix), !path.dropFirst(prefix.count).contains("/"),
                  (path as NSString).pathExtension.caseInsensitiveCompare(pathExtension) == .orderedSame
            else { return nil }
            return LibraryTopLevelFile(url: URL(fileURLWithPath: path), name: (path as NSString).lastPathComponent, stamp: file.stamp)
        }
        .sorted { $0.name < $1.name }
    }

    func readPrefix(of url: URL, length: Int) async throws -> Data {
        if let barrier = self.prefixBarrier {
            self.prefixBarrier = nil
            await barrier.started.open()
            await barrier.release.wait()
        }
        guard !self.unreadable.contains(url.path), let file = self.topLevel[url.path] else { throw CocoaError(.fileReadNoPermission) }
        return file.data.prefix(length)
    }

    func readAll(of url: URL) async throws -> Data {
        self.fullReads += 1
        if let barrier = self.readBarrier {
            self.readBarrier = nil
            await barrier.started.open()
            await barrier.release.wait()
        }
        guard !self.unreadable.contains(url.path), let file = self.topLevel[url.path] else { throw CocoaError(.fileReadNoPermission) }
        return file.data
    }

    private func relative(_ url: URL) -> String {
        let prefix = self.root.path + "/"
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }
}

/// Metadata loader double: title = file stem; counts calls; can fail paths or interrupt the scan task.
final class FakeMetadataLoader: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var failing: Set<String> = []
    private var interruptAt: Int?
    private var onCall: (@Sendable (Int) async -> Void)?

    var callCount: Int {
        self.lock.withLock { self.calls }
    }

    func fail(_ fileName: String) {
        self.lock.withLock { _ = self.failing.insert(fileName) }
    }

    /// Cancels the calling (scan) task on the given 1-based call, like an app quit mid-parse.
    func interrupt(atCall call: Int?) {
        self.lock.withLock { self.interruptAt = call }
    }

    func onCall(_ handler: @escaping @Sendable (Int) async -> Void) {
        self.lock.withLock { self.onCall = handler }
    }

    var load: LibraryMetadataLoading {
        { url in
            let (call, fails, interrupt, handler) = self.lock.withLock { () -> (Int, Bool, Bool, (@Sendable (Int) async -> Void)?) in
                self.calls += 1
                return (self.calls, self.failing.contains(url.lastPathComponent), self.interruptAt == self.calls, self.onCall)
            }
            if interrupt {
                withUnsafeCurrentTask { $0?.cancel() }
            }
            await handler?(call)
            var metadata = TrackMetadataLoader.Metadata(
                title: url.deletingPathExtension().lastPathComponent, artist: "Artist",
                duration: fails ? 0 : 60, fileSize: 0
            )
            metadata.readFailed = fails
            metadata.codec = TrackMetadataLoader.codec(for: url)
            return metadata
        }
    }
}

/// One root on disk (for bookmarks and step 0) whose contents are scripted by a fake file system.
struct ScanHarness {
    let container: ModelContainer
    let store: LibraryStore
    let fileSystem: FakeLibraryFileSystem
    let loader: FakeMetadataLoader
    let scanner: LibraryScanner
    let rootID: UUID
    let rootURL: URL
    let scope: ScopeSpy

    /// `storeURL` nil = in memory. Reopening the same `storeURL` with `rootID` reuses the existing root.
    static func make(
        _ testCase: XCTestCase,
        storeURL: URL? = nil,
        rootURL: URL? = nil,
        rootID: UUID? = nil,
        fileSystem: FakeLibraryFileSystem? = nil,
        batchSize: Int = 200
    ) async throws -> ScanHarness {
        let container = try LibraryContainerFactory.make(url: storeURL)
        let log = EventLog()
        let scope = ScopeSpy(log: log)
        let store = LibraryTestSupport.makeRootStore(container: container, scope: scope, flag: FlagSpy(log: log))
        let rootURL = try rootURL ?? LibraryTestSupport.temporaryDirectory(testCase)
        let id: UUID = if let rootID {
            rootID
        } else {
            try await store.addRoot(url: rootURL)
        }
        let fileSystem = fileSystem ?? FakeLibraryFileSystem(root: rootURL)
        let loader = FakeMetadataLoader()
        let scanner = LibraryScanner(store: store, fileSystem: fileSystem, loadMetadata: loader.load, batchSize: batchSize)
        return ScanHarness(
            container: container, store: store, fileSystem: fileSystem, loader: loader,
            scanner: scanner, rootID: id, rootURL: rootURL, scope: scope
        )
    }

    func tracks() throws -> [LibraryTestSupport.TrackState] {
        try LibraryTestSupport.tracks(self.container)
    }

    func root() async throws -> LibraryRootSnapshot {
        try await self.store.roots().first { $0.id == self.rootID }!
    }
}

/// A minimal rekordbox export for sync tests.
enum RekordboxXML {
    struct Entry {
        var path: String
        var bpm: Double = 124
        var key = "Am"
        var label: String?
    }

    static func make(_ entries: [Entry], product: String = "rekordbox") -> Data {
        let tracks = entries.enumerated().map { index, entry in
            let location = "file://localhost" + (entry.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? entry.path)
            let label = entry.label.map { #" Label="\#($0)""# } ?? ""
            return #"<TRACK TrackID="\#(index + 1)" Name="T" AverageBpm="\#(entry.bpm)" Tonality="\#(entry.key)"\#(label) Location="\#(location)"/>"#
        }
        return Data(#"""
        <?xml version="1.0" encoding="UTF-8"?>
        <DJ_PLAYLISTS Version="1.0.0">
          <PRODUCT Name="\#(product)" Version="7.2.19" Company="AlphaTheta"/>
          <COLLECTION Entries="\#(entries.count)">
            \#(tracks.joined(separator: "\n    "))
          </COLLECTION>
        </DJ_PLAYLISTS>
        """#.utf8)
    }
}
