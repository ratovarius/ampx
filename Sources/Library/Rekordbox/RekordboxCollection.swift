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

/// Compact storage for a beatgrid (`LibraryTrack.beatGrid`). rekordbox writes one `TEMPO` per bar for dynamic
/// grids (538,178 across the 2,232-track collection), so JSON was too slow to encode on every check.
/// Layout: version byte `1`, then per beat: start and BPM as little-endian Float64 bit patterns, beat as UInt8,
/// meter as a UInt8 length plus UTF-8 bytes.
enum RekordboxBeatGrid {
    private static let version: UInt8 = 1

    static func pack(_ grid: [RekordboxBeat]) -> Data {
        let size = grid.reduce(1) { $0 + 18 + min(255, $1.meter.utf8.count) }
        var data = Data(count: size)
        data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            buffer[0] = self.version
            var offset = 1
            // Nearly every beat shares its meter with the previous one; convert it once.
            var meter = ""
            var meterBytes: [UInt8] = []
            for beat in grid {
                if beat.meter != meter {
                    meter = beat.meter
                    meterBytes = Array(meter.utf8.prefix(255))
                }
                buffer.storeBytes(of: beat.start.bitPattern.littleEndian, toByteOffset: offset, as: UInt64.self)
                buffer.storeBytes(of: beat.bpm.bitPattern.littleEndian, toByteOffset: offset + 8, as: UInt64.self)
                buffer[offset + 16] = UInt8(clamping: beat.beat)
                buffer[offset + 17] = UInt8(meterBytes.count)
                offset += 18
                if !meterBytes.isEmpty {
                    UnsafeMutableRawBufferPointer(rebasing: buffer[offset ..< offset + meterBytes.count]).copyBytes(from: meterBytes)
                    offset += meterBytes.count
                }
            }
        }
        return data
    }

    static func unpack(_ data: Data) -> [RekordboxBeat]? {
        let bytes = [UInt8](data)
        guard bytes.first == self.version else { return nil }
        var grid: [RekordboxBeat] = []
        var index = 1
        while index < bytes.count {
            guard index + 18 <= bytes.count else { return nil }
            let start = Double(bitPattern: self.read(bytes, at: index))
            let bpm = Double(bitPattern: self.read(bytes, at: index + 8))
            let beat = Int(bytes[index + 16])
            let length = Int(bytes[index + 17])
            index += 18
            guard index + length <= bytes.count, let meter = String(bytes: bytes[index ..< index + length], encoding: .utf8) else {
                return nil
            }
            index += length
            grid.append(RekordboxBeat(start: start, bpm: bpm, meter: meter, beat: beat))
        }
        return grid
    }

    private static func read(_ bytes: [UInt8], at index: Int) -> UInt64 {
        (0 ..< 8).reduce(UInt64(0)) { $0 | UInt64(bytes[index + $1]) << UInt64($1 * 8) }
    }
}
