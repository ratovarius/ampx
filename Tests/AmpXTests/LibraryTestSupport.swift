@testable import AmpX
import Foundation
import SwiftData
import XCTest

/// Holds a caller until the test opens it; replaces sleeps when ordering concurrent work.
actor TestBarrier {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if self.isOpen {
            return
        }
        await withCheckedContinuation { self.waiters.append($0) }
    }

    func open() {
        self.isOpen = true
        self.waiters.forEach { $0.resume() }
        self.waiters.removeAll()
    }
}

/// Thread-safe ordered event log shared by spies.
final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ event: String) {
        self.lock.withLock { self.storage.append(event) }
    }

    var events: [String] {
        self.lock.withLock { self.storage }
    }
}

/// Records security-scope starts/stops; `allowStart` decides what `start` returns.
final class ScopeSpy: @unchecked Sendable {
    let log: EventLog
    private let lock = NSLock()
    private var allow = true
    private var counts: [String: Int] = [:]

    init(log: EventLog = EventLog()) {
        self.log = log
    }

    var allowStart: Bool {
        get { self.lock.withLock { self.allow } }
        set { self.lock.withLock { self.allow = newValue } }
    }

    /// Outstanding starts per path; balanced scopes leave every count at zero.
    var openCounts: [String: Int] {
        self.lock.withLock { self.counts.filter { $0.value != 0 } }
    }

    var scope: LibrarySecurityScope {
        LibrarySecurityScope(
            start: { url in
                let path = url.standardizedFileURL.resolvingSymlinksInPath().path
                let allowed = self.lock.withLock { () -> Bool in
                    if self.allow {
                        self.counts[path, default: 0] += 1
                    }
                    return self.allow
                }
                self.log.append("start:\(url.lastPathComponent)")
                return allowed
            },
            stop: { url in
                let path = url.standardizedFileURL.resolvingSymlinksInPath().path
                self.lock.withLock { self.counts[path, default: 0] -= 1 }
                self.log.append("stop:\(url.lastPathComponent)")
            }
        )
    }
}

/// Startup flag that logs every write next to the saves in the same `EventLog`.
final class FlagSpy: LibraryStartupFlag, @unchecked Sendable {
    let log: EventLog
    private let lock = NSLock()
    private var value: Bool

    init(log: EventLog, initial: Bool = false) {
        self.log = log
        self.value = initial
    }

    var hasRoots: Bool {
        self.lock.withLock { self.value }
    }

    func setHasRoots(_ value: Bool) {
        self.lock.withLock { self.value = value }
        self.log.append("flag:\(value)")
    }
}

/// Deterministic builders for library value types. Test-only.
enum LibraryTestSupport {
    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    static func stat(_ size: Int64, _ seconds: TimeInterval) -> LibraryStat {
        LibraryStat(fileSize: size, contentModifiedAt: Date(timeIntervalSince1970: seconds))
    }

    static func key(
        id: UUID,
        path: String,
        stat: LibraryStat,
        fingerprint: Data? = nil,
        history: LibraryHistory = LibraryHistory(playCount: 0, lastPlayedAt: nil, rating: 0),
        dateAdded: Date = fixedDate,
        missing: Bool = false
    ) -> LibraryRowKey {
        LibraryRowKey(
            id: id, relativePath: path, stat: stat, fingerprint: fingerprint,
            dateAdded: dateAdded, history: history, isMissing: missing
        )
    }

    static func entry(path: String, stat: LibraryStat) -> LibraryEntry {
        LibraryEntry(relativePath: path, stat: stat)
    }

    /// Rename tracking on uses the verified `apfs` type; off uses a type no allowlist contains.
    static func walk(
        entries: [LibraryEntry],
        coverage: LibraryCoverage = .complete,
        caseSensitive: Bool = true,
        renameTracking: Bool = true
    ) -> LibraryWalk {
        LibraryWalk(
            entries: entries,
            coverage: coverage,
            volume: LibraryVolume(caseSensitive: caseSensitive, typeName: renameTracking ? "apfs" : "test-disabled")
        )
    }

    // MARK: - Store harness

    static func isolatedDefaults(_ testCase: XCTestCase) -> UserDefaults {
        let suite = "LibraryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        testCase.addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return defaults
    }

    static func makeStore(
        _ testCase: XCTestCase,
        container: ModelContainer,
        saveContext: @escaping @Sendable (ModelContext) throws -> Void = { try $0.save() }
    ) -> LibraryStore {
        var dependencies = LibraryStoreDependencies(
            startupFlag: UserDefaultsLibraryStartupFlag(defaults: self.isolatedDefaults(testCase))
        )
        dependencies.saveContext = saveContext
        dependencies.now = { self.fixedDate }
        return LibraryStore(modelContainer: container, dependencies: dependencies)
    }

    /// Plain (non-security-scoped) bookmarks: deterministic in unit tests.
    static let plainBookmarks = LibraryBookmarking(
        make: { try SecurityScopedBookmark.makeData(for: $0, usesSecurityScope: false) },
        resolve: { SecurityScopedBookmark.resolve($0) },
        refresh: { url, _ in SecurityScopedBookmark.refreshedData(for: url, usesSecurityScope: false) }
    )

    /// A store wired to spies for root tests; saves are logged as `save` in `log`.
    static func makeRootStore(container: ModelContainer, scope: ScopeSpy, flag: FlagSpy) -> LibraryStore {
        let log = flag.log
        var dependencies = LibraryStoreDependencies(startupFlag: flag)
        dependencies.scope = scope.scope
        dependencies.bookmarks = self.plainBookmarks
        dependencies.now = { self.fixedDate }
        dependencies.saveContext = { context in
            try context.save()
            log.append("save")
        }
        return LibraryStore(modelContainer: container, dependencies: dependencies)
    }

    /// Seeds through a test-owned context, independent of the store's root APIs.
    static func seedRoot(_ container: ModelContainer, id: UUID, path: String = "/Music/DJ") throws {
        let context = ModelContext(container)
        context.insert(LibraryRoot(id: id, bookmark: Data(), displayPath: path, addedAt: self.fixedDate))
        try context.save()
    }

    static func seedTrack(
        _ container: ModelContainer,
        id: UUID,
        rootID: UUID,
        path: String,
        stat: LibraryStat = LibraryTestSupport.stat(100, 1),
        history: LibraryHistory = LibraryHistory(playCount: 0, lastPlayedAt: nil, rating: 0),
        dateAdded: Date = fixedDate
    ) throws {
        let context = ModelContext(container)
        let track = LibraryTrack(
            id: id, rootID: rootID, relativePath: path, title: "Seed", artist: "Seed",
            fileSize: stat.fileSize, contentModifiedAt: stat.contentModifiedAt, dateAdded: dateAdded
        )
        track.playCount = history.playCount
        track.lastPlayedAt = history.lastPlayedAt
        track.rating = history.rating
        context.insert(track)
        try context.save()
    }

    struct TrackState: Equatable {
        let id: UUID
        let relativePath: String
        let title: String
        let isMissing: Bool
        let history: LibraryHistory
        let dateAdded: Date
        let fileSize: Int64
        let fingerprint: Data?
    }

    /// Reads committed rows through a fresh context, sorted by path.
    static func tracks(_ container: ModelContainer) throws -> [TrackState] {
        try ModelContext(container).fetch(FetchDescriptor<LibraryTrack>()).map {
            TrackState(
                id: $0.id, relativePath: $0.relativePath, title: $0.title, isMissing: $0.isMissing,
                history: LibraryHistory(playCount: $0.playCount, lastPlayedAt: $0.lastPlayedAt, rating: $0.rating),
                dateAdded: $0.dateAdded, fileSize: $0.fileSize, fingerprint: $0.contentFingerprint
            )
        }
        .sorted { $0.relativePath < $1.relativePath }
    }

    static func parseWrite(
        id: UUID = UUID(),
        insert: Bool,
        path: String,
        stat: LibraryStat = LibraryTestSupport.stat(100, 1),
        title: String = "Parsed",
        fingerprint: Data? = Data([7])
    ) -> LibraryParseWrite {
        var metadata = TrackMetadataLoader.Metadata(title: title, artist: "Artist", duration: 60, fileSize: stat.fileSize)
        metadata.genre = "Techno"
        metadata.codec = "mp3"
        return LibraryParseWrite(id: id, isInsert: insert, relativePath: path, stat: stat, metadata: metadata, fingerprint: fingerprint)
    }

    /// A fresh directory removed when the test finishes.
    static func temporaryDirectory(_ testCase: XCTestCase) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Library-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        testCase.addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
