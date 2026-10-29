import Foundation

/// Builds minimal rekordbox ANLZ files for tests, following the layout `RekordboxAnalysisFile` decodes.
enum ANLZTestData {
    static let maskKey: [UInt8] = [
        0xCB, 0xE1, 0xEE, 0xFA, 0xE5, 0xEE, 0xAD, 0xEE, 0xE9, 0xD2, 0xE9, 0xEB, 0xE1, 0xE9, 0xF3, 0xE8, 0xE9, 0xF4, 0xE1,
    ]

    /// rekordbox writes `?/` plus the file name as the path. `firstBeat` is `(seconds, bpm, beat number)` of the
    /// beatgrid's first beat (`PQTZ`); nil leaves the grid out.
    static func dat(path: String, firstBeat: (Double, Double, Int)? = (0.2, 128, 1)) -> Data {
        var pathBytes: [UInt8] = []
        for unit in (path + "\u{0}").utf16 {
            pathBytes += [UInt8(unit >> 8), UInt8(unit & 0xFF)]
        }
        var sections = [self.section("PPTH", headerLength: 16, body: Self.u32Bytes(UInt32(pathBytes.count)) + pathBytes)]
        if let (seconds, bpm, beat) = firstBeat {
            var grid = Self.u32Bytes(0) + Self.u32Bytes(0x80000) + Self.u32Bytes(2)
            for index in 0 ..< 2 {
                let time = UInt32(((seconds + Double(index) * 60 / bpm) * 1000).rounded())
                grid += Self.u16Bytes(UInt16((beat + index - 1) % 4 + 1)) + Self.u16Bytes(UInt16((bpm * 100).rounded()))
                grid += Self.u32Bytes(time)
            }
            sections.append(self.section("PQTZ", headerLength: 24, body: grid))
        }
        return self.file(sections)
    }

    /// `entries` are `(beat, kind)` pairs; `count` overrides the stored entry count (to corrupt it).
    static func ext(mood: Int, endBeat: Int, entries: [(Int, Int)], masked: Bool, count: Int? = nil) -> Data {
        let stored = UInt16(count ?? entries.count)
        var body = Self.u32Bytes(24) + Self.u16Bytes(stored) + Self.u16Bytes(UInt16(mood))
        body += [UInt8](repeating: 0, count: 6) + Self.u16Bytes(UInt16(endBeat)) + [UInt8](repeating: 0, count: 4)
        for (index, (beat, kind)) in entries.enumerated() {
            body += Self.u16Bytes(UInt16(index + 1)) + Self.u16Bytes(UInt16(beat)) + Self.u16Bytes(UInt16(kind))
            body += [UInt8](repeating: 0, count: 18)
        }
        if masked {
            for index in 6 ..< body.count {
                body[index] ^= UInt8((Int(self.maskKey[(index - 6) % 19]) + Int(stored)) & 0xFF)
            }
        }
        return self.file([self.section("PCOB", headerLength: 12, body: [0, 0, 0, 0]), self.section("PSSI", headerLength: 32, body: body)])
    }

    static func file(_ sections: [[UInt8]]) -> Data {
        let headerLength = 28
        let total = headerLength + sections.reduce(0) { $0 + $1.count }
        var bytes = Array("PMAI".utf8) + Self.u32Bytes(UInt32(headerLength)) + Self.u32Bytes(UInt32(total))
        bytes += [UInt8](repeating: 0, count: headerLength - bytes.count)
        for section in sections {
            bytes += section
        }
        return Data(bytes)
    }

    /// A section: code, header length, total length, then `body` from section offset 12.
    static func section(_ code: String, headerLength: Int, body: [UInt8]) -> [UInt8] {
        Array(code.utf8) + Self.u32Bytes(UInt32(headerLength)) + Self.u32Bytes(UInt32(12 + body.count)) + body
    }

    static func u16Bytes(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }

    static func u32Bytes(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }
}
