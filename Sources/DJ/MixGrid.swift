import Foundation

/// A track's rekordbox beatgrid as Automix counts it (DJ mode spec Revision 2 § Mix points). The export stores tempo
/// segments, not every beat: segment *i* starts at its `start` and has a beat every `60 / bpm` seconds until the next
/// segment. Beats are 0-based from the grid's first beat; bars are counted from the first downbeat. Pure.
struct MixGrid: Equatable, Sendable {
    private struct Segment: Equatable, Sendable {
        let start: Double
        let bpm: Double
        /// Index of the segment's first beat in the whole grid.
        let firstBeat: Int
    }

    private let segments: [Segment]
    let duration: Double
    /// 0-based index of the first beat that starts a bar.
    let firstDownbeat: Int

    init?(segments: [RekordboxBeat], duration: Double) {
        guard let first = segments.first, duration > 0, segments.allSatisfy({ $0.bpm > 0 && $0.bpm.isFinite }) else {
            return nil
        }
        var built: [Segment] = []
        var beatIndex = 0
        for (index, segment) in segments.enumerated() {
            built.append(Segment(start: segment.start, bpm: segment.bpm, firstBeat: beatIndex))
            if index + 1 < segments.count {
                beatIndex += max(1, Int(((segments[index + 1].start - segment.start) * segment.bpm / 60).rounded()))
            }
        }
        self.segments = built
        self.duration = duration
        self.firstDownbeat = (5 - min(max(first.beat, 1), 4)) % 4
    }

    func time(ofBeat index: Int) -> Double {
        let segment = self.segments.last { $0.firstBeat <= index } ?? self.segments[0]
        return segment.start + Double(index - segment.firstBeat) * 60 / segment.bpm
    }

    /// Fractional beat index at `time`.
    func beat(at time: Double) -> Double {
        let segment = self.segment(at: time)
        return Double(segment.firstBeat) + (time - segment.start) * segment.bpm / 60
    }

    func time(ofBar bar: Int) -> Double {
        self.time(ofBeat: self.firstDownbeat + 4 * bar)
    }

    /// Fractional bar at `time`.
    func bar(at time: Double) -> Double {
        (self.beat(at: time) - Double(self.firstDownbeat)) / 4
    }

    func localBPM(at time: Double) -> Double {
        self.segment(at: time).bpm
    }

    /// rekordbox phrase beats are 1-based: beat 1 is the grid's first beat.
    func phraseBeatTime(_ oneBasedBeat: Int) -> Double {
        self.time(ofBeat: oneBasedBeat - 1)
    }

    /// The last bar that ends at or before the end of the file.
    var lastFullBar: Int {
        Int(floor(self.bar(at: self.duration))) - 1
    }

    private func segment(at time: Double) -> Segment {
        self.segments.last { $0.start <= time } ?? self.segments[0]
    }
}
