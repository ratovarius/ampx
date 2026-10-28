@testable import AmpX
import XCTest

/// Success criterion 7 as a property: for every small inventory, interrupting a scan after its structure save
/// with any subset of parse writes committed, then retrying on the same file-system state and read results,
/// ends exactly where an uninterrupted scan ends. Drives the real `LibraryReconciler` over an in-memory model
/// of the store's structure and parse saves.
final class LibraryRetryPropertyTests: XCTestCase {
    private struct Row: Equatable {
        var path: String
        var stat: LibraryStat
        var fingerprint: Data?
        var isMissing: Bool
        let dateAdded: Date
    }

    private struct File {
        let stat: LibraryStat
        let fingerprint: Data
    }

    private struct State {
        var rows: [UUID: Row]
        let files: [String: File]
        /// Deterministic ids for inserts, keyed by path, so runs can be compared.
        var nextInsert = 0
    }

    private static let paths = ["p0", "p1", "p2"]
    private static let stats = [LibraryTestSupport.stat(1, 1), LibraryTestSupport.stat(2, 2)]
    private static let prints = [Data([1]), Data([2])]
    private static let originalIDs = (0 ..< 3).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0 + 1))! }

    func testInterruptedRetryMatchesUninterruptedForAllSmallInventories() {
        // Per path: a row is absent, or one of two stats × {F1, nil}; a file is absent, or one of two stats × {F1, F2}.
        let rowOptions: [(LibraryStat, Data?)?] = [nil] + Self.stats.flatMap { stat in [(stat, Self.prints[0]), (stat, nil)] }
        let fileOptions: [File?] = [nil] + Self.stats.flatMap { stat in Self.prints.map { File(stat: stat, fingerprint: $0) } }
        var cases = 0
        var mismatches: [String] = []

        for rowChoice in Self.product(rowOptions.count, 3) {
            for fileChoice in Self.product(fileOptions.count, 3) {
                var rows: [UUID: Row] = [:]
                var files: [String: File] = [:]
                for (index, path) in Self.paths.enumerated() {
                    if let (stat, fingerprint) = rowOptions[rowChoice[index]] {
                        rows[Self.originalIDs[index]] = Row(
                            path: path, stat: stat, fingerprint: fingerprint, isMissing: false,
                            dateAdded: Date(timeIntervalSince1970: Double(index))
                        )
                    }
                    if let file = fileOptions[fileChoice[index]] {
                        files[path] = file
                    }
                }
                let initial = State(rows: rows, files: files)
                let reference = Self.normalized(Self.scan(initial, commit: nil))
                let parseCount = Self.parseItems(initial).count
                for mask in 0 ..< (1 << parseCount) {
                    cases += 1
                    let interrupted = Self.scan(initial, commit: mask)
                    let retried = Self.normalized(Self.scan(interrupted, commit: nil))
                    if retried != reference, mismatches.count < 5 {
                        mismatches.append("rows \(rowChoice) files \(fileChoice) mask \(mask)")
                    }
                }
            }
        }
        XCTAssertTrue(mismatches.isEmpty, "\(mismatches)")
        XCTAssertGreaterThan(cases, 10000)
        self.emitGate("retry-cases", ["cases": cases, "mismatches": mismatches.count])
    }

    // MARK: - Model

    /// One scan: reconcile, commit structure, then parse. `commit` = nil parses everything; otherwise only the
    /// parse items whose bit is set are committed (an interruption after the structure save).
    private static func scan(_ state: State, commit mask: Int?) -> State {
        var state = state
        let keys = state.rows.map { id, row in
            LibraryRowKey(
                id: id, relativePath: row.path, stat: row.stat, fingerprint: row.fingerprint,
                dateAdded: row.dateAdded, history: LibraryHistory(playCount: 0, lastPlayedAt: nil, rating: 0),
                isMissing: row.isMissing
            )
        }
        let walk = LibraryWalk(
            entries: state.files.map { LibraryEntry(relativePath: $0.key, stat: $0.value.stat) }
                .sorted { $0.relativePath < $1.relativePath },
            coverage: .complete,
            volume: LibraryVolume(caseSensitive: true, typeName: "apfs")
        )
        var fingerprints: [String: Data] = [:]
        for path in LibraryReconciler.candidatePaths(rows: keys, walk: walk) {
            fingerprints[path] = state.files[path]?.fingerprint
        }
        let plan = LibraryReconciler.reconcile(rows: keys, walk: walk, fingerprints: fingerprints)

        for move in plan.moves {
            state.rows[move.id]?.path = move.relativePath
        }
        for id in plan.foundIDs {
            state.rows[id]?.isMissing = false
        }
        for id in plan.missingIDs {
            state.rows[id]?.isMissing = true
        }

        for (index, item) in self.parseItems(state, plan: plan).enumerated() {
            if let mask, mask & (1 << index) == 0 {
                continue
            }
            guard let file = state.files[item.path] else { continue }
            if let id = item.id {
                state.rows[id]?.stat = file.stat
                state.rows[id]?.fingerprint = file.fingerprint
            } else {
                state.nextInsert += 1
                state.rows[UUID()] = Row(
                    path: item.path, stat: file.stat, fingerprint: file.fingerprint, isMissing: false,
                    dateAdded: Date(timeIntervalSince1970: Double(100 + state.nextInsert))
                )
            }
        }
        return state
    }

    private struct Item {
        let id: UUID?
        let path: String
    }

    private static func parseItems(_ state: State) -> [Item] {
        let keys = state.rows.map { id, row in
            LibraryRowKey(
                id: id, relativePath: row.path, stat: row.stat, fingerprint: row.fingerprint, dateAdded: row.dateAdded,
                history: LibraryHistory(playCount: 0, lastPlayedAt: nil, rating: 0), isMissing: row.isMissing
            )
        }
        let walk = LibraryWalk(
            entries: state.files.map { LibraryEntry(relativePath: $0.key, stat: $0.value.stat) },
            coverage: .complete, volume: LibraryVolume(caseSensitive: true, typeName: "apfs")
        )
        var fingerprints: [String: Data] = [:]
        for path in LibraryReconciler.candidatePaths(rows: keys, walk: walk) {
            fingerprints[path] = state.files[path]?.fingerprint
        }
        return self.parseItems(state, plan: LibraryReconciler.reconcile(rows: keys, walk: walk, fingerprints: fingerprints))
    }

    /// Stale matched rows and new entries, in path order (as the scanner orders them).
    private static func parseItems(_ state: State, plan: LibraryReconciliation) -> [Item] {
        let stale = plan.staleIDs.compactMap { id in state.rows[id].map { Item(id: id, path: $0.path) } }
        let inserts = plan.newEntries.map { Item(id: nil, path: $0.relativePath) }
        return (stale + inserts).sorted { $0.path < $1.path }
    }

    private struct Normalized: Equatable, Hashable {
        let id: String
        let path: String
        let stat: LibraryStat
        let fingerprint: Data?
        let isMissing: Bool
    }

    /// Original ids are kept; freshly minted ids compare by path only.
    private static func normalized(_ state: State) -> Set<Normalized> {
        Set(state.rows.map { id, row in
            Normalized(
                id: self.originalIDs.contains(id) ? id.uuidString : "new",
                path: row.path, stat: row.stat, fingerprint: row.fingerprint, isMissing: row.isMissing
            )
        })
    }

    private static func product(_ base: Int, _ count: Int) -> [[Int]] {
        (0 ..< Int(pow(Double(base), Double(count)))).map { value in
            var value = value
            return (0 ..< count).map { _ in
                defer { value /= base }
                return value % base
            }
        }
    }
}
