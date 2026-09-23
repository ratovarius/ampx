@testable import AmpX
import AppKit
import XCTest

@MainActor
final class AmpXSliderColorRampTests: XCTestCase {
    private let green = AmpXRGB(r: 14, g: 236, b: 2)
    private let yellow = AmpXRGB(r: 247, g: 210, b: 3)
    private let red = AmpXRGB(r: 240, g: 32, b: 8)

    func testVolumeRampRunsGreenThroughYellowToRed() {
        XCTAssertEqual(AmpXSliderColorRamp.color(for: .volume, fraction: 0), self.green)
        XCTAssertEqual(AmpXSliderColorRamp.color(for: .volume, fraction: 0.5), self.yellow)
        XCTAssertEqual(AmpXSliderColorRamp.color(for: .volume, fraction: 1), self.red)

        let reference = AmpXSliderColorRamp.color(for: .volume, fraction: 0.762)
        XCTAssertGreaterThan(reference.r, reference.g, "Reference volume sits between yellow and red")
        XCTAssertLessThan(reference.g, self.yellow.g)
        XCTAssertGreaterThan(reference.g, self.red.g)
    }

    func testBalanceRampFollowsDistanceFromCenter() {
        XCTAssertEqual(AmpXSliderColorRamp.color(for: .balance, fraction: 0.5), self.green)
        XCTAssertEqual(AmpXSliderColorRamp.color(for: .balance, fraction: 0), self.red)
        XCTAssertEqual(AmpXSliderColorRamp.color(for: .balance, fraction: 1), self.red)
        XCTAssertEqual(
            AmpXSliderColorRamp.color(for: .balance, fraction: 0.25),
            AmpXSliderColorRamp.color(for: .balance, fraction: 0.75)
        )
        XCTAssertEqual(AmpXSliderColorRamp.color(for: .balance, fraction: 0.25), self.yellow)
    }

    func testRampClampsOutOfRangeFractions() {
        XCTAssertEqual(AmpXSliderColorRamp.color(for: .volume, fraction: -1), self.green)
        XCTAssertEqual(AmpXSliderColorRamp.color(for: .volume, fraction: 2), self.red)
    }

    func testDrawnVolumeTrackColorFollowsDisplayedValue() throws {
        let low = try self.fillColor(for: .volume, value: 0.1)
        let high = try self.fillColor(for: .volume, value: 0.95)
        XCTAssertGreaterThan(low.g, low.r, "Quiet volume should draw green")
        XCTAssertGreaterThan(high.r, high.g * 2, "Loud volume should draw red")

        let centered = try self.fillColor(for: .balance, value: 0.5)
        let panned = try self.fillColor(for: .balance, value: 0.98)
        XCTAssertGreaterThan(centered.g, centered.r, "Centered balance should draw green")
        XCTAssertGreaterThan(panned.r, panned.g * 2, "Panned balance should draw red")
    }

    func testRampColorCoversFullTrackLengthRegardlessOfThumb() throws {
        for fill: AmpXTrackFill in [.volume, .balance] {
            for value in [0.02, 0.5, 0.98] {
                let expected = AmpXSliderColorRamp.color(for: fill, fraction: value)
                // Sample only ends the thumb does not cover; the far end proves the fill ignores thumb position.
                var samples: [(String, AmpXRGB)] = []
                if value >= 0.5 {
                    try samples.append(("leading", self.fillColor(for: fill, value: value, atEnd: .leading)))
                }
                if value <= 0.5 {
                    try samples.append(("trailing", self.fillColor(for: fill, value: value, atEnd: .trailing)))
                }
                for (end, sample) in samples {
                    XCTAssertLessThan(
                        self.distance(sample, expected), 60,
                        "\(fill) at \(value): \(end) end \(sample) is not the ramp color \(expected)"
                    )
                }
            }
        }
    }

    func testDrawnEQTrackRunsFromGreenThroughYellowToRedAtMaximumGain() throws {
        var samples: [AmpXRGB] = []
        for gain in [-12.0, 0, 12] {
            let slider = AmpXSlider(skin: ClassicModernSkin())
            slider.frame = CGRect(x: 0, y: 0, width: 24, height: 120)
            slider.trackSize = CGSize(width: 12, height: 120)
            slider.isVertical = true
            slider.range = -12 ... 12
            slider.artwork = .level
            slider.displayValueOverride = gain
            let rep = try XCTUnwrap(slider.bitmapImageRepForCachingDisplay(in: slider.bounds))
            slider.cacheDisplay(in: slider.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / slider.bounds.width
            // Keep clear of the thumb at minimum, center, and maximum gain.
            let color = try XCTUnwrap(rep.colorAt(
                x: Int(slider.trackRect.midX * scale),
                y: Int(slider.trackRect.height * 0.3 * scale)
            )?.usingColorSpace(.sRGB))
            samples.append(AmpXRGB(r: color.redComponent * 255, g: color.greenComponent * 255, b: color.blueComponent * 255))
        }
        XCTAssertGreaterThan(samples[0].g, samples[0].r, "Cut gain should draw green")
        XCTAssertGreaterThan(samples[1].r, samples[1].b * 3, "Unity gain should draw yellow")
        XCTAssertGreaterThan(samples[1].g, samples[1].b * 3, "Unity gain should retain its green channel")
        XCTAssertGreaterThan(samples[2].r, samples[2].g * 4, "+12 dB should draw red, not orange")
        XCTAssertGreaterThan(samples[2].r, samples[2].b * 8, "+12 dB should draw red")
    }

    private enum TrackEnd {
        case leading
        case trailing
    }

    private func distance(_ a: AmpXRGB, _ b: AmpXRGB) -> CGFloat {
        abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
    }

    /// Samples the track 5 pt inside one end, on its center line.
    private func fillColor(for fill: AmpXTrackFill, value: Double, atEnd end: TrackEnd = .leading) throws -> AmpXRGB {
        let slider = AmpXSlider(skin: ClassicModernSkin())
        slider.frame = CGRect(x: 0, y: 0, width: 120, height: 24)
        slider.trackSize = CGSize(width: 120, height: AmpXMetrics.playerSliderTrackHeight)
        slider.artwork = .pill(fill)
        slider.displayValueOverride = value

        let rep = try XCTUnwrap(slider.bitmapImageRepForCachingDisplay(in: slider.bounds))
        slider.cacheDisplay(in: slider.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / slider.bounds.width
        let track = slider.trackRect
        let color = try XCTUnwrap(
            rep.colorAt(
                x: Int((end == .leading ? track.minX + 5 : track.maxX - 5) * scale),
                y: Int(track.midY * scale)
            )?.usingColorSpace(.sRGB)
        )
        return AmpXRGB(r: color.redComponent * 255, g: color.greenComponent * 255, b: color.blueComponent * 255)
    }
}
