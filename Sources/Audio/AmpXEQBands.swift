import CoreGraphics
import Foundation

/// Classic Winamp 2.x 10-band EQ — single source of truth for UI labels and `AVAudioUnitEQ` setup.
enum AmpXEQBands {
    static let bandCount = 10

    /// Center frequencies (Hz) used by the audio engine (`AVAudioUnitEQ`).
    static let centerFrequenciesHz: [Float] = [60, 170, 310, 600, 1000, 3000, 6000, 12000, 14000, 16000]

    /// Labels shown under each band slider (matches classic Winamp).
    static let displayLabels: [String] = ["60", "170", "310", "600", "1K", "3K", "6K", "12K", "14K", "16K"]

    /// Per-band filter bandwidth in octaves for `AVAudioUnitEQ` parametric bands.
    ///
    /// A fixed 1-octave bandwidth makes the closely-spaced top bands (12k/14k/16k, which sit
    /// less than ¼ octave apart) overlap heavily — boosting all three stacks far past +12 dB and
    /// produces a lumpy response. We instead derive each band's bandwidth from the spacing to its
    /// neighbours (the average octave gap on each side), so adjacent filters meet near their −3 dB
    /// points and the summed response tracks the curve the UI draws.
    static let bandwidthsOctaves: [Float] = {
        let freqs = centerFrequenciesHz
        func octaveGap(_ a: Float, _ b: Float) -> Float {
            abs(log2(b / a))
        }
        return freqs.indices.map { index in
            let leftGap = index > 0 ? octaveGap(freqs[index - 1], freqs[index]) : nil
            let rightGap = index < freqs.count - 1 ? octaveGap(freqs[index], freqs[index + 1]) : nil
            let gaps = [leftGap, rightGap].compactMap { $0 }
            let mean = gaps.reduce(0, +) / Float(gaps.count)
            // AVAudioUnitEQ accepts 0.05…5.0 octaves.
            return min(max(mean, 0.05), 5.0)
        }
    }()

    /// Horizontal position (0…1) of each band within the 10-band slider row (even spacing, like Winamp).
    static func bandCenterX(bandIndex: Int, width: CGFloat) -> CGFloat {
        let index = CGFloat(bandIndex)
        return (index + 0.5) / CGFloat(self.bandCount) * width
    }

    /// Curve height for a normalized −1…1 gain in a graph of `height`, top-left origin: boost
    /// above the center line, cut below, with a small margin at the extremes.
    static func curveY(forNormalizedGain gain: Float, height: CGFloat) -> CGFloat {
        let midY = height / 2
        let clamped = CGFloat(max(-1, min(1, gain)))
        return midY - clamped * midY * 0.85
    }

    /// One curve knot per band, at the band's slider value. Preamp is not folded in: the
    /// graph draws it as its own line, so each knot mirrors exactly one slider.
    static func responseCurvePoints(bandValues: [Float], width: CGFloat, height: CGFloat) -> [CGPoint] {
        (0 ..< min(bandValues.count, self.bandCount)).map { index in
            CGPoint(
                x: self.bandCenterX(bandIndex: index, width: width),
                y: self.curveY(forNormalizedGain: bandValues[index], height: height)
            )
        }
    }
}
