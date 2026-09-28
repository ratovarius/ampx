import Foundation

/// One `<TEMPO>` element of a rekordbox beatgrid.
struct RekordboxBeat: Codable, Equatable, Sendable {
    let start: Double
    let bpm: Double
    let meter: String
    let beat: Int
}

/// One `COLLECTION/TRACK` of a rekordbox export, with every field optional except the path.
struct RekordboxTrack: Equatable, Sendable {
    /// Decoded, standardised, symlink-resolved, NFC absolute path.
    let path: String
    let size: Int64?
    let duration: Double?
    let bpm: Double?
    let tonality: String?
    /// Already scaled to 0…5.
    let rating: Int?
    let playCount: Int?
    let label, remixer, composer, grouping, mix: String?
    let beatGrid: [RekordboxBeat]
}

struct RekordboxCollection: Equatable, Sendable {
    let productVersion: String?
    let tracks: [RekordboxTrack]
    let droppedWithoutLocation: Int
}
