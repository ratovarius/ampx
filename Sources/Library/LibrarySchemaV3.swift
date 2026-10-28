import Foundation
import SwiftData

/// V2 plus DJ mode's fields: cues, tempo spread, rekordbox phrases, the mix-point scan and the tag-write record
/// (DJ mode spec Revision 2 § Data model).
enum LibrarySchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
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
        /// Packed `RekordboxCues`; stored for later cue UI, never displayed in this revision.
        var cues: Data?
        /// `(max − min) / median` of the beatgrid's BPMs, in percent; recomputed whenever `beatGrid` changes.
        var tempoSpread: Double?
        /// Packed `RekordboxPhraseAnalysis` from rekordbox's ANLZ files.
        var phrases: Data?
        /// JSON `RekordboxFileStamp` of the `.EXT` file `phrases` came from.
        var phrasesStamp: Data?
        /// AmpX's per-bar energy scan (DJ mode delivery 2).
        var mixScan: Data?
        /// Hash of the tag values last written to, or confirmed in, the file.
        var tagsWrittenHash: Data?

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
            self.schemaVersion = 3
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

    /// V2 → V3: stamp the version and derive the tempo spread from the stored beatgrid.
    static let migrateFromV2 = MigrationStage.custom(
        fromVersion: LibrarySchemaV2.self,
        toVersion: LibrarySchemaV3.self,
        willMigrate: nil,
        didMigrate: { context in
            for track in try context.fetch(FetchDescriptor<LibraryTrack>()) {
                track.schemaVersion = 3
                track.tempoSpread = track.beatGrid.flatMap(RekordboxBeatGrid.unpack).flatMap(RekordboxBeatGrid.tempoSpread)
            }
            try context.save()
        }
    )
}

typealias LibraryRoot = LibrarySchemaV3.LibraryRoot
typealias LibraryTrack = LibrarySchemaV3.LibraryTrack
typealias RekordboxSource = LibrarySchemaV3.RekordboxSource
