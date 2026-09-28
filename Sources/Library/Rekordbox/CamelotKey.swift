import Foundation

/// Musical key → Camelot wheel code (rekordbox sync spec § `CamelotKey`). Minor keys are "A", major "B".
enum CamelotKey {
    /// Pitch class (C = 0) of each spelling after `♯`/`♭` are folded to `#`/`b`.
    private static let pitchClasses: [String: Int] = [
        "C": 0, "B#": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "Fb": 4, "E#": 5, "F": 5,
        "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11, "Cb": 11,
    ]

    /// Camelot number per pitch class, for minor and major keys.
    private static let minorNumbers = [5, 12, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10]
    private static let majorNumbers = [8, 3, 10, 5, 12, 7, 2, 9, 4, 11, 6, 1]

    static func from(musicalKey: String) -> String? {
        var key = musicalKey.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
        let isMinor = key.hasSuffix("m")
        if isMinor {
            key.removeLast()
        }
        guard let pitch = self.pitchClasses[key] else { return nil }
        return isMinor ? "\(self.minorNumbers[pitch])A" : "\(self.majorNumbers[pitch])B"
    }

    /// 1A = 0, 1B = 1 … 12B = 23; nil or an unknown code sorts last.
    static func sortOrder(_ camelot: String?) -> Int {
        guard let camelot, let letter = camelot.last, letter == "A" || letter == "B",
              let number = Int(camelot.dropLast()), (1 ... 12).contains(number)
        else { return Int.max }
        return (number - 1) * 2 + (letter == "A" ? 0 : 1)
    }
}
