@testable import AmpX
import Foundation
import SwiftData

/// Test-only V4 (spec: "Schema versioning"): the shipped V3 plus one optional field, reached by a custom stage
/// whose `didMigrate` stamps `schemaVersion = 4`. Never shipped; proves a store can move past the newest shipped schema.
enum LibraryTestSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] {
        [LibraryRoot.self, LibraryTrack.self, RekordboxSource.self]
    }

    @Model
    final class LibraryRoot {
        @Attribute(.unique) var id: UUID
        var bookmark: Data
        var displayPath: String
        var isAvailable: Bool
        var unreadableFolderCount: Int
        var addedAt: Date
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
        var analysisSource: AnalysisSource?
        var camelotKey: String?
        var beatGrid: Data?
        var label: String?
        var remixer: String?
        var composer: String?
        var grouping: String?
        var mix: String?
        var ratingSource: RatingSource?
        var rekordboxPlayCount: Int = 0
        var cues: Data?
        var tempoSpread: Double?
        var phrases: Data?
        var phrasesStamp: Data?
        var mixScan: Data?
        var tagsWrittenHash: Data?
        var testOnlyField: String?

        init(id: UUID, rootID: UUID, relativePath: String, title: String, artist: String) {
            self.id = id
            self.rootID = rootID
            self.relativePath = relativePath
            self.schemaVersion = 4
            self.title = title
            self.artist = artist
            self.album = ""
            self.albumArtist = ""
            self.duration = 0
            self.fileSize = 0
            self.contentModifiedAt = .distantPast
            self.bitrate = 0
            self.bitrateIsDerived = false
            self.sampleRate = 0
            self.channels = 0
            self.codec = ""
            self.dateAdded = .distantPast
            self.playCount = 0
            self.rating = 0
            self.isMissing = false
        }
    }

    @Model
    final class RekordboxSource {
        @Attribute(.unique) var rootID: UUID
        var fileName: String
        var isPresent: Bool
        var stampSize: Int64?
        var stampModifiedAt: Date?
        var lastImportAt: Date?
        var lastReport: Data?

        init(rootID: UUID, fileName: String) {
            self.rootID = rootID
            self.fileName = fileName
            self.isPresent = true
        }
    }

    enum MigrationPlan: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] {
            LibraryMigrationPlan.schemas + [LibraryTestSchemaV4.self]
        }

        static var stages: [MigrationStage] {
            LibraryMigrationPlan.stages + [
                .custom(
                    fromVersion: LibrarySchemaV3.self,
                    toVersion: LibraryTestSchemaV4.self,
                    willMigrate: nil,
                    didMigrate: { context in
                        for track in try context.fetch(FetchDescriptor<LibraryTestSchemaV4.LibraryTrack>()) {
                            track.schemaVersion = 4
                        }
                        try context.save()
                    }
                ),
            ]
        }
    }

    static func makeContainer(url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LibraryTestSchemaV4.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: MigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url)
        )
    }
}
