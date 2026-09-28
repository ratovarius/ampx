import Foundation

/// A root as the planner sees it: its resolved, NFC path and whether its volume folds case.
struct RekordboxRootPath: Sendable, Equatable {
    let id: UUID
    let path: String
    let caseSensitive: Bool
}

/// A row's key and the current value of every field a sync may write.
struct RekordboxRowSnapshot: Sendable, Equatable {
    let id: UUID
    let rootID: UUID
    let relativePath: String
    let fileSize: Int64
    let duration: Double
    let bpm: Double?
    let musicalKey: String?
    let analysisSource: AnalysisSource?
    let rating: Int
    let ratingSource: RatingSource?
    let rekordboxPlayCount: Int
    let label, remixer, composer, grouping, mix: String?
    let beatGrid: Data?
}

struct RekordboxLibrarySnapshot: Sendable {
    let roots: [RekordboxRootPath]
    let rows: [RekordboxRowSnapshot]
}

/// A row's full target state; the store writes all of it.
struct RekordboxRowValues: Sendable, Equatable {
    var bpm: Double?
    var musicalKey: String?
    var analysisSource: AnalysisSource?
    var rating: Int
    var ratingSource: RatingSource?
    var rekordboxPlayCount: Int
    var label, remixer, composer, grouping, mix: String?
    var beatGrid: Data?
}

struct RekordboxRowWrite: Sendable, Equatable {
    let rowID: UUID
    let rootID: UUID
    let values: RekordboxRowValues
}

struct RekordboxSyncReport: Codable, Sendable, Equatable {
    struct Ambiguity: Codable, Sendable, Equatable {
        let path: String
        let candidates: [String]
    }

    struct RatingConflict: Codable, Sendable, Equatable {
        let path: String
        let library: Int
        let rekordbox: Int
    }

    var fileName = ""
    var matched = 0
    var updated = 0
    var droppedWithoutLocation = 0
    var unmatched: [String] = []
    var ambiguous: [Ambiguity] = []
    var ratingConflicts: [RatingConflict] = []
    var noLongerInRekordbox: [String] = []
}

struct RekordboxImportPlan: Sendable, Equatable {
    let writes: [RekordboxRowWrite]
    let report: RekordboxSyncReport
}

/// Matches an export against the library and decides what to write (rekordbox sync spec § `RekordboxImportPlanner`).
/// Matching runs in two passes, paths first, so a copy stored elsewhere never claims a row before its own entry.
enum RekordboxImportPlanner {
    static func plan(
        _ collection: RekordboxCollection,
        fileName: String,
        sourceRootID: UUID,
        library: RekordboxLibrarySnapshot
    ) -> RekordboxImportPlan {
        var report = RekordboxSyncReport(fileName: fileName, droppedWithoutLocation: collection.droppedWithoutLocation)
        let roots = Dictionary(uniqueKeysWithValues: library.roots.map { ($0.id, $0) })
        let rowsByID = Dictionary(uniqueKeysWithValues: library.rows.map { ($0.id, $0) })
        func fullPath(_ row: RekordboxRowSnapshot) -> String {
            (roots[row.rootID]?.path ?? "") + "/" + row.relativePath
        }

        // Pass 1: paths. A row claimed by two entries is ambiguous for both.
        var byPath: [UUID: [String: UUID]] = [:]
        for row in library.rows {
            let caseSensitive = roots[row.rootID]?.caseSensitive ?? true
            byPath[row.rootID, default: [:]][self.key(row.relativePath, caseSensitive: caseSensitive)] = row.id
        }
        var pathClaims: [UUID: [Int]] = [:]
        var unresolved: [Int] = []
        for (index, track) in collection.tracks.enumerated() {
            if let rowID = self.pathMatch(track.path, roots: library.roots, byPath: byPath) {
                pathClaims[rowID, default: []].append(index)
            } else {
                unresolved.append(index)
            }
        }

        // Pass 2: size + duration, only for unresolved entries and only against rows pass 1 left unclaimed.
        let bySize = Dictionary(grouping: library.rows.filter { pathClaims[$0.id] == nil }, by: \.fileSize)
        var fallbackClaims: [UUID: [Int]] = [:]
        for index in unresolved {
            let track = collection.tracks[index]
            let candidates = track.size.flatMap { size in
                track.duration.map { duration in
                    (bySize[size] ?? []).filter { abs($0.duration - duration) <= 1 }
                }
            } ?? []
            switch candidates.count {
            case 0:
                report.unmatched.append(track.path)
            case 1:
                fallbackClaims[candidates[0].id, default: []].append(index)
            default:
                report.ambiguous.append(.init(path: track.path, candidates: candidates.map(fullPath).sorted()))
            }
        }

        var matchedRows: [(row: RekordboxRowSnapshot, track: RekordboxTrack)] = []
        for (rowID, claims) in pathClaims.merging(fallbackClaims, uniquingKeysWith: +) {
            guard let row = rowsByID[rowID] else { continue }
            if claims.count == 1 {
                matchedRows.append((row, collection.tracks[claims[0]]))
            } else {
                for index in claims {
                    report.ambiguous.append(.init(path: collection.tracks[index].path, candidates: [fullPath(row)]))
                }
            }
        }
        matchedRows.sort { $0.row.id.uuidString < $1.row.id.uuidString }
        report.matched = matchedRows.count

        var writes: [RekordboxRowWrite] = []
        for (row, track) in matchedRows {
            let values = self.target(row, track: track, conflicts: &report.ratingConflicts, path: fullPath(row))
            if values != self.current(row) {
                writes.append(RekordboxRowWrite(rowID: row.id, rootID: row.rootID, values: values))
            }
        }
        report.updated = writes.count

        let matchedIDs = Set(matchedRows.map(\.row.id))
        report.noLongerInRekordbox = library.rows
            .filter { $0.rootID == sourceRootID && $0.analysisSource == .rekordbox && !matchedIDs.contains($0.id) }
            .map(fullPath)
            .sorted()
        return RekordboxImportPlan(writes: writes, report: report)
    }

    // MARK: - Matching

    private static func key(_ path: String, caseSensitive: Bool) -> String {
        let normalized = path.precomposedStringWithCanonicalMapping
        return caseSensitive ? normalized : normalized.lowercased()
    }

    private static func pathMatch(_ path: String, roots: [RekordboxRootPath], byPath: [UUID: [String: UUID]]) -> UUID? {
        for root in roots {
            let prefix = self.key(root.path, caseSensitive: root.caseSensitive) + "/"
            let candidate = self.key(path, caseSensitive: root.caseSensitive)
            guard candidate.hasPrefix(prefix) else { continue }
            if let rowID = byPath[root.id]?[String(candidate.dropFirst(prefix.count))] {
                return rowID
            }
        }
        return nil
    }

    // MARK: - Values

    private static func current(_ row: RekordboxRowSnapshot) -> RekordboxRowValues {
        RekordboxRowValues(
            bpm: row.bpm, musicalKey: row.musicalKey, analysisSource: row.analysisSource,
            rating: row.rating, ratingSource: row.ratingSource, rekordboxPlayCount: row.rekordboxPlayCount,
            label: row.label, remixer: row.remixer, composer: row.composer, grouping: row.grouping, mix: row.mix,
            beatGrid: row.beatGrid
        )
    }

    private static func target(
        _ row: RekordboxRowSnapshot,
        track: RekordboxTrack,
        conflicts: inout [RekordboxSyncReport.RatingConflict],
        path: String
    ) -> RekordboxRowValues {
        var values = self.current(row)
        if track.bpm != nil || track.tonality != nil {
            values.bpm = track.bpm ?? row.bpm
            values.musicalKey = track.tonality ?? row.musicalKey
            values.analysisSource = .rekordbox
        }
        if let rating = track.rating {
            if row.ratingSource == .user {
                if rating != row.rating {
                    conflicts.append(.init(path: path, library: row.rating, rekordbox: rating))
                }
            } else {
                values.rating = rating
                values.ratingSource = .rekordbox
            }
        }
        values.rekordboxPlayCount = track.playCount ?? row.rekordboxPlayCount
        values.label = track.label
        values.remixer = track.remixer
        values.composer = track.composer
        values.grouping = track.grouping
        values.mix = track.mix
        values.beatGrid = self.encode(track.beatGrid)
        return values
    }

    private static func encode(_ grid: [RekordboxBeat]) -> Data? {
        guard !grid.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(grid)
    }
}
