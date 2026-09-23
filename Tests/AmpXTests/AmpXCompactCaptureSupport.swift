@testable import AmpX
import AppKit
import Metal
import XCTest

/// Test-only composition of production AppKit drawing and production Metal offscreen output.
@MainActor
enum AmpXCompactCaptureSupport {
    static func capture(
        _ view: NSView, scale: CGFloat,
        visualizer: SpectrumWellView? = nil,
        frame: AmpXMiniVisualizerFrame? = nil,
        settings: AmpXMiniVisualizerSettings? = nil
    ) throws -> Data {
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int((view.bounds.width * scale).rounded()),
            pixelsHigh: Int((view.bounds.height * scale).rounded()), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        let output = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        try output.draw(XCTUnwrap(rep.cgImage), in: CGRect(x: 0, y: 0, width: width, height: height))
        if let visualizer, let frame, let settings {
            let renderer = try XCTUnwrap(AmpXMiniVisualizerRenderer())
            let rect = visualizer.convert(visualizer.spectrumRect, to: view)
            let x0 = Int((rect.minX * scale).rounded())
            let y0 = Int((rect.minY * scale).rounded())
            let width = Int((rect.width * scale).rounded())
            let height = Int((rect.height * scale).rounded())
            let texture = try renderer.renderOffscreen(
                frame,
                style: settings.style,
                palette: settings.palette,
                width: width,
                height: height
            )
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            bytes.withUnsafeMutableBytes { storage in
                texture.getBytes(
                    storage.baseAddress!,
                    bytesPerRow: width * 4,
                    from: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0
                )
            }
            let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
            let image = try XCTUnwrap(CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)],
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
            ))
            // Metal scanlines begin at the top; CGContext drawing coordinates begin at the bottom.
            output.draw(image, in: CGRect(x: x0, y: output.height - y0 - height, width: width, height: height))
        }
        return try XCTUnwrap(NSBitmapImageRep(cgImage: XCTUnwrap(output.makeImage())).representation(using: .png, properties: [:]))
    }

    static var signal: AmpXMiniVisualizerFrame {
        var frame = AmpXMiniVisualizerFrame()
        frame.spectrum = (0 ..< 32).map { index in
            Float(max(0.05, 0.85 * exp(-Double(abs(index - 5)) / 8)))
        }
        frame.peaks = frame.spectrum.map { min(1, $0 + 0.05) }
        frame.waveform = (0 ..< 256).map { Float(sin(Double($0) * 0.09) * 0.7) }
        frame.meterLevels = SIMD2(0.75, 0.4)
        frame.meterPeaks = SIMD2(0.9, 0.65)
        frame.history = (0 ..< 4096).map { Float($0 % 32) / 32 }
        frame.particleOpacity = 1
        frame.elapsed = 1.25
        frame.isActive = true
        return frame
    }
}
