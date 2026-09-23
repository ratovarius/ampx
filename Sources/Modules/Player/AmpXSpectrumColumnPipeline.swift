import Foundation

/// Turns `AudioFeatureBus` spectrum bands into the Player well's column levels and peak-hold
/// levels, owning the shared smoothing and falloff state. Pure: it never touches the bus, so the
/// band mapping, smoothing and peak behavior are unit-testable without audio.
struct AmpXSpectrumColumnPipeline {
    struct Frame: Equatable {
        /// Normalized 0…1 level per column.
        var levels: [Float]
        /// Normalized 0…1 peak-hold level per column.
        var peaks: [Float]
        /// Normalized 0…1 afterglow level per column: follows `levels` up at once and falls behind.
        var trails: [Float]
        /// Normalized 0…1 level per analysis band, unfolded, for the analyzer's thin bars.
        var bandLevels: [Float]
        /// Normalized 0…1 peak-hold level per analysis band.
        var bandPeaks: [Float]
        /// False once playback stopped and both bars and afterglow decayed to visual silence.
        var isActive: Bool
    }

    /// Level below which the columns count as visually silent (develop's mini-visualizer threshold).
    static let activityThreshold: Float = 0.002

    /// Full-scale fractions the afterglow loses per second. `SpectrumPeakTracker` drops the bars
    /// linearly at 3.0/s, so the trail has to fall linearly and slower — an exponential fade fast
    /// enough to clear the well would stay behind the bar and never be seen at all.
    static let trailFalloffPerSecond: Float = 1.5

    private var smoother = VisualizationFeatureSmoother()
    private var tracker = SpectrumPeakTracker()
    private var trails = [Float](repeating: 0, count: AmpXSpectrumColumnModel.columnCount)

    /// Folds the analysis bands into the well's columns, each column showing the louder of its bands
    /// so transients survive the 32 → 16 reduction.
    static func columnLevels(fromBands bands: [Float]) -> [Float] {
        let columns = AmpXSpectrumColumnModel.columnCount
        guard columns > 0 else { return [] }
        let bandsPerColumn = max(1, AudioFeatures.spectrumBandCount / columns)

        return (0 ..< columns).map { column in
            let start = column * bandsPerColumn
            let end = min(start + bandsPerColumn, bands.count)
            guard start < end else { return 0 }
            return bands[start ..< end].max() ?? 0
        }
    }

    /// How much afterglow `deltaTime` seconds burns off. Proportional to elapsed time, so the fade
    /// takes the same wall time at any refresh rate.
    static func trailFade(deltaTime: Float) -> Float {
        self.trailFalloffPerSecond * max(0, deltaTime)
    }

    mutating func update(bands: [Float], isPlaying: Bool, deltaTime: Float) -> Frame {
        // Display-rate smoothing first, then the falloff, matching the Metal mini visualizer.
        let smoothed = self.smoother.update(targets: bands, isPlaying: isPlaying, deltaTime: deltaTime)
        let tracked = self.tracker.update(targets: smoothed, isPlaying: isPlaying, deltaTime: deltaTime)
        let levels = Self.columnLevels(fromBands: tracked.bars)
        let peaks = Self.columnLevels(fromBands: tracked.peaks)

        let fade = Self.trailFade(deltaTime: deltaTime)
        for column in 0 ..< self.trails.count {
            let level = column < levels.count ? levels[column] : 0
            self.trails[column] = max(level, self.trails[column] - fade)
        }

        // The afterglow keeps the well awake: parking while a trail is still fading would freeze it
        // mid-fade on screen.
        let visible = max(levels.max() ?? 0, self.trails.max() ?? 0)
        let isActive = isPlaying || visible > Self.activityThreshold
        return Frame(
            levels: levels,
            peaks: peaks,
            trails: self.trails,
            bandLevels: tracked.bars,
            bandPeaks: tracked.peaks,
            isActive: isActive
        )
    }
}
