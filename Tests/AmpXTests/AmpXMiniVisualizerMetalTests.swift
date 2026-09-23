@testable import AmpX
import AppKit
import ImageIO
import MetalKit
import UniformTypeIdentifiers
import XCTest

@MainActor
final class AmpXMiniVisualizerMetalTests: XCTestCase {
    func testAllStylesAndPalettesRenderSignalAtCompactDimensions() throws {
        let renderer = try self.makeRenderer()
        for scale in [1, 2, 3] {
            for style in AmpXMiniVisualizerStyle.allCases {
                for palette in AmpXMiniVisualizerPalette.allCases {
                    let active = try self.capture(
                        renderer,
                        frame: self.signal(),
                        style: style,
                        palette: palette,
                        width: 110 * scale,
                        height: 18 * scale
                    )
                    let silent = try self.capture(
                        renderer,
                        frame: AmpXMiniVisualizerFrame(),
                        style: style,
                        palette: palette,
                        width: 110 * scale,
                        height: 18 * scale
                    )
                    XCTAssertTrue(active.bytes.enumerated().allSatisfy { $0.offset % 4 != 3 || $0.element == 255 })
                    XCTAssertGreaterThan(active.meanBrightness(), silent.meanBrightness(), "\(style), \(palette), \(scale)×")
                    XCTAssertNotEqual(active.bytes, silent.bytes)
                }
            }
        }
    }

    func testMissingDeviceReturnsNilWithoutCrashing() {
        XCTAssertNil(AmpXMiniVisualizerRenderer(device: nil))
    }

    func testCompletedCapturesPublishBoundedPerformanceStatistics() throws {
        let renderer = try self.makeRenderer()
        let frame = self.signal()
        for index in 0 ..< 144 {
            let style = AmpXMiniVisualizerStyle.allCases[index % AmpXMiniVisualizerStyle.allCases.count]
            _ = try self.capture(renderer, frame: frame, style: style, width: 275, height: 82)
        }
        let statistics = renderer.statistics
        XCTAssertEqual(statistics.submittedFrames, 144)
        XCTAssertEqual(statistics.completedFrames, 144)
        XCTAssertEqual(statistics.droppedFrames, 0)
        XCTAssertEqual(statistics.failedFrames, 0)
        XCTAssertGreaterThan(statistics.cpuEncodingP95Milliseconds, 0)
        XCTAssertGreaterThanOrEqual(statistics.gpuP95Milliseconds, 0)
        print("""
        Mini Metal \(renderer.device.name), Debug captures at 275×82:
        120-frame CPU encoding p95 \(statistics.cpuEncodingP95Milliseconds) ms;
        GPU p95 \(statistics.gpuP95Milliseconds) ms (\(statistics.gpuTimingSamples) GPU samples).
        """)
    }

    func testCaptureRejectsInvalidAndUnrepresentableDimensions() throws {
        let renderer = try self.makeRenderer()
        for (width, height) in [(0, 41), (138, 0), (-1, 41), (138, -1), (Int.max, 41)] {
            XCTAssertThrowsError(try renderer.renderOffscreen(
                AmpXMiniVisualizerFrame(), style: .classicSpectrum, palette: .blue,
                width: width, height: height
            ))
        }
    }

    /// Catches missing effects, palette branches, shader failures, and transparent/empty captures.
    /// These are also the deterministic 1×/2× artifacts for visual inspection.
    func testAllStylesAndPalettesRenderDistinctOpaqueCapturesAtBothScales() throws {
        let renderer = try self.makeRenderer()
        print("Mini visualizer captures: \(self.captureDirectory.path)")
        for (width, height, scale) in [(138, 41, 1), (275, 82, 2)] {
            for palette in AmpXMiniVisualizerPalette.allCases {
                var captures = Set<Data>()
                for style in AmpXMiniVisualizerStyle.allCases {
                    let pixels = try self.capture(
                        renderer,
                        frame: self.signal(),
                        style: style,
                        palette: palette,
                        width: width,
                        height: height
                    )
                    XCTAssertTrue(pixels.bytes.enumerated().allSatisfy { $0.offset % 4 != 3 || $0.element == 255 })
                    XCTAssertGreaterThan(pixels.brightCount(), width / 2, "\(style), \(palette), \(scale)×")
                    let totals = pixels.channelTotals()
                    let context = "\(style), \(palette), \(scale)×"
                    switch palette {
                    case .blue:
                        XCTAssertGreaterThan(totals.blue, totals.red * 1.5, context)
                    case .classic:
                        XCTAssertGreaterThan(totals.green, totals.blue * 1.5, context)
                    case .red:
                        XCTAssertGreaterThan(totals.red, totals.green * 1.35, context)
                        XCTAssertGreaterThan(totals.red, totals.blue * 1.5, context)
                    case .green:
                        XCTAssertGreaterThan(totals.green, totals.red * 1.15, context)
                        XCTAssertGreaterThan(totals.green, totals.blue * 1.2, context)
                    case .amber:
                        XCTAssertGreaterThan(totals.red, totals.green * 1.05, context)
                        XCTAssertGreaterThan(totals.green, totals.blue * 1.25, context)
                    }
                    XCTAssertTrue(captures.insert(Data(pixels.bytes)).inserted, "\(style) duplicates an earlier effect")
                    try self.save(pixels, name: "\(style.rawValue)-\(palette.rawValue)-\(scale)x")
                }
                XCTAssertEqual(captures.count, 8)
            }
        }
    }

    func testSilenceStaysDarkInEveryStyleAndPalette() throws {
        let renderer = try self.makeRenderer()
        for style in AmpXMiniVisualizerStyle.allCases {
            for palette in AmpXMiniVisualizerPalette.allCases {
                let pixels = try self.capture(renderer, frame: AmpXMiniVisualizerFrame(), style: style, palette: palette)
                XCTAssertLessThan(pixels.meanBrightness(), 24, "\(style), \(palette)")
                XCTAssertEqual(pixels.brightCount(), 0, "\(style) must not invent signal in silence")
            }
        }
    }

    func testClassicFullLevelSpectrumPeaksMetersAndHistoryReachRed() throws {
        let renderer = try self.makeRenderer()
        var frame = AmpXMiniVisualizerFrame()
        frame.spectrum = Array(repeating: 1, count: 32)
        frame.peaks = Array(repeating: 1, count: 32)
        frame.meterLevels = SIMD2(repeating: 1)
        frame.meterPeaks = SIMD2(repeating: 1)
        frame.history = Array(repeating: 1, count: 32 * 128)
        for (width, height, scale) in [(138, 41, 1), (275, 82, 2)] {
            for style in [AmpXMiniVisualizerStyle.classicSpectrum, .stereoBars, .waterfall] {
                let pixels = try self.capture(
                    renderer, frame: frame, style: style, palette: .classic, width: width, height: height
                )
                // Spectrum: top peak cap; meters: rightmost peak; waterfall: maximum-energy cell.
                let x = style == .stereoBars ? width - 1 : 1
                let y = style == .stereoBars ? Int(Double(height) * 0.27) : scale
                let offset = (y * width + x) * 4
                let red = Int(pixels.bytes[offset + 2])
                let green = Int(pixels.bytes[offset + 1])
                let blue = Int(pixels.bytes[offset])
                XCTAssertGreaterThan(red, 200, "\(style), \(scale)× maximum must stay bright")
                XCTAssertGreaterThan(red, green * 4, "\(style), \(scale)× maximum must be red, not amber")
                XCTAssertGreaterThan(red, blue * 8, "\(style), \(scale)× maximum must be red")
            }
        }
    }

    func testClassicSpectrumReachesYellowAtHalfHeight() throws {
        let renderer = try self.makeRenderer()
        var frame = AmpXMiniVisualizerFrame()
        frame.spectrum = Array(repeating: 1, count: 32)
        for (width, height, scale) in [(138, 41, 1), (275, 82, 2)] {
            let pixels = try self.capture(
                renderer, frame: frame, style: .classicSpectrum,
                palette: .classic, width: width, height: height
            )
            let middle = pixels.color(x: 1, y: height / 2)
            XCTAssertEqual(middle.x, 255, accuracy: 5, "Yellow belongs at 50% of the display height")
            XCTAssertEqual(middle.y, 210, accuracy: 5)
            XCTAssertEqual(middle.z, 26, accuracy: 5)
            try self.save(pixels, name: "classic-centered-gradient-\(scale)x")
        }
    }

    func testClassicHeldPeaksKeepTheGradientColorAtTheirHeight() throws {
        let renderer = try self.makeRenderer()
        for (width, height, scale) in [(138, 41, 1), (275, 82, 2)] {
            for style in [AmpXMiniVisualizerStyle.classicSpectrum, .stereoBars] {
                var full = AmpXMiniVisualizerFrame()
                full.spectrum = Array(repeating: 1, count: 32)
                full.meterLevels = SIMD2(repeating: 1)
                let reference = try self.capture(
                    renderer, frame: full, style: style, palette: .classic, width: width, height: height
                )
                for peak: Float in [0.2, 0.5, 0.9] {
                    var held = AmpXMiniVisualizerFrame()
                    held.spectrum = Array(repeating: 0.05, count: 32)
                    held.peaks = Array(repeating: peak, count: 32)
                    held.meterLevels = SIMD2(repeating: 0.05)
                    held.meterPeaks = SIMD2(repeating: peak)
                    let pixels = try self.capture(
                        renderer, frame: held, style: style, palette: .classic, width: width, height: height
                    )
                    let x: Int
                    let y: Int
                    if style == .classicSpectrum {
                        x = 1
                        y = height - scale - Int(peak * Float(height - 2 * scale)) - 1
                    } else {
                        // Pick a lit cell next to the held marker, outside the row's center gap.
                        x = Int(peak * Float(width - 1))
                        y = Int(Float(height) * 0.27) - 2 * scale
                    }
                    var referenceX = x
                    if style == .stereoBars {
                        while referenceX > 0, reference.brightness(x: referenceX, y: y) == 0 {
                            referenceX -= 1
                        }
                    }
                    XCTAssertGreaterThan(reference.brightness(x: referenceX, y: y), 0)
                    XCTAssertGreaterThan(pixels.brightness(x: x, y: y), 0)
                    let cap = pixels.color(x: x, y: y)
                    let bar = reference.color(x: referenceX, y: y)
                    for channel in 0 ..< 3 {
                        XCTAssertEqual(
                            cap[channel], bar[channel], accuracy: 16,
                            "\(style), \(scale)×, held \(peak): the peak must keep its level color after the body falls"
                        )
                    }
                    try self.save(pixels, name: "classic-held-\(Int(peak * 100))-\(style.rawValue)-\(scale)x")
                }
            }
        }
    }

    func testStereoRowsRetainIndependentRMSAndSamplePeak() throws {
        let renderer = try self.makeRenderer()
        var frame = AmpXMiniVisualizerFrame()
        frame.meterLevels = SIMD2(0.8, 0.2)
        frame.meterPeaks = SIMD2(0.95, 0.35)
        frame.isActive = true
        let pixels = try self.capture(renderer, frame: frame, style: .stereoBars, width: 256, height: 80)
        XCTAssertGreaterThan(pixels.brightCount(rows: 0 ..< 40), pixels.brightCount(rows: 40 ..< 80) * 2)
        XCTAssertGreaterThan(pixels.brightCount(columns: 238 ..< 247, rows: 0 ..< 40), 0, "left sample peak")
        XCTAssertEqual(pixels.brightCount(columns: 220 ..< 230, rows: 0 ..< 40), 0, "gap between RMS and sample peak")
        XCTAssertEqual(pixels.brightCount(columns: 238 ..< 247, rows: 40 ..< 80), 0, "right meter cannot borrow left peak")
    }

    func testMirroredSpectrumHasSymmetricVisibleReflectionsAtBothScales() throws {
        let renderer = try self.makeRenderer()
        for (width, height) in [(138, 41), (275, 82)] {
            for palette in AmpXMiniVisualizerPalette.allCases {
                var frame = AmpXMiniVisualizerFrame()
                frame.spectrum = (0 ..< 32).map { $0 % 2 == 0 ? 0.45 : 0.9 }
                let pixels = try self.capture(
                    renderer, frame: frame, style: .mirroredSpectrum,
                    palette: palette, width: width, height: height
                )
                var reflectedPixels = 0
                var dimOrMissingPixels = 0
                for y in 0 ..< height / 2 {
                    for x in 0 ..< width {
                        let top = pixels.brightness(x: x, y: y)
                        let bottom = pixels.brightness(x: x, y: height - 1 - y)
                        if top == 0 {
                            if bottom != 0 {
                                dimOrMissingPixels += 1
                            }
                        } else {
                            reflectedPixels += 1
                            if Double(bottom) < Double(top) * 0.65 || bottom > top {
                                dimOrMissingPixels += 1
                            }
                        }
                    }
                }
                XCTAssertGreaterThan(reflectedPixels, width, "\(palette) \(width)×\(height)")
                XCTAssertEqual(dimOrMissingPixels, 0, "every lit bar cell needs a visible matching reflection")
            }
        }
    }

    func testWaterfallUsesOldestFirstHistoryWithNewestAtBottom() throws {
        let renderer = try self.makeRenderer()
        var frame = AmpXMiniVisualizerFrame()
        frame.history = Array(repeating: 0, count: 32 * 128)
        frame.history[5] = 1
        frame.history[127 * 32 + 26] = 1
        let pixels = try self.capture(renderer, frame: frame, style: .waterfall, width: 256, height: 128)
        XCTAssertGreaterThan(pixels.brightness(x: 44, y: 0), 110)
        XCTAssertLessThan(pixels.brightness(x: 212, y: 0), 50)
        XCTAssertGreaterThan(pixels.brightness(x: 212, y: 127), 110)
        XCTAssertLessThan(pixels.brightness(x: 44, y: 127), 50)
        XCTAssertEqual(pixels.brightCount(rows: 50 ..< 80), 0)

        frame.history = []
        let cleared = try self.capture(renderer, frame: frame, style: .waterfall, width: 256, height: 128)
        XCTAssertEqual(cleared.brightCount(), 0, "a later empty frame cannot reuse stale history")
        XCTAssertGreaterThan(pixels.brightness(x: 44, y: 0), 110, "capture storage remains independent")
    }

    func testWaveformAndParticlesFollowPCMIndependentlyOfSpectrum() throws {
        let renderer = try self.makeRenderer()
        for style in [AmpXMiniVisualizerStyle.lineWaveform, .particleWaveform] {
            var frame = self.signal()
            frame.waveform = Array(repeating: 0.65, count: 256)
            let positive = try self.capture(renderer, frame: frame, style: style, width: 275, height: 82)
            XCTAssertGreaterThan(positive.brightCount(rows: 0 ..< 41), positive.brightCount(rows: 41 ..< 82))
            frame.spectrum = Array(repeating: 0, count: 32)
            frame.peaks = Array(repeating: 0, count: 32)
            let otherSpectrum = try self.capture(renderer, frame: frame, style: style, width: 275, height: 82)
            XCTAssertEqual(positive.bytes, otherSpectrum.bytes, "\(style) uses waveform, not FFT bands")
            frame.waveform = Array(repeating: -0.65, count: 256)
            let negative = try self.capture(renderer, frame: frame, style: style, width: 275, height: 82)
            XCTAssertGreaterThan(negative.brightCount(rows: 41 ..< 82), negative.brightCount(rows: 0 ..< 41))
        }
    }

    func testParticleOpacitySettlesAndFixedTimeIsDeterministic() throws {
        let renderer = try self.makeRenderer()
        var frame = self.signal()
        let first = try self.capture(renderer, frame: frame, style: .particleWaveform)
        let repeated = try self.capture(renderer, frame: frame, style: .particleWaveform)
        XCTAssertEqual(first.bytes, repeated.bytes)
        frame.elapsed += 0.2
        let advanced = try self.capture(renderer, frame: frame, style: .particleWaveform)
        XCTAssertNotEqual(first.bytes, advanced.bytes)
        frame.particleOpacity = 0
        let settled = try self.capture(renderer, frame: frame, style: .particleWaveform)
        XCTAssertEqual(settled.brightCount(), 0)
    }

    func testQuietParticleWaveformRemainsVisibleWithoutLightingTheBackground() throws {
        let renderer = try self.makeRenderer()
        var frame = AmpXMiniVisualizerFrame()
        frame.waveform = Array(repeating: 0.15, count: 256)
        frame.particleOpacity = 0.15
        frame.elapsed = 1.25
        for palette in AmpXMiniVisualizerPalette.allCases {
            let pixels = try self.capture(renderer, frame: frame, style: .particleWaveform, palette: palette, width: 275, height: 82)
            XCTAssertGreaterThan(pixels.brightCount(threshold: 60), 50, "\(palette): quiet music still needs visible points")
            XCTAssertLessThan(pixels.meanBrightness(), 12, "the surrounding display stays dark")
        }
    }

    func testWaterfallSeparatesModerateEnergyFromStrongEnergy() throws {
        let renderer = try self.makeRenderer()
        var frame = AmpXMiniVisualizerFrame()
        frame.history = (0 ..< 4096).map { $0 % 32 < 16 ? 0.35 : 0.8 }
        for palette in AmpXMiniVisualizerPalette.allCases {
            let pixels = try self.capture(renderer, frame: frame, style: .waterfall, palette: palette, width: 256, height: 128)
            let moderate = pixels.brightness(x: 64, y: 64)
            let strong = pixels.brightness(x: 192, y: 64)
            XCTAssertGreaterThan(strong, 120, "\(palette): hot bands stay vivid")
            XCTAssertLessThan(Double(moderate), Double(strong) * 0.33, "\(palette): preserve contrast in dense music")
        }
    }

    func testStereoMetersDoNotAnimateFromElapsedTimeOrSpectrum() throws {
        let renderer = try self.makeRenderer()
        var frame = self.signal()
        let first = try self.capture(renderer, frame: frame, style: .stereoBars)
        frame.elapsed += 10
        frame.spectrum = Array(repeating: 0, count: 32)
        frame.waveform = []
        let later = try self.capture(renderer, frame: frame, style: .stereoBars)
        XCTAssertEqual(first.bytes, later.bytes, "only measured L/R signal levels may move the meters")
    }

    func testDotCellsAreSquareWithCrispBlackGutters() throws {
        let renderer = try self.makeRenderer()
        var frame = AmpXMiniVisualizerFrame()
        frame.spectrum = Array(repeating: 1, count: 32)
        let pixels = try self.capture(renderer, frame: frame, style: .dotSpectrum, width: 128, height: 48)
        // A four-pixel column pitch has a three-by-three lit square and a one-pixel gutter.
        for y in 44 ..< 47 {
            for x in 4 ..< 7 {
                XCTAssertGreaterThan(pixels.brightness(x: x, y: y), 110)
            }
            XCTAssertEqual(pixels.brightness(x: 7, y: y), 0)
        }
        XCTAssertEqual(pixels.brightness(x: 5, y: 43), 0)
    }

    func testNonfiniteAndOversizedInputsCannotLeakStaleSignal() throws {
        let renderer = try self.makeRenderer()
        var frame = AmpXMiniVisualizerFrame()
        frame.spectrum = Array(repeating: .nan, count: 1024)
        frame.peaks = [.infinity, -.infinity]
        frame.trails = [.nan]
        frame.waveform = Array(repeating: .nan, count: 4096)
        frame.history = Array(repeating: .infinity, count: 32 * 256)
        frame.meterLevels = SIMD2(.nan, .infinity)
        frame.meterPeaks = SIMD2(.nan, -.infinity)
        frame.particleOpacity = .nan
        frame.elapsed = .infinity
        for style in AmpXMiniVisualizerStyle.allCases {
            _ = try self.capture(renderer, frame: self.signal(), style: style)
            let invalid = try self.capture(renderer, frame: frame, style: style)
            XCTAssertEqual(invalid.brightCount(), 0, "\(style)")
        }
    }
}

extension AmpXMiniVisualizerMetalTests {
    private func makeRenderer() throws -> AmpXMiniVisualizerRenderer {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device on this test host")
        }
        return try XCTUnwrap(AmpXMiniVisualizerRenderer(device: device), "Mini Metal library/pipelines must initialize")
    }

    private func signal() -> AmpXMiniVisualizerFrame {
        var frame = AmpXMiniVisualizerFrame()
        frame.spectrum = (0 ..< 32).map { index in
            let x = Float(index)
            return 0.12 + 0.64 * exp(-pow((x - 7) / 4, 2)) + 0.38 * exp(-pow((x - 20) / 5, 2))
        }
        frame.peaks = frame.spectrum.map { min(1, $0 + 0.14) }
        frame.trails = frame.spectrum.map { min(1, $0 + 0.08) }
        frame.waveform = (0 ..< 256).map { index in
            let x = Float(index) / 255
            return 0.55 * sin(x * .pi * 6) + 0.12 * sin(x * .pi * 26)
        }
        frame.meterLevels = SIMD2(0.78, 0.38)
        frame.meterPeaks = SIMD2(0.92, 0.56)
        frame.history = (0 ..< 128).flatMap { row in
            frame.spectrum.enumerated().map { column, value in
                value * (0.35 + 0.65 * abs(sin(Float(row) * 0.055 + Float(column) * 0.13)))
            }
        }
        frame.particleOpacity = 1
        frame.elapsed = 1.25
        frame.isActive = true
        return frame
    }

    private func capture(
        _ renderer: AmpXMiniVisualizerRenderer, frame: AmpXMiniVisualizerFrame,
        style: AmpXMiniVisualizerStyle, palette: AmpXMiniVisualizerPalette = .blue,
        width: Int = 138, height: Int = 41
    ) throws -> Pixels {
        let texture = try renderer.renderOffscreen(frame, style: style, palette: palette, width: width, height: height)
        XCTAssertEqual(texture.width, width)
        XCTAssertEqual(texture.height, height)
        XCTAssertEqual(texture.pixelFormat, .bgra8Unorm)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { storage in
            if let base = storage.baseAddress {
                texture.getBytes(base, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            }
        }
        return Pixels(bytes: bytes, width: width, height: height)
    }

    private func save(_ pixels: Pixels, name: String) throws {
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels.bytes) as CFData))
        let image = try XCTUnwrap(CGImage(
            width: pixels.width, height: pixels.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: pixels.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)],
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        try FileManager.default.createDirectory(at: self.captureDirectory, withIntermediateDirectories: true)
        try (data as Data).write(to: self.captureDirectory.appendingPathComponent("\(name).png"))
        let attachment = XCTAttachment(data: data as Data, uniformTypeIdentifier: UTType.png.identifier)
        attachment.name = name
        attachment.lifetime = .keepAlways
        self.add(attachment)
    }

    private var captureDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ampx-mini-metal-captures", isDirectory: true)
    }

    private struct ChannelTotals {
        var red = 0.0
        var green = 0.0
        var blue = 0.0
    }

    private struct Pixels {
        let bytes: [UInt8]
        let width: Int
        let height: Int

        func color(x: Int, y: Int) -> SIMD3<Double> {
            let offset = (y * self.width + x) * 4
            return SIMD3(Double(self.bytes[offset + 2]), Double(self.bytes[offset + 1]), Double(self.bytes[offset]))
        }

        func brightness(x: Int, y: Int) -> Int {
            let offset = (y * self.width + x) * 4
            return Int(max(self.bytes[offset], self.bytes[offset + 1], self.bytes[offset + 2]))
        }

        func brightCount(columns: Range<Int>? = nil, rows: Range<Int>? = nil, threshold: Int = 110) -> Int {
            var count = 0
            for y in rows ?? 0 ..< self.height {
                for x in columns ?? 0 ..< self.width where self.brightness(x: x, y: y) > threshold {
                    count += 1
                }
            }
            return count
        }

        func meanBrightness() -> Double {
            var total = 0
            for y in 0 ..< self.height {
                for x in 0 ..< self.width {
                    total += self.brightness(x: x, y: y)
                }
            }
            return Double(total) / Double(self.width * self.height)
        }

        func channelTotals() -> ChannelTotals {
            var result = ChannelTotals()
            for offset in stride(from: 0, to: self.bytes.count, by: 4) {
                result.blue += Double(self.bytes[offset])
                result.green += Double(self.bytes[offset + 1])
                result.red += Double(self.bytes[offset + 2])
            }
            return result
        }
    }
}
