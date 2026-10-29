import Foundation

/// How Automix and MIXES WELL treat a track (DJ mode spec Revision 2 § Track classes). Computed, never stored.
enum TrackClass: Equatable, Sendable {
    /// A recorded DJ set or mix: genre `Sets & Mixes`, or longer than 30 minutes.
    case set
    /// Tempo varies by at most 0.5%.
    case steady
    /// Tempo varies by more than 0.5% and at most 8%.
    case drifting
    /// Tempo varies by more than 8%.
    case changing
    /// No beatgrid.
    case noGrid

    static let setGenre = "Sets & Mixes"
    static let setMinimumDuration: Double = 1800

    static func classify(genre: String?, duration: Double, tempoSpread: Double?) -> TrackClass {
        if genre?.caseInsensitiveCompare(self.setGenre) == .orderedSame || duration > self.setMinimumDuration {
            return .set
        }
        guard let tempoSpread else { return .noGrid }
        if tempoSpread <= 0.5 {
            return .steady
        }
        return tempoSpread <= 8 ? .drifting : .changing
    }
}

extension LibraryRow {
    var trackClass: TrackClass {
        TrackClass.classify(genre: self.genre, duration: self.duration, tempoSpread: self.tempoSpread)
    }

    var isSet: Bool {
        self.trackClass == .set
    }
}
