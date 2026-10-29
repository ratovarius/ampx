import Foundation

/// What Automix knows about one track: its length, class, grid and rekordbox phrases.
struct AutomixTrack: Equatable, Sendable {
    let duration: Double
    let trackClass: TrackClass
    let grid: MixGrid?
    let phrases: RekordboxPhraseAnalysis?

    /// A track outside the library, or without data: always a plain crossfade.
    static func unknown(duration: Double) -> AutomixTrack {
        AutomixTrack(duration: duration, trackClass: .noGrid, grid: nil, phrases: nil)
    }
}

/// One transition from the live track A to the next track B. Times are file seconds of the track they belong to.
struct MixPlan: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case beatmatched(rate: Double, transition: TransitionStyle)
        /// Equal-power, no tempo change.
        case crossfade
    }

    let kind: Kind
    /// Where A starts mixing out.
    let outgoingStart: Double
    /// Where B starts playing.
    let incomingStart: Double
    /// Blend length in A's file seconds.
    let length: Double
    /// 0 for a crossfade.
    let blendBars: Int
    /// Bass Swap's cut switch, and the transport switch: the bar nearest the blend's midpoint (the midpoint for a
    /// crossfade).
    let switchTime: Double
}

/// Chooses a transition's mix points (DJ mode spec Revision 2 § Mix points, § Tempo and the edge-case table). Pure.
enum MixPoints {
    static let crossfadeLength = 6.0
    static let phraseBars = 16
    /// A transition with less than this left is dropped: the Playlist advances normally.
    static let minimumLength = 1.0

    /// A's content end: rekordbox's phrase end beat, else the end of the grid's last full bar, else the file's end.
    static func contentEnd(_ a: AutomixTrack) -> Double {
        guard let grid = a.grid else { return a.duration }
        if let phrases = a.phrases {
            return min(grid.phraseBeatTime(phrases.endBeat), a.duration)
        }
        return min(grid.time(ofBar: grid.lastFullBar + 1), a.duration)
    }

    static func plan(
        outgoing a: AutomixTrack,
        incoming b: AutomixTrack,
        outgoingRate: Double,
        outgoingPosition: Double,
        settings: AutomixSettings
    ) -> MixPlan? {
        let planned = self.beatmatched(a, b, outgoingRate: outgoingRate, settings: settings) ?? self.crossfade(a, from: nil)
        guard let planned, outgoingPosition > planned.outgoingStart else { return planned }
        return self.crossfade(a, from: outgoingPosition)
    }

    // MARK: - Beatmatched

    private static func beatmatched(_ a: AutomixTrack, _ b: AutomixTrack, outgoingRate: Double, settings: AutomixSettings) -> MixPlan? {
        let mixable: Set<TrackClass> = [.steady, .drifting]
        guard mixable.contains(a.trackClass), mixable.contains(b.trackClass), let gridA = a.grid, let gridB = b.grid else { return nil }
        let endBar = Int(floor(gridA.bar(at: self.contentEnd(a)) + 1e-9))
        // Octave transitions use Last Phrase: B's intro is counted in B's bars, which are not A's.
        let octave = TempoPlan.octaveFactor(
            incoming: gridB.localBPM(at: gridB.time(ofBar: 0)),
            outgoing: gridA.localBPM(at: 0) * outgoingRate
        )
        var points = settings.mixPoints == .introOutro && octave == 1
            ? self.introOutro(a, b, gridA: gridA, gridB: gridB, endBar: endBar, longest: settings.longestBlendBars)
            : nil
        if points == nil {
            points = self.lastPhrase(endBar: endBar, blend: settings.lastPhraseBlendBars)
        }
        guard var (outBar, inBar, blend) = points else { return nil }

        // B shorter than the blend: a third of B's playing time, in A's bars.
        let aBarSeconds = 240 / (gridA.localBPM(at: gridA.time(ofBar: outBar)) * outgoingRate)
        let incomingRemaining = b.duration - max(0, gridB.time(ofBar: inBar))
        if Double(blend) * aBarSeconds > incomingRemaining {
            blend = self.roundedDown(Int(incomingRemaining / aBarSeconds) / 3)
            guard blend >= 4 else { return nil }
            if inBar == 0 {
                guard let shortened = self.lastPhrase(endBar: endBar, blend: blend) else { return nil }
                outBar = shortened.outBar
            } else {
                outBar = endBar - blend
                inBar = max(0, inBar)
            }
        }

        let outgoingStart = gridA.time(ofBar: outBar)
        let incomingStart = max(0, gridB.time(ofBar: inBar))
        guard let rate = TempoPlan.matchRate(
            outgoingEffectiveBPM: gridA.localBPM(at: outgoingStart) * outgoingRate,
            incomingLocalBPM: gridB.localBPM(at: incomingStart)
        ) else { return nil }
        return MixPlan(
            kind: .beatmatched(rate: rate, transition: settings.transition),
            outgoingStart: outgoingStart,
            incomingStart: incomingStart,
            length: gridA.time(ofBar: outBar + blend) - outgoingStart,
            blendBars: blend,
            switchTime: gridA.time(ofBar: outBar + blend / 2)
        )
    }

    /// The last 16-bar boundary from which the whole blend fits before A's content end; B comes in at its bar 0.
    private static func lastPhrase(endBar: Int, blend: Int) -> (outBar: Int, inBar: Int, blend: Int)? {
        guard blend > 0, endBar >= blend else { return nil }
        return ((endBar - blend) / self.phraseBars * self.phraseBars, 0, blend)
    }

    /// B's intro over A's outro, so B's main part arrives as A's content ends. Nil without phrases on both sides or
    /// under 4 bars.
    private static func introOutro(
        _ a: AutomixTrack,
        _ b: AutomixTrack,
        gridA: MixGrid,
        gridB: MixGrid,
        endBar: Int,
        longest: Int
    ) -> (outBar: Int, inBar: Int, blend: Int)? {
        guard let phrasesA = a.phrases, let phrasesB = b.phrases else { return nil }
        let sortedB = phrasesB.phrases.sorted { $0.beat < $1.beat }
        let leadingIntros = sortedB.prefix { $0.kind == .intro }
        guard !leadingIntros.isEmpty else { return nil }
        let introEndBeat = sortedB.dropFirst(leadingIntros.count).first?.beat ?? phrasesB.endBeat
        let intro = Int(floor(gridB.bar(at: gridB.phraseBeatTime(introEndBeat)) + 1e-9))

        let sortedA = phrasesA.phrases.sorted { $0.beat < $1.beat }
        guard let outroStart = sortedA.reversed().prefix(while: { $0.kind == .outro }).last else { return nil }
        let outro = endBar - Int(ceil(gridA.bar(at: gridA.phraseBeatTime(outroStart.beat)) - 1e-9))

        let blend = self.roundedDown(min(intro, outro, longest))
        guard blend >= 4 else { return nil }
        return (endBar - blend, intro - blend, blend)
    }

    private static func roundedDown(_ bars: Int) -> Int {
        max(0, bars) / 4 * 4
    }

    // MARK: - Crossfade

    /// A plain crossfade ending at A's content end: 6 s, or from `position` when that is later. Nil under 1 s.
    private static func crossfade(_ a: AutomixTrack, from position: Double?) -> MixPlan? {
        let end = self.contentEnd(a)
        let start = max(end - self.crossfadeLength, position ?? 0, 0)
        let length = end - start
        guard length >= self.minimumLength else { return nil }
        return MixPlan(
            kind: .crossfade,
            outgoingStart: start,
            incomingStart: 0,
            length: length,
            blendBars: 0,
            switchTime: start + length / 2
        )
    }
}
