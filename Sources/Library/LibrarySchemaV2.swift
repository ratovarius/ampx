import Foundation
import SwiftData

/// Where a row's BPM and key came from (rekordbox sync spec § Data model).
enum AnalysisSource: String, Codable, Sendable {
    case fileTag
    case rekordbox
}

/// Who set a row's rating. A sync only updates ratings it set itself.
enum RatingSource: String, Codable, Sendable {
    case rekordbox
    case user
}

/// V1 plus the rekordbox fields and one `RekordboxSource` per root (rekordbox sync spec § `LibrarySchemaV2`).
enum LibrarySchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [LibraryRoot.self, LibraryTrack.self, RekordboxSource.self]
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
        /// Where `bpm` / `musicalKey` came from (rekordbox sync spec § Data model); rekordbox wins over tags.
        var analysisSource: AnalysisSource?
        /// Derived from `musicalKey` on every write.
        var camelotKey: String?
        /// JSON of `[RekordboxBeat]`, stored for DJ mode's auto-mix.
        var beatGrid: Data?
        var label: String?
        var remixer: String?
        var composer: String?
        var grouping: String?
        var mix: String?
        var ratingSource: RatingSource?
        /// rekordbox's own count, replaced on each sync; never merged into `playCount`.
        var rekordboxPlayCount: Int = 0

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
            self.schemaVersion = 2
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

    /// The rekordbox export found at a root's top level, and the state of its last import.
    @Model
    final class RekordboxSource {
        @Attribute(.unique) var rootID: UUID
        var fileName: String
        /// False once the export is gone; values and report are kept.
        var isPresent: Bool
        var stampSize: Int64?
        var stampModifiedAt: Date?
        var lastImportAt: Date?
        /// JSON of `RekordboxSyncReport`.
        var lastReport: Data?

        init(rootID: UUID, fileName: String) {
            self.rootID = rootID
            self.fileName = fileName
            self.isPresent = true
        }
    }

    /// V1 → V2: stamp the version and record tagged BPM/key as file-tag values with their Camelot key.
    static let migrateFromV1 = MigrationStage.custom(
        fromVersion: LibrarySchemaV1.self,
        toVersion: LibrarySchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
            for track in try context.fetch(FetchDescriptor<LibraryTrack>()) {
                track.schemaVersion = 2
                if track.bpm != nil || track.musicalKey != nil {
                    track.analysisSource = .fileTag
                }
                track.camelotKey = track.musicalKey.flatMap(CamelotKey.from(musicalKey:))
            }
            try context.save()
        }
    )
}

typealias LibraryRoot = LibrarySchemaV2.LibraryRoot
typealias LibraryTrack = LibrarySchemaV2.LibraryTrack
typealias RekordboxSource = LibrarySchemaV2.RekordboxSource
