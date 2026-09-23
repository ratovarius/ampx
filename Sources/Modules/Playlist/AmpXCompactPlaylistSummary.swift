import AppKit

struct AmpXCompactPlaylistSummary: Equatable {
    let title: String
    let duration: String

    static func make(loadedTrack: Track?, tracks: [Track], loadedDuration: TimeInterval) -> Self {
        guard let track = loadedTrack else { return Self(title: "NO TRACK", duration: "--:--") }
        let prefix = tracks.firstIndex(where: { $0.id == track.id }).map { "\($0 + 1). " } ?? ""
        let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let time = Self.validDuration(loadedDuration) ? loadedDuration : track.duration
        let duration: String
        if Self.validDuration(time) {
            let seconds = Int(time)
            duration = seconds >= 3600
                ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
                : String(format: "%d:%02d", seconds / 60, seconds % 60)
        } else {
            duration = "--:--"
        }
        return Self(
            title: "\(prefix)\(artist.isEmpty ? "Unknown Artist" : artist) - \(title.isEmpty ? "Unknown Title" : title)",
            duration: duration
        )
    }

    private static func validDuration(_ time: TimeInterval) -> Bool {
        time.isFinite && time > 0 && time < Double(Int32.max)
    }

    static func textRects(in rect: CGRect, durationWidth: CGFloat) -> (title: CGRect, duration: CGRect) {
        let width = min(rect.width, max(0, durationWidth))
        return (
            CGRect(x: rect.minX, y: rect.minY, width: max(0, rect.width - width - 8), height: rect.height),
            CGRect(x: rect.maxX - width, y: rect.minY, width: width, height: rect.height)
        )
    }
}
