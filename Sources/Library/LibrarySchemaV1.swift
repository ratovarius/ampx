import CoreData
import Foundation
import SwiftData

/// Storage-only models (spec: "Models (`LibrarySchemaV1`)"). Only `id` is unique: SwiftData's `.unique`
/// upserts on collision, so path uniqueness is a scanner invariant, not a constraint.
enum LibrarySchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [LibraryRoot.self, LibraryTrack.self]
    }

    @Model
    final class LibraryRoot {
        @Attribute(.unique) var id: UUID
        /// Security-scoped folder bookmark; refreshed when resolution reports stale.
        var bookmark: Data
        var displayPath: String
        var isAvailable: Bool
        var unreadableFolderCount: Int
        var addedAt: Date
        /// Set only by a complete walk.
        var lastCompletedScanAt: Date?

        init(id: UUID, bookmark: Data, displayPath: String, addedAt: Date) {
            self.id = id
            self.bookmark = bookmark
            self.displayPath = displayPath
            self.isAvailable = true
            self.unreadableFolderCount = 0
            self.addedAt = addedAt
            self.lastCompletedScanAt = nil
        }
    }

    @Model
    final class LibraryTrack {
        #Index<LibraryTrack>([\.rootID], [\.rootID, \.relativePath])

        @Attribute(.unique) var id: UUID
        var rootID: UUID
        var relativePath: String
        var schemaVersion: Int
        var title: String
        var artist: String
        var album: String
        var albumArtist: String
        var genre: String?
        var year: Int?
        var trackNumber: Int?
        var duration: Double
        var fileSize: Int64
        var contentModifiedAt: Date
        var contentFingerprint: Data?
        var bitrate: Int
        var bitrateIsDerived: Bool
        var sampleRate: Int
        var channels: Int
        var codec: String
        var bpm: Double?
        var musicalKey: String?
        var comment: String?
        var dateAdded: Date
        var lastPlayedAt: Date?
        var playCount: Int
        var rating: Int
        var isMissing: Bool

        init(
            id: UUID,
            rootID: UUID,
            relativePath: String,
            title: String,
            artist: String,
            fileSize: Int64,
            contentModifiedAt: Date,
            dateAdded: Date
        ) {
            self.id = id
            self.rootID = rootID
            self.relativePath = relativePath
            self.schemaVersion = 1
            self.title = title
            self.artist = artist
            self.album = ""
            self.albumArtist = ""
            self.duration = 0
            self.fileSize = fileSize
            self.contentModifiedAt = contentModifiedAt
            self.bitrate = 0
            self.bitrateIsDerived = false
            self.sampleRate = 0
            self.channels = 0
            self.codec = ""
            self.dateAdded = dateAdded
            self.playCount = 0
            self.rating = 0
            self.isMissing = false
        }
    }
}

typealias LibraryRoot = LibrarySchemaV1.LibraryRoot
typealias LibraryTrack = LibrarySchemaV1.LibraryTrack

enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [LibrarySchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

enum LibraryContainerError: Error, Equatable {
    /// The store was written by a newer app version; opening it would silently migrate it down.
    case newerSchema(found: String)
}

enum LibraryContainerFactory {
    /// `nil` URL keeps the store in memory (tests). Always applies `LibraryMigrationPlan`.
    /// An open failure propagates; the store is never deleted or replaced to recover.
    static func make(url: URL?) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        let configuration: ModelConfiguration
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try self.rejectNewerStore(at: url)
            configuration = ModelConfiguration(schema: schema, url: url)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        }
        return try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: configuration)
    }

    /// SwiftData does not refuse a store from a newer `VersionedSchema`: it opens and migrates it down.
    /// The spec requires refusing, so compare the version SwiftData stamped into the store's metadata
    /// with the newest schema in the migration plan before opening.
    private static func rejectNewerStore(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path),
              let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url),
              let identifiers = metadata[NSStoreModelVersionIdentifiersKey] as? [String]
        else { return }
        let newestKnown = LibraryMigrationPlan.schemas.map { self.components($0.versionIdentifier.description) }
            .max { $0.lexicographicallyPrecedes($1) } ?? []
        for identifier in identifiers where newestKnown.lexicographicallyPrecedes(self.components(identifier)) {
            throw LibraryContainerError.newerSchema(found: identifier)
        }
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }

    /// Application Support/AmpX/Library/Library.store (inside the sandbox container).
    static var defaultURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("AmpX/Library/Library.store")
    }
}
