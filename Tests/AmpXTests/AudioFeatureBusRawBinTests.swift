@testable import AmpX
import AVFoundation
import XCTest

/// Task 0 (Stage 0): the raw linear FFT bin channel. `AudioFeatures.spectrum` is 32
/// log-spaced bands; consumers that index bins linearly or diff adjacent bins for
/// spectral flux (e.g. ENTHEA) need the full linear magnitude spectrum instead.
final class AudioFeatureBusRawBinTests: XCTestCase {
    func testRawBinSnapshotHasLinearBinCount() {
        let analyzer = FFTSpectrumAnalyzer(bandCount: AudioFeatures.spectrumBandCount, fftSize: 1024)
        let capturedBins = SendableBox<[UInt8]?>(nil)
        analyzer.onRawBins = { bins, _ in capturedBins.value = bins }

        let buffer = self.makeSineBuffer(frequency: 440, sampleRate: 44100, frameCount: 1024)
        _ = analyzer.analyze(buffer)

        XCTAssertEqual(capturedBins.value?.count, 512, "fftSize 1024 must publish fftSize / 2 = 512 linear bins")
    }

    func testRawBinSnapshotIsLinearlySpaced() {
        let sampleRate: Double = 44100
        let frequency: Double = 1000
        let frameCount = 1024

        let analyzer = FFTSpectrumAnalyzer(bandCount: AudioFeatures.spectrumBandCount, fftSize: frameCount)
        let capturedBins = SendableBox<[UInt8]?>(nil)
        analyzer.onRawBins = { bins, _ in capturedBins.value = bins }

        let buffer = self.makeSineBuffer(frequency: frequency, sampleRate: sampleRate, frameCount: frameCount)
        _ = analyzer.analyze(buffer)

        guard let bins = capturedBins.value else {
            return XCTFail("onRawBins never fired")
        }

        // Linear spacing means bin i sits at i * (sampleRate / 2) / bins.count. If the
        // mapping were accidentally log-spaced (like the 32-band path), the peak would
        // land at the wrong index for this frequency.
        let binHz = (sampleRate / 2) / Double(bins.count)
        let expectedBinIndex = Int((frequency / binHz).rounded())

        let peakIndex = bins.indices.max { bins[$0] < bins[$1] } ?? 0
        XCTAssertLessThanOrEqual(
            abs(peakIndex - expectedBinIndex),
            1,
            "expected peak near bin \(expectedBinIndex) for a \(frequency) Hz tone, got bin \(peakIndex)"
        )
    }

    func testRawBinSnapshotReportsSampleRate() {
        let sampleRate: Double = 48000
        let analyzer = FFTSpectrumAnalyzer(bandCount: AudioFeatures.spectrumBandCount, fftSize: 1024)
        let reportedSampleRate = SendableBox<Double?>(nil)
        analyzer.onRawBins = { _, rate in reportedSampleRate.value = rate }

        let buffer = self.makeSineBuffer(frequency: 440, sampleRate: sampleRate, frameCount: 1024)
        _ = analyzer.analyze(buffer)

        XCTAssertEqual(reportedSampleRate.value, sampleRate, "a wrong sample rate silently misplaces every band edge downstream")

        // Round-trip through the bus, matching the concurrency pattern of
        // `publishSpectrumFrames` / `spectrumSnapshot`.
        let bus = AudioFeatureBus.shared
        bus.publishRawBins(Array(repeating: 0, count: AudioFeatures.rawBinCount), sampleRate: sampleRate)
        let snapshot = bus.rawBinSnapshot()
        XCTAssertEqual(snapshot.sampleRate, sampleRate)
        XCTAssertEqual(snapshot.bins.count, AudioFeatures.rawBinCount)
    }

    /// Regression guard: wiring the new raw-bin channel must not perturb the existing
    /// 32-band spectrum the Metal mini viz consumes.
    func testExistingThirtyTwoBandSpectrumUnchanged() {
        let sampleRate: Double = 44100
        let frameCount = 1024
        let buffer = self.makeSineBuffer(frequency: 440, sampleRate: sampleRate, frameCount: frameCount)

        let withoutRawBins = FFTSpectrumAnalyzer(bandCount: AudioFeatures.spectrumBandCount, fftSize: frameCount)
        let baselineBands = withoutRawBins.analyze(buffer)

        let withRawBins = FFTSpectrumAnalyzer(bandCount: AudioFeatures.spectrumBandCount, fftSize: frameCount)
        withRawBins.onRawBins = { _, _ in }
        let bandsWithRawBinsWired = withRawBins.analyze(buffer)

        XCTAssertEqual(baselineBands.count, AudioFeatures.spectrumBandCount)
        XCTAssertEqual(
            baselineBands,
            bandsWithRawBinsWired,
            "the 32-band spectrum must be bit-for-bit identical whether or not onRawBins is wired"
        )
    }

    private func makeSineBuffer(frequency: Double, sampleRate: Double, frameCount: Int) -> AVAudioPCMBuffer {
        let samples = (0 ..< frameCount).map { index in
            Float(sin(2 * .pi * frequency * Double(index) / sampleRate))
        }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channelData = buffer.floatChannelData?[0]
        else {
            fatalError("Failed to create audio buffer")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        memcpy(channelData, samples, samples.count * MemoryLayout<Float>.size)
        return buffer
    }
}
