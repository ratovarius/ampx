import Foundation

struct LibraryMove: Equatable, Sendable {
    let id: UUID
    let relativePath: String
}

struct LibraryIntegrityMerge: Equatable, Sendable {
    let survivorID: UUID
    let deletedIDs: Set<UUID>
    let history: LibraryHistory
}

/// The structure save of one scan (spec step 5) plus what step 6 must parse.
struct LibraryReconciliation: Equatable, Sendable {
    let moves: [LibraryMove]
    let spellingUpdates: [LibraryMove]
    /// Matched and moved rows: `isMissing = false`.
    let foundIDs: Set<UUID>
    /// Unmatched rows whose location the walk covered: `isMissing = true`.
    let missingIDs: Set<UUID>
    let newEntries: [LibraryEntry]
    /// Matched rows whose walked stat differs from the stored one.
    let staleIDs: Set<UUID>

    static let empty = LibraryReconciliation(
        moves: [], spellingUpdates: [], foundIDs: [], missingIDs: [], newEntries: [], staleIDs: []
    )
}

/// Pure decisions from stored row keys and a walk (spec: "Scanning", steps 1, 3 and 4). No I/O.
enum LibraryReconciler {
    /// NFC, plus case folding on case-insensitive volumes.
    static func pathKey(_ path: String, caseSensitive: Bool) -> String {
        let normalized = path.precomposedStringWithCanonicalMapping
        return caseSensitive ? normalized : normalized.lowercased()
    }

    /// Step 1: rows sharing a path key merge into the oldest (`dateAdded`, then smallest id).
    static func integrityMerges(rows: [LibraryRowKey], caseSensitive: Bool) -> [LibraryIntegrityMerge] {
        let groups = Dictionary(grouping: rows) { self.pathKey($0.relativePath, caseSensitive: caseSensitive) }
        return groups.values.filter { $0.count > 1 }.map { group in
            let ordered = group.sorted(by: self.isOlder)
            let survivor = ordered[0]
            let rating = survivor.history.rating != 0
                ? survivor.history.rating
                : ordered.dropFirst().first { $0.history.rating != 0 }?.history.rating ?? 0
            return LibraryIntegrityMerge(
                survivorID: survivor.id,
                deletedIDs: Set(ordered.dropFirst().map(\.id)),
                history: LibraryHistory(
                    playCount: group.map(\.history.playCount).max() ?? 0,
                    lastPlayedAt: group.compactMap(\.history.lastPlayedAt).max(),
                    rating: rating
                )
            )
        }
        .sorted { $0.survivorID.uuidString < $1.survivorID.uuidString }
    }

    /// Entries whose fingerprint the scanner must read before `reconcile`.
    static func candidatePaths(rows: [LibraryRowKey], walk: LibraryWalk) -> [String] {
        self.match(rows: rows, walk: walk).candidates.map(\.entry.relativePath)
    }

    /// Steps 3–4. `fingerprints` maps candidate paths to their content fingerprint; a missing value means
    /// the read failed, which forbids that move.
    static func reconcile(rows: [LibraryRowKey], walk: LibraryWalk, fingerprints: [String: Data]) -> LibraryReconciliation {
        guard walk.coverage != .aborted else { return .empty }
        let matching = self.match(rows: rows, walk: walk)

        var moves: [LibraryMove] = []
        var movedRowIDs: Set<UUID> = []
        var movedPaths: Set<String> = []
        for candidate in matching.candidates where fingerprints[candidate.entry.relativePath] == candidate.row.fingerprint {
            moves.append(LibraryMove(id: candidate.row.id, relativePath: candidate.entry.relativePath))
            movedRowIDs.insert(candidate.row.id)
            movedPaths.insert(candidate.entry.relativePath)
        }

        return LibraryReconciliation(
            moves: moves.sorted { $0.relativePath < $1.relativePath },
            spellingUpdates: matching.spellingUpdates.sorted { $0.relativePath < $1.relativePath },
            foundIDs: Set(matching.matched.map(\.row.id)).union(movedRowIDs),
            missingIDs: Set(matching.unmatchedRows.map(\.id)).subtracting(movedRowIDs),
            newEntries: matching.unmatchedEntries.filter { !movedPaths.contains($0.relativePath) }
                .sorted { $0.relativePath < $1.relativePath },
            staleIDs: Set(matching.matched.filter { $0.row.stat != $0.entry.stat }.map(\.row.id))
        )
    }

    // MARK: - Shared matching

    private struct Pair {
        let row: LibraryRowKey
        let entry: LibraryEntry
    }

    private struct Matching {
        var matched: [Pair] = []
        var spellingUpdates: [LibraryMove] = []
        /// N: entries with no row at their path.
        var unmatchedEntries: [LibraryEntry] = []
        /// U: rows with no entry whose location the walk covered.
        var unmatchedRows: [LibraryRowKey] = []
        var candidates: [Pair] = []
    }

    /// The one routine behind `candidatePaths` and `reconcile`, so eligibility cannot drift between them.
    private static func match(rows: [LibraryRowKey], walk: LibraryWalk) -> Matching {
        guard walk.coverage != .aborted else { return Matching() }
        let caseSensitive = walk.volume.caseSensitive
        var rowsByKey: [String: LibraryRowKey] = [:]
        for row in rows.sorted(by: self.isOlder) where rowsByKey[self.pathKey(row.relativePath, caseSensitive: caseSensitive)] == nil {
            rowsByKey[self.pathKey(row.relativePath, caseSensitive: caseSensitive)] = row
        }

        var matching = Matching()
        var matchedIDs: Set<UUID> = []
        for entry in walk.entries {
            if let row = rowsByKey[self.pathKey(entry.relativePath, caseSensitive: caseSensitive)] {
                matching.matched.append(Pair(row: row, entry: entry))
                matchedIDs.insert(row.id)
                // Scalars, not `==`: Swift string equality treats NFC and NFD spellings as equal.
                if !row.relativePath.unicodeScalars.elementsEqual(entry.relativePath.unicodeScalars) {
                    matching.spellingUpdates.append(LibraryMove(id: row.id, relativePath: entry.relativePath))
                }
            } else {
                matching.unmatchedEntries.append(entry)
            }
        }

        let uncovered: [String] = if case let .partial(folders) = walk.coverage {
            folders.map { self.pathKey($0, caseSensitive: caseSensitive) }
        } else {
            []
        }
        matching.unmatchedRows = rows.filter { row in
            guard !matchedIDs.contains(row.id) else { return false }
            let key = self.pathKey(row.relativePath, caseSensitive: caseSensitive)
            return !uncovered.contains { self.isInside(key, folder: $0) }
        }

        // Moves only on complete walks with rename tracking; ambiguity from walked stats of all entries and
        // stored stats of U only (Revision 5).
        guard walk.coverage == .complete, walk.volume.renameTrackingEnabled else { return matching }
        let walkedByStat = Dictionary(grouping: walk.entries, by: \.stat)
        let unmatchedByStat = Dictionary(grouping: matching.unmatchedRows, by: \.stat)
        for entry in matching.unmatchedEntries {
            guard walkedByStat[entry.stat]?.count == 1,
                  let candidates = unmatchedByStat[entry.stat], candidates.count == 1,
                  candidates[0].fingerprint != nil
            else { continue }
            matching.candidates.append(Pair(row: candidates[0], entry: entry))
        }
        matching.candidates.sort { $0.entry.relativePath < $1.entry.relativePath }
        return matching
    }

    /// Component-aware containment: `crate` contains `crate/a.mp3`, not `crate2/a.mp3`. `""` is the root.
    private static func isInside(_ path: String, folder: String) -> Bool {
        folder.isEmpty || path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }

    private static func isOlder(_ lhs: LibraryRowKey, _ rhs: LibraryRowKey) -> Bool {
        lhs.dateAdded != rhs.dateAdded ? lhs.dateAdded < rhs.dateAdded : lhs.id.uuidString < rhs.id.uuidString
    }
}
