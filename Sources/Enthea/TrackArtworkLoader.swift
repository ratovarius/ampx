import AppKit
import AVFoundation
import Foundation
import ImageIO

/// Loads embedded cover art for Image Warp. Separate from `Track` so playlist rows stay light.
enum TrackArtworkLoader {
    /// JPEG (or PNG) bytes suitable for a `data:` URL, downscaled to `maxPixel` on the long edge.
    static func loadImageData(from url: URL, maxPixel: CGFloat = 512) async -> Data? {
        let asset = AVURLAsset(url: url)
        let metadata = await (try? asset.load(.commonMetadata)) ?? []
        for item in metadata {
            guard item.commonKey == .commonKeyArtwork else { continue }
            if let data = try? await item.load(.dataValue), !data.isEmpty {
                return Self.downscale(data, maxPixel: maxPixel) ?? data
            }
        }
        return nil
    }

    /// Downscale for WebView IPC — full-res album art can be multi‑MB.
    static func downscale(_ data: Data, maxPixel: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let longest = max(width, height)
        guard longest > maxPixel else {
            return Self.jpegData(from: image, quality: 0.85)
        }

        let scale = maxPixel / longest
        let size = CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSImage(cgImage: image, size: size).draw(in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    private static func jpegData(from image: CGImage, quality: CGFloat) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}

/// Host push-rate policy (Task 7). Theater / large panels keep ~60 Hz; small docked panels cap at 30.
enum EntheaPushRatePolicy {
    static let theaterOrLargeHz: Double = 60
    static let dockedSmallHz: Double = 30
    /// Above this content area (pt²), treat as “large” (full rate).
    static let largeAreaThreshold: CGFloat = 600 * 450

    static func pushHz(forContentSize size: CGSize, isTheater: Bool) -> Double {
        if isTheater {
            return self.theaterOrLargeHz
        }
        let area = max(0, size.width) * max(0, size.height)
        return area >= Self.largeAreaThreshold ? Self.theaterOrLargeHz : Self.dockedSmallHz
    }
}
