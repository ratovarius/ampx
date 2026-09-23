import AVFoundation
import Foundation

/// One energy section from offline analysis (`{t, energy}` in ENTHEA's `S.timeline`).
struct EntheaTimelineSection: Sendable, Equatable, Codable {
    /// Section start time in seconds.
    var t: Double
    /// `0` = low energy, `1` = high energy (mirrors upstream).
    var energy: Int
}

/// Native mirror of ENTHEA's `analyzeTrack()` result assigned to `S.timeline`.
struct EntheaTimeline: Sendable, Equatable, Codable {
    var dur: Double
    var drops: [Double]
    var sections: [EntheaTimelineSection]
    var fps: Double

    /// Encode for `winampAudio.setTimeline(...)` (runtime pointer fields added in JS).
    func jsonObjectString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        let data = try encoder.encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw EntheaTrackAnalyzerError.encodingFailed
        }
        return string
    }
}

enum EntheaTrackAnalyzerError: Error {
    case cannotOpenFile
    case emptyFile
    case encodingFailed
}

/// Offline onset/section heuristic ported from ENTHEA's `analyzeTrack()` (vendored `index.html`).
/// Runs on a background executor — never call from the main actor for long files.
enum EntheaTrackAnalyzer {
    /// Analyze a local audio file. Throws if the file cannot be opened.
    static func analyze(url: URL) throws -> EntheaTimeline {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0 else { throw EntheaTrackAnalyzerError.emptyFile }

        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else {
            throw EntheaTrackAnalyzerError.cannotOpenFile
        }

        let channelCount = Int(format.channelCount)
        let sampleCount = Int(buffer.frameLength)
        let sampleRate = format.sampleRate
        var mono = [Float](repeating: 0, count: sampleCount)
        if channelCount >= 2 {
            let left = UnsafeBufferPointer(start: channels[0], count: sampleCount)
            let right = UnsafeBufferPointer(start: channels[1], count: sampleCount)
            for i in 0 ..< sampleCount {
                mono[i] = (left[i] + right[i]) * 0.5
            }
        } else {
            mono = Array(UnsafeBufferPointer(start: channels[0], count: sampleCount))
        }

        return Self.analyzeMono(samples: mono, sampleRate: sampleRate)
    }

    /// Core heuristic — exposed for fixture tests that synthesize mono PCM in memory.
    static func analyzeMono(samples: [Float], sampleRate: Double) -> EntheaTimeline {
        let n = samples.count
        guard n > 0, sampleRate > 0 else {
            return EntheaTimeline(dur: 0, drops: [], sections: [], fps: 0)
        }

        let hop = max(256, Int(floor(sampleRate * 0.023)))
        let frames = n / hop
        guard frames > 4 else {
            return EntheaTimeline(dur: Double(n) / sampleRate, drops: [], sections: [
                EntheaTimelineSection(t: 0, energy: 0),
            ], fps: sampleRate / Double(hop))
        }
        let fps = sampleRate / Double(hop)

        // One-pole split @160 Hz (same as upstream).
        let a1 = Float(1 - exp(-2 * Double.pi * 160 / sampleRate))
        var lp: Float = 0
        var level = [Float](repeating: 0, count: frames)
        var bass = [Float](repeating: 0, count: frames)
        var high = [Float](repeating: 0, count: frames)

        for f in 0 ..< frames {
            let s0 = f * hop
            let s1 = min(n, s0 + hop)
            var acc: Float = 0
            var accB: Float = 0
            var accH: Float = 0
            for i in s0 ..< s1 {
                let x = samples[i]
                lp += a1 * (x - lp)
                let hi = x - lp
                acc += x * x
                accB += lp * lp
                accH += hi * hi
            }
            let c = Float(max(1, s1 - s0))
            level[f] = sqrt(acc / c)
            bass[f] = sqrt(accB / c)
            high[f] = sqrt(accH / c)
        }

        Self.normalizeInPlace(&level)
        Self.normalizeInPlace(&bass)
        Self.normalizeInPlace(&high)

        let lvlS = Self.smooth(level, window: max(1, Int(round(fps * 0.12))))
        let lvlSlow = Self.smooth(level, window: max(1, Int(round(fps * 1.5))))

        let jK = max(1, Int(round(fps * 0.18)))
        let dipW = Int(round(fps * 1.8))
        var score = [Float](repeating: 0, count: frames)
        for f in (jK + 1) ..< frames {
            let jump = lvlS[f] - lvlS[f - jK]
            var mn: Float = 1
            let dipStart = max(0, f - dipW)
            for j in dipStart ..< f {
                if lvlS[j] < mn {
                    mn = lvlS[j]
                }
            }
            let dip = lvlS[f] - mn
            score[f] = max(0, jump) * bass[f]
                * (0.35 + 0.65 * min(1, dip * 1.6))
                * min(1, lvlS[f] * 1.4)
        }

        var mx: Float = 0
        for v in score where v > mx {
            mx = v
        }
        let thr = max(Float(0.03), mx * 0.34)
        let refr = Int(round(fps * 4))
        var drops: [Double] = []
        var last = Int.min / 4
        if frames > 4 {
            for f in 2 ..< (frames - 2) {
                if score[f] > thr,
                   score[f] >= score[f - 1],
                   score[f] > score[f + 1],
                   (f - last) > refr
                {
                    drops.append(max(0, (Double(f) - 0.5) / fps))
                    last = f
                }
            }
        }

        var sections: [EntheaTimelineSection] = []
        let hiThr: Float = 0.46
        var cur = lvlSlow[0] > hiThr ? 1 : 0
        var seg = 0
        let minSeg = Int(fps * 4)
        for f in 1 ..< frames {
            let st = lvlSlow[f] > hiThr ? 1 : 0
            if st != cur, (f - seg) > minSeg {
                sections.append(EntheaTimelineSection(t: Double(seg) / fps, energy: cur))
                seg = f
                cur = st
            }
        }
        sections.append(EntheaTimelineSection(t: Double(seg) / fps, energy: cur))

        return EntheaTimeline(
            dur: Double(n) / sampleRate,
            drops: drops,
            sections: sections,
            fps: fps
        )
    }

    private static func normalizeInPlace(_ a: inout [Float]) {
        var m: Float = 1e-6
        for v in a where v > m {
            m = v
        }
        guard m > 0 else { return }
        for i in a.indices {
            a[i] /= m
        }
    }

    private static func smooth(_ a: [Float], window w: Int) -> [Float] {
        var o = [Float](repeating: 0, count: a.count)
        for i in a.indices {
            var s: Float = 0
            var c: Float = 0
            for k in -w ... w {
                let j = i + k
                if j >= 0, j < a.count {
                    s += a[j]
                    c += 1
                }
            }
            o[i] = s / c
        }
        return o
    }
}
