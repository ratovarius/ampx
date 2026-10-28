import Foundation

/// One `<TEMPO>` element of a rekordbox beatgrid.
struct RekordboxBeat: Codable, Equatable, Sendable {
    let start: Double
    let bpm: Double
    let meter: String
    let beat: Int
}

/// One `POSITION_MARK` of a track: a hot cue (`number` 0–7) or a memory cue (−1); `type` 0 is a cue, 4 a loop.
struct RekordboxCue: Equatable, Sendable {
    let number: Int
    let type: Int
    let start: Double
    let end: Double?
    let name: String
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
    var cues: [RekordboxCue] = []
}

struct RekordboxCollection: Equatable, Sendable {
    let productVersion: String?
    let tracks: [RekordboxTrack]
    let droppedWithoutLocation: Int
}

/// Compact storage for cues (`LibraryTrack.cues`). Layout: version byte `1`, then per cue: Int8 number, UInt8 type,
/// start as a little-endian Float64 bit pattern, UInt8 has-end flag, end (0 when absent), UInt8 name length plus UTF-8.
enum RekordboxCues {
    private static let version: UInt8 = 1

    static func pack(_ cues: [RekordboxCue]) -> Data {
        var bytes: [UInt8] = [self.version]
        for cue in cues {
            bytes.append(UInt8(bitPattern: Int8(clamping: cue.number)))
            bytes.append(UInt8(clamping: cue.type))
            self.append(cue.start, to: &bytes)
            bytes.append(cue.end == nil ? 0 : 1)
            self.append(cue.end ?? 0, to: &bytes)
            let name = Array(cue.name.utf8.prefix(255))
            bytes.append(UInt8(name.count))
            bytes.append(contentsOf: name)
        }
        return Data(bytes)
    }

    static func unpack(_ data: Data) -> [RekordboxCue]? {
        let bytes = [UInt8](data)
        guard bytes.first == self.version else { return nil }
        var cues: [RekordboxCue] = []
        var index = 1
        while index < bytes.count {
            guard index + 20 <= bytes.count else { return nil }
            let number = Int(Int8(bitPattern: bytes[index]))
            let type = Int(bytes[index + 1])
            let start = self.read(bytes, at: index + 2)
            let hasEnd = bytes[index + 10] != 0
            let end = self.read(bytes, at: index + 11)
            let length = Int(bytes[index + 19])
            index += 20
            guard index + length <= bytes.count, let name = String(bytes: bytes[index ..< index + length], encoding: .utf8) else {
                return nil
            }
            index += length
            cues.append(RekordboxCue(number: number, type: type, start: start, end: hasEnd ? end : nil, name: name))
        }
        return cues
    }

    private static func append(_ value: Double, to bytes: inout [UInt8]) {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { bytes.append(contentsOf: $0) }
    }

    private static func read(_ bytes: [UInt8], at index: Int) -> Double {
        Double(bitPattern: (0 ..< 8).reduce(UInt64(0)) { $0 | UInt64(bytes[index + $1]) << UInt64($1 * 8) })
    }
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

    /// `(max − min) / median` of the grid's BPMs, in percent; nil for an empty grid (DJ mode spec § Track classes).
    static func tempoSpread(_ grid: [RekordboxBeat]) -> Double? {
        guard !grid.isEmpty else { return nil }
        let bpms = grid.map(\.bpm).sorted()
        let middle = bpms.count / 2
        let median = bpms.count.isMultiple(of: 2) ? (bpms[middle - 1] + bpms[middle]) / 2 : bpms[middle]
        guard median > 0 else { return nil }
        return (bpms[bpms.count - 1] - bpms[0]) / median * 100
    }

    private static func read(_ bytes: [UInt8], at index: Int) -> UInt64 {
        (0 ..< 8).reduce(UInt64(0)) { $0 | UInt64(bytes[index + $1]) << UInt64($1 * 8) }
    }
}
