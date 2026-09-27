@testable import AmpX
import Foundation
import XCTest

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

    /// A fresh directory removed when the test finishes.
    static func temporaryDirectory(_ testCase: XCTestCase) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Library-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        testCase.addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
