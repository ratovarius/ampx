import Foundation
import SwiftData

/// The stamp that says whether an export changed since its last import.
struct RekordboxFileStamp: Codable, Sendable, Equatable {
    let size: Int64
    let modifiedAt: Date
}

/// Issued only by `LibraryStore`, one live token per root; revoked when the root is removed or relocated.
struct RekordboxSyncToken: Hashable, Sendable {
    let rootID: UUID
    fileprivate let nonce: UUID
}

struct RekordboxSourceSnapshot: Sendable, Equatable {
    let rootID: UUID
    let fileName: String
    let isPresent: Bool
    let stamp: RekordboxFileStamp?
    let lastImportAt: Date?
    let lastReport: RekordboxSyncReport?
}

/// Store side of the rekordbox sync (rekordbox sync spec § `LibraryStore.applyRekordbox`).
extension LibraryStore {
    /// Every root, available or not, and every row. `caseSensitivity` comes from the roots' volumes; a root
    /// missing from it is treated as case-sensitive.
    func rekordboxSnapshot(caseSensitivity: [UUID: Bool] = [:]) throws -> RekordboxLibrarySnapshot {
        let roots = try self.modelContext.fetch(FetchDescriptor<LibraryRoot>()).map {
            RekordboxRootPath(
                id: $0.id, path: $0.displayPath.precomposedStringWithCanonicalMapping,
                caseSensitive: caseSensitivity[$0.id] ?? true
            )
        }
        let rows = try self.modelContext.fetch(FetchDescriptor<LibraryTrack>()).map {
            RekordboxRowSnapshot(
                id: $0.id, rootID: $0.rootID, relativePath: $0.relativePath, fileSize: $0.fileSize, duration: $0.duration,
                bpm: $0.bpm, musicalKey: $0.musicalKey, analysisSource: $0.analysisSource,
                rating: $0.rating, ratingSource: $0.ratingSource, rekordboxPlayCount: $0.rekordboxPlayCount,
                label: $0.label, remixer: $0.remixer, composer: $0.composer, grouping: $0.grouping, mix: $0.mix,
                beatGrid: $0.beatGrid
            )
        }
        return RekordboxLibrarySnapshot(roots: roots, rows: rows)
    }

    func rekordboxSources() throws -> [RekordboxSourceSnapshot] {
        try self.modelContext.fetch(FetchDescriptor<RekordboxSource>()).map {
            let stamp: RekordboxFileStamp? = if let size = $0.stampSize, let date = $0.stampModifiedAt {
                RekordboxFileStamp(size: size, modifiedAt: date)
            } else {
                nil
            }
            return RekordboxSourceSnapshot(
                rootID: $0.rootID, fileName: $0.fileName, isPresent: $0.isPresent, stamp: stamp,
                lastImportAt: $0.lastImportAt,
                lastReport: $0.lastReport.flatMap { try? JSONDecoder().decode(RekordboxSyncReport.self, from: $0) }
            )
        }
    }

    func beginRekordboxSync(rootID: UUID) throws -> RekordboxSyncToken {
        guard try self.root(rootID) != nil else { throw LibraryStoreError.unknownRoot }
        let token = RekordboxSyncToken(rootID: rootID, nonce: UUID())
        self.rekordboxTokens[rootID] = token
        return token
    }

    func revokeRekordboxSync(rootID: UUID) {
        self.rekordboxTokens[rootID] = nil
    }

    /// One transaction: the plan's rows plus the root's source. Writes for rows that no longer exist are skipped.
    func applyRekordbox(
        _ plan: RekordboxImportPlan,
        fileName: String,
        stamp: RekordboxFileStamp,
        token: RekordboxSyncToken
    ) throws {
        try self.checkRekordbox(token)
        let report = try JSONEncoder().encode(plan.report)
        try self.commit(nil) {
            let rows = try Dictionary(
                uniqueKeysWithValues: self.modelContext.fetch(FetchDescriptor<LibraryTrack>()).map { ($0.id, $0) }
            )
            var roots: [UUID] = []
            for write in plan.writes {
                guard let row = rows[write.rowID] else { continue }
                Self.apply(write.values, to: row)
                if !roots.contains(row.rootID) {
                    roots.append(row.rootID)
                }
            }
            let source = try self.rekordboxSource(token.rootID) ?? {
                let created = RekordboxSource(rootID: token.rootID, fileName: fileName)
                self.modelContext.insert(created)
                return created
            }()
            source.fileName = fileName
            source.isPresent = true
            source.stampSize = stamp.size
            source.stampModifiedAt = stamp.modifiedAt
            source.lastImportAt = self.dependencies.now()
            source.lastReport = report
            return roots.map { .rowsChanged(rootID: $0) } + [.rekordboxSourcesChanged]
        }
    }

    /// The export is gone: keep its values, stamp and report, and mark it not present.
    func markRekordboxSourceAbsent(rootID: UUID) throws {
        try self.commit(nil) {
            guard let source = try self.rekordboxSource(rootID), source.isPresent else { return [] }
            source.isPresent = false
            return [.rekordboxSourcesChanged]
        }
    }

    func rekordboxSource(_ rootID: UUID) throws -> RekordboxSource? {
        var descriptor = FetchDescriptor<RekordboxSource>(predicate: #Predicate { $0.rootID == rootID })
        descriptor.fetchLimit = 1
        return try self.modelContext.fetch(descriptor).first
    }

    private func checkRekordbox(_ token: RekordboxSyncToken) throws {
        guard self.rekordboxTokens[token.rootID] == token else { throw LibraryStoreError.revokedToken }
        guard try self.root(token.rootID) != nil else {
            self.rekordboxTokens[token.rootID] = nil
            throw LibraryStoreError.unknownRoot
        }
    }

    private static func apply(_ values: RekordboxRowValues, to row: LibraryTrack) {
        row.bpm = values.bpm
        row.musicalKey = values.musicalKey
        row.analysisSource = values.analysisSource
        row.camelotKey = values.musicalKey.flatMap(CamelotKey.from(musicalKey:))
        row.rating = values.rating
        row.ratingSource = values.ratingSource
        row.rekordboxPlayCount = values.rekordboxPlayCount
        row.label = values.label
        row.remixer = values.remixer
        row.composer = values.composer
        row.grouping = values.grouping
        row.mix = values.mix
        row.beatGrid = values.beatGrid
    }
}
