import AVFoundation
import os
import QuartzCore

/// Bounded latest-buffer mailbox. The single audio producer never waits: contention
/// drops a buffer, and the next successful capture explicitly reports the gap.
final class TapPCMStaging: @unchecked Sendable {
    struct Batch {
        let pcm: AVAudioPCMBuffer
        let generation: UInt64
        let arrivalTime: Double
        let discontinuity: Bool
    }

    private let lock = OSAllocatedUnfairLock()
    private let capacity: Int
    private var left: [Float]
    private var right: [Float]
    private var frameLength = 0
    private var channelCount = 1
    private var sampleRate: Double = 44100
    private var generation: UInt64 = 0
    private var arrivalTime: Double = 0
    private var discontinuity = false
    private var captureSequence: UInt64 = 0 // single producer only
    private var acceptedSequence: UInt64 = 0 // protected by lock
    private var cachedBuffer: AVAudioPCMBuffer?

    init(capacity: Int = 131_072) {
        self.capacity = max(256, capacity)
        self.left = [Float](repeating: 0, count: self.capacity)
        self.right = [Float](repeating: 0, count: self.capacity)
    }

    /// Called by one producer. Contention is dropped, never waited out.
    @discardableResult
    func capture(
        _ buffer: AVAudioPCMBuffer,
        generation: UInt64 = 0,
        arrivalTime: Double = CACurrentMediaTime()
    ) -> Bool {
        guard let channelData = buffer.floatChannelData else { return false }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return false }
        self.captureSequence &+= 1
        guard self.lock.lockIfAvailable() else { return false }
        defer { self.lock.unlock() }

        let channels = Int(buffer.format.channelCount)
        let n = min(frames, self.capacity)
        let start = frames - n
        let byteCount = n * MemoryLayout<Float>.size

        self.discontinuity = self.frameLength > 0 || frames > self.capacity
            || self.captureSequence != self.acceptedSequence &+ 1
        self.acceptedSequence = self.captureSequence
        self.frameLength = n
        self.channelCount = min(2, max(1, channels))
        self.sampleRate = buffer.format.sampleRate
        self.generation = generation
        self.arrivalTime = arrivalTime
        self.left.withUnsafeMutableBufferPointer { dst in
            guard let base = dst.baseAddress else { return }
            memcpy(base, channelData[0].advanced(by: start), byteCount)
        }
        self.right.withUnsafeMutableBufferPointer { dst in
            guard let base = dst.baseAddress else { return }
            if channels > 1 {
                memcpy(base, channelData[1].advanced(by: start), byteCount)
            } else {
                memcpy(base, channelData[0].advanced(by: start), byteCount)
            }
        }
        return true
    }

    /// Only the analysis consumer calls this. Each successful capture is consumed once.
    func take() -> Batch? {
        self.lock.lock()
        defer { self.lock.unlock() }

        let frames = self.frameLength
        let channels = self.channelCount
        let rate = self.sampleRate
        guard frames > 0,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: rate,
                  channels: AVAudioChannelCount(channels),
                  interleaved: false
              )
        else {
            return nil
        }

        let needsNew = self.cachedBuffer == nil
            || self.cachedBuffer?.format != format
            || Int(self.cachedBuffer?.frameCapacity ?? 0) < frames
        if needsNew {
            self.cachedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))
        }
        guard let out = self.cachedBuffer, let dst = out.floatChannelData else {
            return nil
        }
        out.frameLength = AVAudioFrameCount(frames)
        let byteCount = frames * MemoryLayout<Float>.size
        self.left.withUnsafeBufferPointer { src in
            guard let base = src.baseAddress else { return }
            memcpy(dst[0], base, byteCount)
        }
        if channels > 1 {
            self.right.withUnsafeBufferPointer { src in
                guard let base = src.baseAddress else { return }
                memcpy(dst[1], base, byteCount)
            }
        }
        self.frameLength = 0
        return Batch(
            pcm: out,
            generation: self.generation,
            arrivalTime: self.arrivalTime,
            discontinuity: self.discontinuity
        )
    }
}
