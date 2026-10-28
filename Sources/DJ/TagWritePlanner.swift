import CryptoKit
import Foundation

/// A library row as the tag writer sees it: where the file is, the rekordbox values, and the record of what was
/// last written.
struct TagWriteRow: Sendable, Equatable {
    let rowID: UUID
    let rootID: UUID
    let url: URL
    let bpm: Double?
    let musicalKey, label, remixer, composer, grouping: String?
    let tagsWrittenHash: Data?
}

struct TagWriteDecision: Equatable, Sendable {
    /// Fields to write, with their new values.
    let changes: [TagField: String]
    /// The file's BPM tag is half or double rekordbox's: BPM is left out and the track is listed for checking.
    let halfDouble: Bool
}

/// Which rekordbox values go into a file's tags (DJ mode spec Revision 2 § Tag writing). Pure.
enum TagWritePlanner {
    /// How close the file's BPM must be to half or double rekordbox's to count as an octave disagreement.
    static let halfDoubleTolerance = 0.01

    /// The values AmpX wants in the file: BPM rounded to an integer (ID3 `TBPM` and MP4 `tmpo` are integers), the
    /// key as rekordbox spells it, and the text fields. Empty values are left out, so they never clear a tag.
    static func desired(_ row: TagWriteRow) -> [TagField: String] {
        var fields: [TagField: String] = [:]
        if let bpm = row.bpm, bpm > 0 {
            fields[.bpm] = String(Int(bpm.rounded()))
        }
        let texts: [(TagField, String?)] = [
            (.key, row.musicalKey), (.label, row.label), (.remixer, row.remixer), (.composer, row.composer), (.grouping, row.grouping),
        ]
        for (field, value) in texts {
            if let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                fields[field] = value
            }
        }
        return fields
    }

    /// SHA-256 of `field=value` lines sorted by field.
    static func hash(_ desired: [TagField: String]) -> Data {
        let text = desired.map { "\($0.key.rawValue)=\($0.value)\n" }.sorted().joined()
        return Data(SHA256.hash(data: Data(text.utf8)))
    }

    static func isDue(_ row: TagWriteRow) -> Bool {
        self.hash(self.desired(row)) != row.tagsWrittenHash
    }

    /// Compares the desired values with what the file holds now.
    static func decide(_ row: TagWriteRow, file: [TagField: String]) -> TagWriteDecision {
        var changes: [TagField: String] = [:]
        var halfDouble = false
        for (field, value) in self.desired(row) {
            let current = file[field]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if field == .bpm {
                let fileBPM = Double(current)
                if let fileBPM, let bpm = row.bpm, self.isHalfOrDouble(fileBPM, of: bpm) {
                    halfDouble = true
                    continue
                }
                if let fileBPM, Int(fileBPM.rounded()) == Int(value) {
                    continue
                }
            } else if current == value {
                continue
            }
            changes[field] = value
        }
        return TagWriteDecision(changes: changes, halfDouble: halfDouble)
    }

    private static func isHalfOrDouble(_ fileBPM: Double, of bpm: Double) -> Bool {
        guard fileBPM > 0, bpm > 0 else { return false }
        let ratio = fileBPM / bpm
        return abs(ratio / 0.5 - 1) <= self.halfDoubleTolerance || abs(ratio / 2 - 1) <= self.halfDoubleTolerance
    }
}
