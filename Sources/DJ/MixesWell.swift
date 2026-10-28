import Foundation

/// How a candidate's Camelot key sits against the reference's.
enum KeyRelation: Equatable, Sendable {
    case same, plusOne, minusOne, relative

    /// Ranking order: same, then ±1 (tied), then relative.
    var rank: Int {
        switch self {
        case .same: 0
        case .plusOne, .minusOne: 1
        case .relative: 2
        }
    }

    var tag: String {
        switch self {
        case .same: "SAME KEY"
        case .plusOne: "+1"
        case .minusOne: "−1"
        case .relative: "REL"
        }
    }
}

/// `half`: the candidate runs at half the reference tempo; `double`: at twice it.
enum TempoOctave: Equatable, Sendable {
    case normal, half, double
}

struct MixesWellMatch: Equatable, Sendable {
    let row: LibraryRow
    let key: KeyRelation
    let octave: TempoOctave
    /// The candidate's BPM (×2 for half, ÷2 for double) against the reference tempo, in percent.
    let bpmDeltaPercent: Double

    var tags: [String] {
        var tags = [self.key.tag, Self.tempoTag(self.bpmDeltaPercent)]
        switch self.octave {
        case .normal: break
        case .half: tags.append("½×")
        case .double: tags.append("2×")
        }
        if self.row.trackClass == .changing {
            tags.append("VAR")
        }
        return tags
    }

    private static func tempoTag(_ delta: Double) -> String {
        let rounded = Int(delta.rounded())
        if rounded == 0 {
            return "±0%"
        }
        return rounded > 0 ? "+\(rounded)%" : "−\(-rounded)%"
    }
}

struct MixesWellResult: Equatable, Sendable {
    let matches: [MixesWellMatch]
    /// Half- or double-tempo matches: a change of chapter, not a normal next track.
    let chapter: [MixesWellMatch]
}

/// Tracks that mix well with a reference (DJ mode spec Revision 2 § MIXES WELL), and the pick that continues a set
/// when the Playlist runs out (§ Continue with MIXES WELL). Pure: callers pass rows and the tempo to match.
enum MixesWell {
    static let tempoWindow = 0.06

    static func keyRelation(_ reference: String, _ candidate: String) -> KeyRelation? {
        guard let (number, letter) = self.parse(reference), let (other, otherLetter) = self.parse(candidate) else { return nil }
        if letter == otherLetter {
            switch (other - number + 12) % 12 {
            case 0: return .same
            case 1: return .plusOne
            case 11: return .minusOne
            default: return nil
            }
        }
        return number == other ? .relative : nil
    }

    static func matches(reference: LibraryRow, tempo: Double, rows: [LibraryRow]) -> MixesWellResult {
        guard tempo > 0, let referenceKey = reference.camelotKey else { return MixesWellResult(matches: [], chapter: []) }
        var matches: [MixesWellMatch] = []
        var chapter: [MixesWellMatch] = []
        for row in rows where row.id != reference.id && row.isAvailable && !row.isSet {
            guard let bpm = row.bpm, bpm > 0, let key = row.camelotKey.flatMap({ self.keyRelation(referenceKey, $0) }) else {
                continue
            }
            for (octave, factor) in [(TempoOctave.normal, 1.0), (.half, 2.0), (.double, 0.5)] {
                let delta = (bpm * factor - tempo) / tempo
                guard abs(delta) <= self.tempoWindow else { continue }
                let match = MixesWellMatch(row: row, key: key, octave: octave, bpmDeltaPercent: delta * 100)
                if octave == .normal {
                    matches.append(match)
                } else {
                    chapter.append(match)
                }
                break
            }
        }
        return MixesWellResult(matches: self.ranked(matches), chapter: self.ranked(chapter))
    }

    static func nextPick(reference: LibraryRow, tempo: Double, pool: [LibraryRow], excluded: Set<UUID>) -> LibraryRow? {
        let eligible = pool.filter {
            $0.id != reference.id && !excluded.contains($0.id) && $0.isAvailable
                && [.steady, .drifting].contains($0.trackClass)
        }
        if let match = self.matches(reference: reference, tempo: tempo, rows: eligible).matches.first {
            return match.row
        }
        return eligible
            .filter { ($0.bpm ?? 0) > 0 }
            .min { lhs, rhs in
                let left = abs(lhs.bpm! - tempo), right = abs(rhs.bpm! - tempo)
                return left != right ? left < right : lhs.title < rhs.title
            }
    }

    private static func ranked(_ matches: [MixesWellMatch]) -> [MixesWellMatch] {
        matches.sorted { lhs, rhs in
            if lhs.key.rank != rhs.key.rank {
                return lhs.key.rank < rhs.key.rank
            }
            if abs(lhs.bpmDeltaPercent) != abs(rhs.bpmDeltaPercent) {
                return abs(lhs.bpmDeltaPercent) < abs(rhs.bpmDeltaPercent)
            }
            return lhs.row.title < rhs.row.title
        }
    }

    /// `8A` → (8, "A"); numbers 1…12, letters A or B.
    private static func parse(_ code: String) -> (Int, Character)? {
        guard let letter = code.last, letter == "A" || letter == "B",
              let number = Int(code.dropLast()), (1 ... 12).contains(number)
        else { return nil }
        return (number, letter)
    }
}
