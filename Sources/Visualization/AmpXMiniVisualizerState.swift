import Foundation

/// Prepared, value-semantic input shared by the mini renderer and its fallback.
struct AmpXMiniVisualizerFrame: Sendable {
    var spectrum: [Float] = Array(repeating: 0, count: 32)
    var peaks: [Float] = Array(repeating: 0, count: 32)
    var trails: [Float] = Array(repeating: 0, count: 32)
    var waveform: [Float] = []
    /// PCM RMS and sample peak mapped from −72…0 dBFS into 0…1.
    var meterLevels: SIMD2<Float> = .zero
    var meterPeaks: SIMD2<Float> = .zero
    /// 128 rows of 32 frequency bands, oldest first; zero-padded during startup.
    var history: [Float] = Array(repeating: 0, count: 4096)
    var particleOpacity: Float = 0
    var elapsed: Float = 0
    var isActive: Bool = false
}

/// Pure display state. Display time drives ballistics; audio time and sequence drive history.
struct AmpXMiniVisualizerState {
    private static let activityThreshold: Float = 0.002
    private var frame = AmpXMiniVisualizerFrame()
    private var bands = Array(repeating: MiniLevelEnvelope(), count: 32)
    private var meters = Array(repeating: MiniLevelEnvelope(), count: 2)
    private var history = MiniSpectrumHistory()
    private var waveform: [Float] = []
    private var waveformPeak: Float = 0
    private var generation: UInt64?
    private var sequence: UInt64?
    private var audioTime: Double?
    private var displayTime: Double?
    private var elapsed: Double = 0
    private var wasPlaying = false

    mutating func update(_ snapshot: AmpXMiniAudioSnapshot, at time: Double) -> AmpXMiniVisualizerFrame {
        if self.generation != snapshot.generation {
            self.reset()
            self.generation = snapshot.generation
        }

        let delta = self.advanceClock(to: time)
        // Integrate the previously accepted targets before installing new ones. Giving a new
        // sample the whole preceding display interval would make attacks depend on refresh rate.
        self.advanceEnvelopes(delta: delta, isPlaying: snapshot.isPlaying && self.wasPlaying)

        if !snapshot.isPlaying {
            self.history.pause()
        }
        if snapshot.isPlaying, snapshot.time.isFinite,
           self.sequence.map({ snapshot.sequence > $0 }) ?? true,
           self.audioTime.map({ snapshot.time >= $0 }) ?? true
        {
            self.accept(snapshot)
        }

        if snapshot.isPlaying {
            self.frame.waveform = self.waveform
        } else {
            let fade = Float(exp(-12 * delta))
            for index in self.frame.waveform.indices {
                self.frame.waveform[index] *= fade
            }
        }
        self.wasPlaying = snapshot.isPlaying
        self.prepareFrame(isPlaying: snapshot.isPlaying)
        return self.frame
    }

    mutating func reset() {
        self = Self()
    }

    /// Transport notifications must reach history even while hidden views receive no frames.
    mutating func playbackDidPause() {
        self.history.pause()
        self.wasPlaying = false
    }

    private mutating func advanceClock(to time: Double) -> Double {
        guard time.isFinite else { return 0 }
        guard let previous = self.displayTime else {
            self.displayTime = time
            return 0
        }
        guard time >= previous else { return 0 }
        self.displayTime = time
        let delta = min(time - previous, Double(Float.greatestFiniteMagnitude))
        self.elapsed = min(self.elapsed + delta, Double(Float.greatestFiniteMagnitude))
        self.frame.elapsed = Float(self.elapsed)
        return delta
    }

    private mutating func accept(_ snapshot: AmpXMiniAudioSnapshot) {
        let isFirst = self.sequence == nil
        var spectrum = Array(repeating: Float(0), count: 32)
        for index in spectrum.indices where index < snapshot.spectrum.count {
            spectrum[index] = Self.clamp(snapshot.spectrum[index])
        }
        for index in self.bands.indices {
            self.bands[index].accept(level: spectrum[index], peak: spectrum[index], seed: isFirst)
        }
        for channel in self.meters.indices {
            self.meters[channel].accept(
                level: Self.meterLevel(snapshot.rms[channel]),
                peak: Self.meterLevel(snapshot.peak[channel]),
                seed: isFirst
            )
        }
        self.waveform = Self.reduceWaveform(left: snapshot.waveformLeft, right: snapshot.waveformRight)
        self.waveformPeak = self.waveform.reduce(0) { max($0, abs($1)) }
        if isFirst {
            self.frame.particleOpacity = self.waveformPeak
        }
        self.history.append(spectrum, at: snapshot.time)
        self.frame.history = self.history.values
        self.sequence = snapshot.sequence
        self.audioTime = snapshot.time
    }

    private mutating func advanceEnvelopes(delta: Double, isPlaying: Bool) {
        for index in self.bands.indices {
            // Same attack/release rates as VisualizationFeatureSmoother, integrated exactly.
            // That helper's Euler step and capped delta cannot satisfy refresh-rate invariance.
            self.bands[index].advance(delta: delta, isPlaying: isPlaying, attack: 110, release: 16)
        }
        for channel in self.meters.indices {
            // PCM RMS already averages a short window. Use a spectrum-speed attack and
            // brisk release here, so the bar body follows beats instead of slowly drifting.
            self.meters[channel].advance(delta: delta, isPlaying: isPlaying, attack: 110, release: 18)
        }
        let target = isPlaying ? self.waveformPeak : 0
        let rate: Double = target >= self.frame.particleOpacity ? 30 : 5
        self.frame.particleOpacity = Float(
            Double(target) + Double(self.frame.particleOpacity - target) * exp(-rate * delta)
        )
    }

    private mutating func prepareFrame(isPlaying: Bool) {
        for index in self.bands.indices {
            self.frame.spectrum[index] = Float(self.bands[index].level)
            self.frame.peaks[index] = Float(self.bands[index].peak)
            self.frame.trails[index] = Float(self.bands[index].trail)
        }
        for channel in self.meters.indices {
            self.frame.meterLevels[channel] = Float(self.meters[channel].level)
            self.frame.meterPeaks[channel] = Float(self.meters[channel].peak)
        }
        let visibleBands = self.bands.contains {
            max($0.level, $0.peak, $0.trail) > Double(Self.activityThreshold)
        }
        let visibleMeters = self.meters.contains {
            max($0.level, $0.peak) > Double(Self.activityThreshold)
        }
        let visibleTrace = self.frame.waveform.contains { abs($0) > Self.activityThreshold }
        self.frame.isActive = isPlaying || visibleBands || visibleMeters || visibleTrace
            || self.frame.particleOpacity > Self.activityThreshold
        if !self.frame.isActive {
            // Present an exactly empty final transient frame before the host parks. History
            // deliberately survives pause and is cleared only by reset / generation changes.
            self.frame.spectrum = Array(repeating: 0, count: 32)
            self.frame.peaks = Array(repeating: 0, count: 32)
            self.frame.trails = Array(repeating: 0, count: 32)
            self.frame.waveform = Array(repeating: 0, count: self.frame.waveform.count)
            self.frame.meterLevels = .zero
            self.frame.meterPeaks = .zero
            self.frame.particleOpacity = 0
        }
    }

    private static func clamp(_ value: Float, lower: Float = 0) -> Float {
        value.isFinite ? min(1, max(lower, value)) : 0
    }

    private static func meterLevel(_ amplitude: Float) -> Float {
        guard amplitude.isFinite, amplitude > 0 else { return 0 }
        return Float(min(1, max(0, (20 * log10(Double(amplitude)) + 72) / 72)))
    }

    /// Select one complete channel (largest absolute peak, ties left) to retain stereo
    /// transients without cancelling antiphase audio or splicing channels sample by sample.
    /// Each reduction bucket emits its two signed extrema in their original temporal order.
    private static func reduceWaveform(left: [Float], right: [Float]) -> [Float] {
        let leftPeak = left.reduce(Float(0)) { max($0, abs(Self.clamp($1, lower: -1))) }
        let rightPeak = right.reduce(Float(0)) { max($0, abs(Self.clamp($1, lower: -1))) }
        let samples = rightPeak > leftPeak ? right : left
        guard samples.count > 512 else { return samples.map { Self.clamp($0, lower: -1) } }

        var reduced: [Float] = []
        reduced.reserveCapacity(512)
        for bucket in 0 ..< 256 {
            let start = bucket * samples.count / 256
            let end = (bucket + 1) * samples.count / 256
            var minimum = Self.clamp(samples[start], lower: -1)
            var maximum = minimum
            var minimumIndex = start
            var maximumIndex = start
            for index in start + 1 ..< end {
                let sample = Self.clamp(samples[index], lower: -1)
                if sample < minimum {
                    minimum = sample
                    minimumIndex = index
                }
                if sample > maximum {
                    maximum = sample
                    maximumIndex = index
                }
            }
            reduced.append(minimumIndex <= maximumIndex ? minimum : maximum)
            reduced.append(minimumIndex <= maximumIndex ? maximum : minimum)
        }
        return reduced
    }
}

/// Continuous-time ballistics with an instantaneous peak capture, 250 ms hold, and
/// linear peak / afterglow falloff. Double storage avoids accumulating Float step error.
private struct MiniLevelEnvelope {
    var level: Double = 0
    var peak: Double = 0
    var trail: Double = 0
    private var target: Double = 0
    private var peakTarget: Double = 0
    private var hold: Double = 0

    mutating func accept(level: Float, peak: Float, seed: Bool) {
        self.target = Double(level)
        self.peakTarget = Double(peak)
        if seed {
            self.level = self.target
            self.trail = self.target
        }
        if self.peakTarget >= self.peak {
            self.peak = self.peakTarget
            self.hold = 0.25
        }
    }

    mutating func advance(delta: Double, isPlaying: Bool, attack: Double, release: Double) {
        let target = isPlaying ? self.target : 0
        let rate = target >= self.level ? attack : release
        self.level = target + (self.level - target) * exp(-rate * delta)
        self.trail = max(self.level, self.trail - 1.5 * delta)

        let peakTarget = isPlaying ? self.peakTarget : 0
        let fallingTime = max(0, delta - self.hold)
        self.hold = max(0, self.hold - delta)
        self.peak = max(peakTarget, self.peak - fallingTime * 1.2)
        if peakTarget >= self.peak {
            self.hold = 0.25
        }
    }
}

/// Fixed 32 Hz audio-time sampling: 128 rows cover four seconds at any display rate.
/// Linear interpolation between accepted snapshots keeps fixed ramps stable even when
/// 30 Hz rendering straddles a history row. Repeated sequences never reach this helper.
private struct MiniSpectrumHistory {
    private static let rowDuration = 1.0 / 32
    var values = Array(repeating: Float(0), count: 4096)
    private var rowTime: Double?
    private var needsRebase = false
    private var previousTime: Double = 0
    private var previousBands = Array(repeating: Float(0), count: 32)

    mutating func pause() {
        self.needsRebase = self.rowTime != nil
    }

    mutating func append(_ bands: [Float], at time: Double) {
        defer {
            self.previousTime = time
            self.previousBands = bands
        }
        if self.needsRebase {
            // Playout timestamps include the paused wall-clock interval. Keep every row,
            // but restart sampling/interpolation from the first accepted resume snapshot.
            // Duplicates and rejected snapshots never reach append, so cannot consume this.
            self.rowTime = time
            self.needsRebase = false
            return
        }
        guard let lastRow = self.rowTime else {
            self.values.replaceSubrange(4064 ..< 4096, with: bands)
            self.rowTime = time
            return
        }

        let duration = time - lastRow
        let rows: Int
        let newestTime: Double
        if duration >= 4 {
            // Bound work before converting to Int, including clocks near Double's limit.
            rows = 128
            let remainder = duration.isFinite ? duration.truncatingRemainder(dividingBy: Self.rowDuration) : 0
            newestTime = time - remainder
        } else {
            rows = Int(max(0, floor(duration / Self.rowDuration + 1e-8)))
            newestTime = lastRow + Double(rows) * Self.rowDuration
        }
        guard rows > 0 else { return }
        let retained = 4096 - rows * 32
        for index in 0 ..< retained {
            self.values[index] = self.values[index + rows * 32]
        }
        let sampleDuration = time - self.previousTime
        for row in 0 ..< rows {
            let sampleTime = newestTime - Double(rows - 1 - row) * Self.rowDuration
            let fraction: Float = if sampleDuration > 0, sampleDuration.isFinite {
                Float(min(1, max(0, (sampleTime - self.previousTime) / sampleDuration)))
            } else {
                1
            }
            for band in 0 ..< 32 {
                let previous = self.previousBands[band]
                self.values[retained + row * 32 + band] = previous + (bands[band] - previous) * fraction
            }
        }
        self.rowTime = newestTime
    }
}
