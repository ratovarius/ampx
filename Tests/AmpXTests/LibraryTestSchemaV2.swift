@testable import AmpX
import Foundation
import SwiftData

/// Test-only V2 (spec: "Schema versioning"): V1 plus one optional field, reached by a lightweight
/// change whose `didMigrate` stamps `schemaVersion = 2`. Never shipped.
enum LibraryTestSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [LibraryRoot.self, LibraryTrack.self]
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
        var camelotKey: String?

        init(id: UUID, rootID: UUID, relativePath: String, title: String, artist: String) {
            self.id = id
            self.rootID = rootID
            self.relativePath = relativePath
            self.schemaVersion = 2
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

    enum MigrationPlan: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] {
            [LibrarySchemaV1.self, LibraryTestSchemaV2.self]
        }

        static var stages: [MigrationStage] {
            [
                .custom(
                    fromVersion: LibrarySchemaV1.self,
                    toVersion: LibraryTestSchemaV2.self,
                    willMigrate: nil,
                    didMigrate: { context in
                        for track in try context.fetch(FetchDescriptor<LibraryTestSchemaV2.LibraryTrack>()) {
                            track.schemaVersion = 2
                        }
                        try context.save()
                    }
                ),
            ]
        }
    }

    static func makeContainer(url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LibraryTestSchemaV2.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: MigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url)
        )
    }
}
