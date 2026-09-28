import Foundation

// Sendable values that cross the library's actor boundaries. No SwiftData types here: `@Model` instances
// never leave `LibraryStore` or `LibraryIndex` (spec: "Model split").

/// The row the browser sees (spec: "`LibraryRow`").
struct LibraryRow: Identifiable, Hashable, Sendable {
    let id: UUID
    let rootID: UUID
    var url: URL
    let title, artist, album, albumArtist: String
    let genre: String?
    let trackNumber: Int?
    let duration: Double
    let fileSize: Int64
    let bpm: Double?
    let musicalKey: String?
    var camelotKey: String?
    var label: String?
    var remixer: String?
    var composer: String?
    var grouping: String?
    var mix: String?
    let bitrate: Int
    let bitrateIsDerived: Bool
    let codec: String
    var isAvailable: Bool
    let searchKey: String

    /// A new playback occurrence each call: enqueuing the same row twice yields two playlist entries.
    func makeTrack() -> Track {
        Track(title: self.title, artist: self.artist, duration: self.duration, fileSize: self.fileSize, url: self.url)
    }
}

/// Staleness key and half of the rename candidate key.
struct LibraryStat: Hashable, Sendable {
    let fileSize: Int64
    let contentModifiedAt: Date
}

/// Reserved fields, preserved across moves and combined only by integrity repair.
struct LibraryHistory: Equatable, Sendable {
    var playCount: Int
    var lastPlayedAt: Date?
    var rating: Int
}

/// A row's stored state as the scanner and reconciler see it.
struct LibraryRowKey: Sendable {
    let id: UUID
    let relativePath: String
    let stat: LibraryStat
    let fingerprint: Data?
    let dateAdded: Date
    let history: LibraryHistory
    let isMissing: Bool
}

struct LibraryRootSnapshot: Sendable, Equatable {
    let id: UUID
    let url: URL
    let displayPath: String
    let isAvailable: Bool
    let unreadableFolderCount: Int
    let lastCompletedScanAt: Date?
}

/// One audio file found by a walk.
struct LibraryEntry: Sendable, Equatable {
    let relativePath: String
    let stat: LibraryStat
}

enum LibraryCoverage: Equatable, Sendable {
    case complete
    /// Relative paths of folders the walk could not read.
    case partial(uncoveredFolders: Set<String>)
    case aborted
}

struct LibraryVolume: Sendable, Equatable {
    let caseSensitive: Bool
    /// `URLResourceKey.volumeTypeNameKey`, e.g. `apfs`.
    let typeName: String

    var renameTrackingEnabled: Bool {
        LibraryRenameTracking.isEnabled(volumeType: self.typeName)
    }
}

struct LibraryWalk: Sendable {
    let entries: [LibraryEntry]
    let coverage: LibraryCoverage
    let volume: LibraryVolume
}

/// A parsed file ready to insert (`isInsert`, new id) or update (existing id; the store keeps dateAdded/history).
struct LibraryParseWrite: Sendable {
    let id: UUID
    let isInsert: Bool
    let relativePath: String
    let stat: LibraryStat
    let metadata: TrackMetadataLoader.Metadata
    let fingerprint: Data?
}

/// Published by `LibraryStore` after every committed save (spec: "Change publication").
enum LibraryChange: Sendable, Equatable {
    case rootsChanged(rootID: UUID)
    case rootRemoved(rootID: UUID)
    case rowsChanged(rootID: UUID)
    /// A root's `RekordboxSource` was created, updated or removed.
    case rekordboxSourcesChanged
}

struct ScanProgress: Sendable, Equatable {
    enum Phase: Sendable {
        case walking, reconciling, parsing
        /// Published when a run ends, however it ends (complete, aborted, failed or cancelled).
        case finished
    }

    let rootID: UUID
    let phase: Phase
    let done: Int
    let total: Int
}
