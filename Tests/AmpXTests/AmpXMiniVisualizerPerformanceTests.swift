@testable import AmpX
import AppKit
import MetalKit
import XCTest

@MainActor
final class AmpXMiniVisualizerPerformanceTests: XCTestCase {
    /// Records a bounded rolling sample after warm-up. The diagnostic values are reported
    /// with the build/hardware; CI scheduling is not used as a hard timing assertion.
    func testRecordNativeMiniFrameCosts() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("No Metal device") }
        for style in AmpXMiniVisualizerStyle.allCases {
            let renderer = try XCTUnwrap(AmpXMiniVisualizerRenderer())
            var frame = AmpXMiniVisualizerFrame()
            frame.spectrum = (0 ..< 32).map { 0.15 + Float($0 % 8) * 0.1 }
            frame.peaks = frame.spectrum.map { min(1, $0 + 0.1) }
            frame.trails = frame.peaks
            frame.waveform = (0 ..< 512).map { sin(Float($0) * 0.05) * 0.7 }
            frame.history = (0 ..< 4096).map { Float($0 % 32) / 31 }
            frame.meterLevels = SIMD2(0.8, 0.45)
            frame.meterPeaks = SIMD2(0.9, 0.65)
            frame.particleOpacity = 0.8
            frame.isActive = true
            var warmAllocatedBytes = 0
            for index in 0 ..< 140 {
                frame.elapsed = Float(index) / 60
                try autoreleasepool {
                    _ = try renderer.renderOffscreen(frame, style: style, palette: .blue, width: 275, height: 82)
                }
                if index == 39 {
                    warmAllocatedBytes = renderer.device.currentAllocatedSize
                }
            }
            let stats = renderer.statistics
            XCTAssertEqual(stats.failedFrames, 0)
            XCTAssertEqual(stats.submittedFrames, 140)
            XCTAssertEqual(stats.completedFrames, 140)
            print(
                "MINI_PERF \(style.rawValue)"
                    + " cpu_p95_ms=\(stats.cpuEncodingP95Milliseconds)"
                    + " gpu_p95_ms=\(stats.gpuP95Milliseconds)"
                    + " gpu_samples=\(stats.gpuTimingSamples)"
            )
            print(
                "MINI_MEMORY \(style.rawValue) warm_bytes=\(warmAllocatedBytes)"
                    + " final_bytes=\(renderer.device.currentAllocatedSize)"
            )
        }
    }

    func testHiddenHostDoesNotSubmitFramesAndFailedMetalUsesFallback() throws {
        try self.assertHiddenHostAndFallback(compact: false)
    }

    func testCompactHiddenHostDoesNotSubmitFramesAndFailedMetalUsesFallback() throws {
        try self.assertHiddenHostAndFallback(compact: true)
    }

    private func assertHiddenHostAndFallback(compact: Bool) throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("No Metal device") }
        let renderer = try XCTUnwrap(AmpXMiniVisualizerRenderer())
        let well = SpectrumWellView(skin: ClassicModernSkin())
        well.geometry = compact ? .compact : .expanded
        well.rendererFactory = { renderer }
        well.frame = compact ? AmpXCompactMetrics.playerLayout().visualizer : CGRect(x: 0, y: 0, width: 180, height: 100)
        well.audioSource = { time in
            AmpXMiniAudioSnapshot(
                sequence: UInt64(max(0, time * 1000)),
                time: time,
                spectrum: [Float](repeating: 0.6, count: 32),
                isPlaying: true
            )
        }
        let window = NSWindow(contentRect: well.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = well
        defer { well.setEffectivelyVisible(false); window.close() }
        window.orderFront(nil)
        well.setEffectivelyVisible(true)
        well.layoutSubtreeIfNeeded()
        well.tick(at: 1)
        XCTAssertGreaterThan(renderer.statistics.submittedFrames, 0)
        let surface = try XCTUnwrap(well.subviews.compactMap { $0 as? MTKView }.first)
        let previousDrawable = try XCTUnwrap(surface.currentDrawable).drawableID
        well.tick(at: 1.02)
        let nextDrawable = try XCTUnwrap(surface.currentDrawable).drawableID
        XCTAssertNotEqual(previousDrawable, nextDrawable, "the host must complete MTKView's draw cycle for each presentation")
        let beforePalette = renderer.statistics.submittedFrames
        well.selectPalette(.classic)
        XCTAssertGreaterThan(renderer.statistics.submittedFrames, beforePalette)
        well.setEffectivelyVisible(false)
        let submissions = renderer.statistics.submittedFrames
        for index in 0 ..< 30 {
            well.tick(at: 2 + Double(index) / 60)
        }
        XCTAssertEqual(renderer.statistics.submittedFrames, submissions)

        let fallback = SpectrumWellView(skin: ClassicModernSkin())
        fallback.geometry = well.geometry
        fallback.rendererFactory = { nil }
        fallback.frame = well.frame
        window.contentView = fallback
        fallback.setEffectivelyVisible(true)
        fallback.selectStyle(.particleWaveform)
        fallback.tick(at: 1)
        XCTAssertEqual(fallback.settings.style, .particleWaveform)
        XCTAssertNotNil(fallback.toolTip)
        fallback.setEffectivelyVisible(false)
    }

    func testLiveFrameCadenceAndParkedSubmissionCounts() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("No Metal device") }
        let renderer = try XCTUnwrap(AmpXMiniVisualizerRenderer())
        let well = SpectrumWellView(skin: ClassicModernSkin())
        well.rendererFactory = { renderer }
        well.frame = CGRect(x: 0, y: 0, width: 180, height: 100)
        var playing = true
        well.audioSource = { time in
            AmpXMiniAudioSnapshot(
                sequence: UInt64(max(0, time * 10000)),
                time: time,
                spectrum: [Float](repeating: 0.6, count: 32),
                waveformLeft: (0 ..< 128).map { sin(Float($0) * 0.1) * 0.6 },
                rms: SIMD2(0.4, 0.2),
                peak: SIMD2(0.6, 0.3),
                isPlaying: playing
            )
        }
        let window = NSWindow(contentRect: well.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = well
        defer { well.setEffectivelyVisible(false); window.close() }
        window.orderFront(nil)
        well.setEffectivelyVisible(true)
        well.layoutSubtreeIfNeeded()
        // Warm every effect and all in-flight histories before measuring the live loop.
        for _ in 0 ..< 2 {
            for style in AmpXMiniVisualizerStyle.allCases {
                well.selectStyle(style)
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        let warmBytes = renderer.device.currentAllocatedSize
        let before = renderer.statistics.submittedFrames
        let start = CACurrentMediaTime()
        try await Task.sleep(for: .seconds(1))
        let elapsed = CACurrentMediaTime() - start
        let after = renderer.statistics
        XCTAssertGreaterThan(after.submittedFrames, before)
        XCTAssertEqual(after.failedFrames, 0)
        print(
            "MINI_LIVE fps=\(Double(after.submittedFrames - before) / elapsed)"
                + " cpu_p95_ms=\(after.cpuEncodingP95Milliseconds)"
                + " gpu_p95_ms=\(after.gpuP95Milliseconds)"
                + " warm_bytes=\(warmBytes) final_bytes=\(renderer.device.currentAllocatedSize)"
                + " dropped=\(after.droppedFrames)"
        )
        playing = false
        well.playbackStateDidChange(isPlaying: false)
        // Particle release plus the one-second idle hold can exceed two seconds.
        // Wait for the lifecycle event, with a deadline, rather than assuming a fixed duration.
        let parkDeadline = CACurrentMediaTime() + 4
        while !well.isContinuousRenderingPaused, CACurrentMediaTime() < parkDeadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(well.isContinuousRenderingPaused)
        let parkedSubmissions = renderer.statistics.submittedFrames
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(renderer.statistics.submittedFrames, parkedSubmissions)
    }
}
