import AVFoundation
import Foundation
import os

/// One serial analysis producer, any number of snapshot readers. Expensive PCM work occurs
/// outside the publication lock; reset invalidates in-progress work before it can publish.
final class AmpXMiniAudioTimeline: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var frames: [AmpXMiniAudioSnapshot] = []
    private var epoch: UInt64 = 0
    private var visualGeneration: UInt64 = 0
    private var sequence: UInt64 = 0

    // Analysis-queue-owned lookbehind, bounded to the 20 ms signal window.
    private var retainedLeft: [Float] = []
    private var retainedRight: [Float] = []
    private var retainedRate: Double = 0
    private var retainedEpoch: UInt64 = .max

    @discardableResult
    func reset() -> UInt64 {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.epoch = max(self.epoch, self.visualGeneration) &+ 1
        self.visualGeneration = self.epoch
        self.frames.removeAll(keepingCapacity: true)
        return self.epoch
    }

    func snapshot(at time: Double) -> AmpXMiniAudioSnapshot {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard !self.frames.isEmpty else {
            return AmpXMiniAudioSnapshot(generation: self.visualGeneration)
        }
        let index = self.frames.lastIndex(where: { $0.time <= time }) ?? 0
        return self.frames[index]
    }

    func publish(
        pcm: AVAudioPCMBuffer, spectrumFrames: [[Float]], hopOffsets: [Int],
        arrivalTime: Double, generation: UInt64, discontinuity: Bool = false
    ) {
        guard let channels = pcm.floatChannelData,
              pcm.frameLength > 0, pcm.format.sampleRate.isFinite,
              pcm.format.sampleRate > 0, !spectrumFrames.isEmpty,
              spectrumFrames.count == hopOffsets.count
        else { return }
        self.lock.lock()
        let accepted = generation == self.epoch
        self.lock.unlock()
        guard accepted else { return }

        let rate = pcm.format.sampleRate
        let count = Int(pcm.frameLength)
        let reset = discontinuity || rate != self.retainedRate || generation != self.retainedEpoch
        if reset {
            self.retainedLeft.removeAll(keepingCapacity: true)
            self.retainedRight.removeAll(keepingCapacity: true)
        }
        let prefix = self.retainedLeft.count
        let left = self.retainedLeft + UnsafeBufferPointer(start: channels[0], count: count)
        let rightChannel = pcm.format.channelCount > 1 ? channels[1] : channels[0]
        let right = self.retainedRight + UnsafeBufferPointer(start: rightChannel, count: count)
        // A compact, reactive meter must release between transients. Share the waveform's
        // 20 ms window instead of smearing each beat over an additional 50 ms RMS window.
        let meterCount = max(1, Int(rate * 0.02))
        let waveformCount = meterCount
        var prepared: [AmpXMiniAudioSnapshot] = []
        prepared.reserveCapacity(spectrumFrames.count)
        var previousOffset = 0
        for (index, offset) in hopOffsets.enumerated() {
            let end = prefix + min(max(offset, 1), count)
            let start = max(0, end - meterCount)
            let l = Self.measure(left, in: start ..< end)
            let r = Self.measure(right, in: start ..< end)
            let waveStart = max(0, end - waveformCount)
            prepared.append(AmpXMiniAudioSnapshot(
                time: arrivalTime + Double(previousOffset) / rate,
                sampleRate: rate,
                spectrum: spectrumFrames[index],
                waveformLeft: Self.reduce(left, in: waveStart ..< end),
                waveformRight: Self.reduce(right, in: waveStart ..< end),
                rms: SIMD2(l.rms, r.rms), peak: SIMD2(l.peak, r.peak),
                isPlaying: true
            ))
            previousOffset = min(max(offset, 0), count)
        }
        self.retainedLeft = Array(left.suffix(meterCount))
        self.retainedRight = Array(right.suffix(meterCount))
        self.retainedRate = rate
        self.retainedEpoch = generation

        self.lock.lock()
        defer { self.lock.unlock() }
        guard generation == self.epoch else { return }
        if reset, !self.frames.isEmpty {
            self.visualGeneration &+= 1
        }
        for index in prepared.indices {
            self.sequence &+= 1
            prepared[index].sequence = self.sequence
            prepared[index].generation = self.visualGeneration
        }
        self.frames = prepared
    }

    private static func measure(_ samples: [Float], in range: Range<Int>) -> (rms: Float, peak: Float) {
        var sum: Double = 0
        var peak: Float = 0
        for index in range {
            let sample = samples[index].isFinite ? min(max(samples[index], -64), 64) : 0
            sum += Double(sample) * Double(sample)
            peak = max(peak, abs(sample))
        }
        return (Float(sqrt(sum / Double(max(1, range.count)))), peak)
    }

    /// Retain both signed extrema in source order. Keeping just the largest absolute
    /// sample would erase an opposite-polarity transient sharing the same bucket.
    private static func reduce(_ samples: [Float], in range: Range<Int>) -> [Float] {
        func finiteSample(_ index: Int) -> Float {
            let value = samples[index]
            return value.isFinite ? min(max(value, -1), 1) : 0
        }
        guard range.count > 512 else { return range.map(finiteSample) }
        var result: [Float] = []
        result.reserveCapacity(512)
        for index in 0 ..< 256 {
            let start = range.lowerBound + index * range.count / 256
            let end = range.lowerBound + (index + 1) * range.count / 256
            var minimum = finiteSample(start)
            var maximum = minimum
            var minimumIndex = start
            var maximumIndex = start
            for source in start ..< end {
                let value = finiteSample(source)
                if value < minimum {
                    minimum = value; minimumIndex = source
                }
                if value > maximum {
                    maximum = value; maximumIndex = source
                }
            }
            result.append(minimumIndex <= maximumIndex ? minimum : maximum)
            result.append(minimumIndex <= maximumIndex ? maximum : minimum)
        }
        return result
    }
}
