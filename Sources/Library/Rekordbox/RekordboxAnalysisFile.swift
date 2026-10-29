import Foundation

enum RekordboxPhraseKind: UInt8, Sendable {
    case other = 0
    case intro = 1
    case outro = 2
}

struct RekordboxPhrase: Equatable, Sendable {
    /// Beat number in the track's beatgrid, counted from its first beat.
    let beat: Int
    let kind: RekordboxPhraseKind
}

struct RekordboxPhraseAnalysis: Equatable, Sendable {
    /// 1 high, 2 mid, 3 low.
    let mood: Int
    let endBeat: Int
    let phrases: [RekordboxPhrase]
}

/// Reads rekordbox's per-track analysis files (DJ mode spec Revision 2 § rekordbox phrases). The format is not
/// published by AlphaTheta; this follows the public description by Deep Symmetry. Everything is big-endian. Any
/// unexpected value yields nil, never a guess.
enum RekordboxAnalysisFile {
    private static let maskKey: [UInt8] = [
        0xCB, 0xE1, 0xEE, 0xFA, 0xE5, 0xEE, 0xAD, 0xEE, 0xE9, 0xD2, 0xE9, 0xEB, 0xE1, 0xE9, 0xF3, 0xE8, 0xE9, 0xF4, 0xE1,
    ]
    private static let packVersion: UInt8 = 1

    /// The track path in an `ANLZ0000.DAT` (`PPTH` section), NFC-normalised, trailing NULs stripped.
    static func trackPath(dat: Data) -> String? {
        let bytes = [UInt8](dat)
        guard let section = self.section("PPTH", in: bytes), section.count >= 16 else { return nil }
        let length = Int(self.u32(section[...], 12))
        guard length > 0, length.isMultiple(of: 2), 16 + length <= section.count,
              let path = String(bytes: section[16 ..< 16 + length], encoding: .utf16BigEndian)
        else { return nil }
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "\u{0}"))
        return trimmed.isEmpty ? nil : trimmed.precomposedStringWithCanonicalMapping
    }

    /// The analysed file's name. rekordbox stores only `?/` plus the name in `PPTH`, never the folder.
    static func fileName(dat: Data) -> String? {
        self.trackPath(dat: dat).map { ($0 as NSString).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The first beat of the beatgrid in an `ANLZ0000.DAT` (`PQTZ`): time in seconds, BPM and beat number.
    static func firstBeat(dat: Data) -> RekordboxBeat? {
        let bytes = [UInt8](dat)
        guard let section = self.section("PQTZ", in: bytes), section.count >= 32, self.u32(section[...], 20) > 0 else { return nil }
        return RekordboxBeat(
            start: Double(self.u32(section[...], 28)) / 1000,
            bpm: Double(self.u16(section, 26)) / 100,
            meter: "",
            beat: Int(self.u16(section, 24))
        )
    }

    /// The phrase analysis in an `ANLZ0000.EXT` (`PSSI` section), unmasked when rekordbox masked it.
    static func phrases(ext: Data) -> RekordboxPhraseAnalysis? {
        let bytes = [UInt8](ext)
        guard let section = self.section("PSSI", in: bytes), section.count >= 12 + 20 else { return nil }
        var body = Array(section.dropFirst(12))
        let count = Int(self.u16(body, 4))
        guard count > 0, 20 + count * 24 <= body.count else { return nil }
        if self.u16(body, 6) > 20 {
            for index in 6 ..< body.count {
                body[index] ^= UInt8((Int(self.maskKey[(index - 6) % 19]) + count) & 0xFF)
            }
        }
        let mood = Int(self.u16(body, 6))
        guard (1 ... 3).contains(mood) else { return nil }
        let outroKind = mood == 1 ? 6 : 10
        let phrases = (0 ..< count).map { entry -> RekordboxPhrase in
            let offset = 20 + entry * 24
            let kind = Int(self.u16(body, offset + 4))
            return RekordboxPhrase(
                beat: Int(self.u16(body, offset + 2)),
                kind: kind == 1 ? .intro : kind == outroKind ? .outro : .other
            )
        }
        return RekordboxPhraseAnalysis(mood: mood, endBeat: Int(self.u16(body, 14)), phrases: phrases)
    }

    /// `LibraryTrack.phrases`: version byte, UInt8 mood, UInt16 LE end beat, then per phrase UInt16 LE beat and UInt8 kind.
    static func pack(_ analysis: RekordboxPhraseAnalysis) -> Data {
        var bytes: [UInt8] = [self.packVersion, UInt8(clamping: analysis.mood)]
        bytes += self.le16(analysis.endBeat)
        for phrase in analysis.phrases {
            bytes += self.le16(phrase.beat)
            bytes.append(phrase.kind.rawValue)
        }
        return Data(bytes)
    }

    static func unpack(_ data: Data) -> RekordboxPhraseAnalysis? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == self.packVersion, (bytes.count - 4).isMultiple(of: 3) else { return nil }
        var phrases: [RekordboxPhrase] = []
        for offset in stride(from: 4, to: bytes.count, by: 3) {
            guard let kind = RekordboxPhraseKind(rawValue: bytes[offset + 2]) else { return nil }
            phrases.append(RekordboxPhrase(beat: Int(bytes[offset]) | Int(bytes[offset + 1]) << 8, kind: kind))
        }
        return RekordboxPhraseAnalysis(mood: Int(bytes[1]), endBeat: Int(bytes[2]) | Int(bytes[3]) << 8, phrases: phrases)
    }

    // MARK: - Bytes

    /// The first section with `code`, as its bytes from the section start (indexed from 0). Sections follow the file header, whose
    /// length is at bytes 4–7; each has a 4-byte code, a header length and a total length.
    private static func section(_ code: String, in bytes: [UInt8]) -> [UInt8]? {
        guard bytes.count >= 12 else { return nil }
        let wanted = Array(code.utf8)
        var offset = Int(self.u32(bytes[...], 4))
        while offset + 12 <= bytes.count {
            let total = Int(self.u32(bytes[...], offset + 8))
            guard total >= 12, offset + total <= bytes.count else { return nil }
            if Array(bytes[offset ..< offset + 4]) == wanted {
                return Array(bytes[offset ..< offset + total])
            }
            offset += total
        }
        return nil
    }

    private static func u16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    /// Reads relative to the slice's start.
    private static func u32(_ bytes: ArraySlice<UInt8>, _ offset: Int) -> UInt32 {
        let base = bytes.startIndex + offset
        return (0 ..< 4).reduce(UInt32(0)) { $0 << 8 | UInt32(bytes[base + $1]) }
    }

    private static func le16(_ value: Int) -> [UInt8] {
        let clamped = UInt16(clamping: value)
        return [UInt8(clamped & 0xFF), UInt8(clamped >> 8)]
    }
}
