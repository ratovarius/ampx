import Foundation
import os
import SwiftData

private let libraryLogger = Logger(subsystem: "com.ampx.macos", category: "Library")

/// `AmpXLibraryHasRoots` (spec: "Start-up and cost"): decides whether the library starts at all.
protocol LibraryStartupFlag: Sendable {
    var hasRoots: Bool { get }
    func setHasRoots(_ value: Bool)
}

final class UserDefaultsLibraryStartupFlag: LibraryStartupFlag, @unchecked Sendable {
    static let key = "AmpXLibraryHasRoots"
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var hasRoots: Bool {
        self.defaults.bool(forKey: Self.key)
    }

    func setHasRoots(_ value: Bool) {
        self.defaults.set(value, forKey: Self.key)
    }
}

struct LibrarySecurityScope: Sendable {
    var start: @Sendable (URL) -> Bool
    var stop: @Sendable (URL) -> Void

    static let foundation = LibrarySecurityScope(
        start: { $0.startAccessingSecurityScopedResource() },
        stop: { $0.stopAccessingSecurityScopedResource() }
    )
}

struct LibraryBookmarking: Sendable {
    var make: @Sendable (URL) throws -> Data
    var resolve: @Sendable (Data) -> ResolvedBookmark?
    var refresh: @Sendable (URL, Bool) -> Data?

    static let securityScoped = LibraryBookmarking(
        make: { try SecurityScopedBookmark.makeData(for: $0, usesSecurityScope: true) },
        resolve: { SecurityScopedBookmark.resolve($0) },
        refresh: { SecurityScopedBookmark.refreshedData(for: $0, usesSecurityScope: $1) }
    )
}

struct LibraryStoreDependencies: Sendable {
    var startupFlag: any LibraryStartupFlag
    var scope: LibrarySecurityScope = .foundation
    var bookmarks: LibraryBookmarking = .securityScoped
    /// Runs synchronously on the writer; injectable so tests can fail a save deterministically.
    var saveContext: @Sendable (ModelContext) throws -> Void = { try $0.save() }
    var now: @Sendable () -> Date = { Date() }
}

/// Issued only by `LibraryStore`; revoked by cancellation, unmount, access loss, relocation and removal.
struct LibraryScanToken: Hashable, Sendable {
    let rootID: UUID
    fileprivate let nonce: UUID
}

enum LibraryStoreError: Error, Equatable {
    case unknownRoot
    case revokedToken
    case overlappingRoot
    case unavailableRoot
    case pathCollision(String)
    case batchTooLarge(Int)
}

/// The library's only SwiftData writer (spec: "LibraryStore"). A hand-written `ModelActor` with one complete
/// initializer, so the actor can never be used before its dependencies are set.
actor LibraryStore: ModelActor {
    static let batchLimit = 200

    nonisolated let modelExecutor: any ModelExecutor
    nonisolated let modelContainer: ModelContainer

    // Internal (not private) so the roots extension in `LibraryStore+Roots.swift` can use them.
    let dependencies: LibraryStoreDependencies
    var activeTokens: [UUID: LibraryScanToken] = [:]
    var subscribers: [UUID: AsyncStream<LibraryChange>.Continuation] = [:]
    /// Security scopes held per available root (spec: "Access lifetime").
    var activeScopes: [UUID: URL] = [:]

    init(modelContainer: ModelContainer, dependencies: LibraryStoreDependencies) {
        let context = ModelContext(modelContainer)
        // Nothing may persist outside the token-validated save path.
        context.autosaveEnabled = false
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.modelContainer = modelContainer
        self.dependencies = dependencies
    }

    // MARK: - Change publication

    /// One stream per subscriber; every committed save yields its changes to each.
    func changes() -> AsyncStream<LibraryChange> {
        let (stream, continuation) = AsyncStream.makeStream(of: LibraryChange.self)
        let id = UUID()
        self.subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        return stream
    }

    private func removeSubscriber(_ id: UUID) {
        self.subscribers[id] = nil
    }

    // MARK: - Tokens

    func beginScan(rootID: UUID) throws -> LibraryScanToken {
        guard try self.root(rootID) != nil else { throw LibraryStoreError.unknownRoot }
        let token = LibraryScanToken(rootID: rootID, nonce: UUID())
        self.activeTokens[rootID] = token
        return token
    }

    func revokeScan(rootID: UUID) {
        self.activeTokens[rootID] = nil
    }

    // MARK: - Reads

    func rowKeys(rootID: UUID) throws -> [LibraryRowKey] {
        try self.tracks(rootID).map {
            LibraryRowKey(
                id: $0.id,
                relativePath: $0.relativePath,
                stat: LibraryStat(fileSize: $0.fileSize, contentModifiedAt: $0.contentModifiedAt),
                fingerprint: $0.contentFingerprint,
                dateAdded: $0.dateAdded,
                history: LibraryHistory(playCount: $0.playCount, lastPlayedAt: $0.lastPlayedAt, rating: $0.rating),
                isMissing: $0.isMissing
            )
        }
    }

    // MARK: - Scan transactions

    /// Step 1: merge rows that share a path key into their survivors, in one save.
    func applyIntegrityMerges(_ merges: [LibraryIntegrityMerge], token: LibraryScanToken) throws {
        try self.commit(token) {
            guard !merges.isEmpty else { return [] }
            let rows = try Dictionary(uniqueKeysWithValues: self.tracks(token.rootID).map { ($0.id, $0) })
            for merge in merges {
                guard let survivor = rows[merge.survivorID] else { continue }
                survivor.playCount = merge.history.playCount
                survivor.lastPlayedAt = merge.history.lastPlayedAt
                survivor.rating = merge.history.rating
                for id in merge.deletedIDs {
                    if let row = rows[id] {
                        self.modelContext.delete(row)
                    }
                }
                libraryLogger.fault("Merged \(merge.deletedIDs.count) duplicate rows into \(merge.survivorID, privacy: .public)")
            }
            return [.rowsChanged(rootID: token.rootID)]
        }
    }

    /// Step 5: moves, spellings, found/missing flags and the unreadable-folder count, in one save.
    func applyStructure(_ plan: LibraryReconciliation, token: LibraryScanToken, unreadableFolderCount: Int) throws {
        try self.commit(token) {
            var changes: [LibraryChange] = []
            if let root = try self.root(token.rootID), root.unreadableFolderCount != unreadableFolderCount {
                root.unreadableFolderCount = unreadableFolderCount
                changes.append(.rootsChanged(rootID: token.rootID))
            }

            var rowsChanged = false
            let rows = try Dictionary(uniqueKeysWithValues: self.tracks(token.rootID).map { ($0.id, $0) })
            for update in plan.moves + plan.spellingUpdates {
                guard let row = rows[update.id],
                      !row.relativePath.unicodeScalars.elementsEqual(update.relativePath.unicodeScalars)
                else { continue }
                row.relativePath = update.relativePath
                rowsChanged = true
            }
            for id in plan.foundIDs {
                if let row = rows[id], row.isMissing {
                    row.isMissing = false
                    rowsChanged = true
                }
            }
            for id in plan.missingIDs {
                if let row = rows[id], !row.isMissing {
                    row.isMissing = true
                    rowsChanged = true
                }
            }
            if rowsChanged {
                changes.append(.rowsChanged(rootID: token.rootID))
            }
            return changes
        }
    }

    /// Step 6: insert new rows and update re-parsed ones, at most `batchLimit` per save. Inserts never upsert.
    func applyParsed(_ writes: [LibraryParseWrite], token: LibraryScanToken) throws {
        guard writes.count <= Self.batchLimit else { throw LibraryStoreError.batchTooLarge(writes.count) }
        try self.commit(token) {
            guard !writes.isEmpty else { return [] }
            let existing = try self.tracks(token.rootID)
            let rows = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
            var pathKeys = Set(existing.map { LibraryReconciler.pathKey($0.relativePath, caseSensitive: true) })

            for write in writes {
                let row: LibraryTrack
                if write.isInsert {
                    guard pathKeys.insert(LibraryReconciler.pathKey(write.relativePath, caseSensitive: true)).inserted else {
                        throw LibraryStoreError.pathCollision(write.relativePath)
                    }
                    row = LibraryTrack(
                        id: write.id, rootID: token.rootID, relativePath: write.relativePath,
                        title: write.metadata.title, artist: write.metadata.artist,
                        fileSize: write.stat.fileSize, contentModifiedAt: write.stat.contentModifiedAt,
                        dateAdded: self.dependencies.now()
                    )
                    self.modelContext.insert(row)
                } else {
                    guard let existingRow = rows[write.id] else { continue }
                    row = existingRow
                }
                Self.apply(write, to: row)
            }
            return [.rowsChanged(rootID: token.rootID)]
        }
    }

    /// Step 7: only a complete walk calls this.
    func finishScan(token: LibraryScanToken) throws {
        try self.commit(token) {
            try self.root(token.rootID)?.lastCompletedScanAt = self.dependencies.now()
            return [.rootsChanged(rootID: token.rootID)]
        }
    }

    // MARK: - Transaction core

    /// Validates the token, applies `mutate`, saves, and publishes only after the save succeeds.
    /// No suspension point inside, so revocation cannot interleave with a save.
    func commit(_ token: LibraryScanToken?, _ mutate: () throws -> [LibraryChange]) throws {
        if let token {
            guard self.activeTokens[token.rootID] == token else { throw LibraryStoreError.revokedToken }
            guard try self.root(token.rootID) != nil else {
                self.activeTokens[token.rootID] = nil
                throw LibraryStoreError.unknownRoot
            }
        }
        let changes: [LibraryChange]
        do {
            changes = try mutate()
            if self.modelContext.hasChanges {
                try self.dependencies.saveContext(self.modelContext)
            }
        } catch {
            self.modelContext.rollback()
            throw error
        }
        for change in changes {
            for continuation in self.subscribers.values {
                continuation.yield(change)
            }
        }
    }

    func root(_ id: UUID) throws -> LibraryRoot? {
        var descriptor = FetchDescriptor<LibraryRoot>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try self.modelContext.fetch(descriptor).first
    }

    func tracks(_ rootID: UUID) throws -> [LibraryTrack] {
        try self.modelContext.fetch(FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.rootID == rootID }))
    }

    private static func apply(_ write: LibraryParseWrite, to row: LibraryTrack) {
        let metadata = write.metadata
        row.relativePath = write.relativePath
        row.title = metadata.title
        row.artist = metadata.artist
        row.album = metadata.album
        row.albumArtist = metadata.albumArtist
        row.genre = metadata.genre
        row.year = metadata.year
        row.trackNumber = metadata.trackNumber
        row.duration = metadata.duration
        row.fileSize = write.stat.fileSize
        row.contentModifiedAt = write.stat.contentModifiedAt
        row.contentFingerprint = write.fingerprint
        row.bitrate = metadata.bitrate
        row.bitrateIsDerived = metadata.bitrateIsDerived
        row.sampleRate = metadata.sampleRate
        row.channels = metadata.channels
        row.codec = metadata.codec
        // Imported rekordbox values survive re-parses (rekordbox sync spec § Scanner re-parse rule).
        if row.analysisSource != .rekordbox {
            row.bpm = metadata.bpm
            row.musicalKey = metadata.musicalKey
            row.analysisSource = metadata.bpm == nil && metadata.musicalKey == nil ? nil : .fileTag
            row.camelotKey = metadata.musicalKey.flatMap(CamelotKey.from(musicalKey:))
        }
        row.comment = metadata.comment
        row.isMissing = false
    }
}
