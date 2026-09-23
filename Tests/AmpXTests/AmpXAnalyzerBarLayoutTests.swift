@testable import AmpX
import XCTest

/// The analyzer draws one thin continuous bar per analysis band with a floating peak cap, so its
/// geometry is independent of the segmented column grid the bars mode uses.
final class AmpXAnalyzerBarLayoutTests: XCTestCase {
    private let area = CGRect(x: 33, y: 57, width: 137.5, height: 41)

    func testOneBarPerAnalysisBand() {
        let bars = AmpXAnalyzerBarLayout.bars(
            levels: [Float](repeating: 0.5, count: AudioFeatures.spectrumBandCount),
            in: self.area
        )

        XCTAssertEqual(bars.count, AudioFeatures.spectrumBandCount)
    }

    func testBarsSpanTheAreaLeftToRightWithoutOverlapping() throws {
        let bars = AmpXAnalyzerBarLayout.bars(
            levels: [Float](repeating: 1, count: AudioFeatures.spectrumBandCount),
            in: self.area
        )

        try XCTSkipIf(bars.count < 2)
        XCTAssertEqual(bars[0].minX, self.area.minX, accuracy: 0.001)
        XCTAssertLessThanOrEqual(bars[bars.count - 1].maxX, self.area.maxX + 0.001)
        for index in 1 ..< bars.count {
            XCTAssertGreaterThanOrEqual(bars[index].minX, bars[index - 1].maxX - 0.001, "bars must not overlap")
        }
        XCTAssertGreaterThan(bars[0].width, 1, "a bar narrower than a point would vanish")
    }

    /// Flipped AppKit coordinates: a bar grows upward from the bottom of the area.
    func testBarsGrowUpwardFromTheBottom() throws {
        let quiet = try XCTUnwrap(AmpXAnalyzerBarLayout.bars(
            levels: [Float](repeating: 0.25, count: AudioFeatures.spectrumBandCount),
            in: self.area
        ).first)
        let loud = try XCTUnwrap(AmpXAnalyzerBarLayout.bars(
            levels: [Float](repeating: 1, count: AudioFeatures.spectrumBandCount),
            in: self.area
        ).first)

        XCTAssertEqual(quiet.maxY, self.area.maxY, accuracy: 0.001)
        XCTAssertEqual(loud.maxY, self.area.maxY, accuracy: 0.001)
        XCTAssertEqual(loud.minY, self.area.minY, accuracy: 0.001, "full scale reaches the top")
        XCTAssertGreaterThan(quiet.minY, loud.minY)
    }

    func testSilentBarsStayVisibleAsAFloorLine() throws {
        let bars = AmpXAnalyzerBarLayout.bars(
            levels: [Float](repeating: 0, count: AudioFeatures.spectrumBandCount),
            in: self.area
        )

        let first = try XCTUnwrap(bars.first)
        XCTAssertGreaterThan(first.height, 0)
        XCTAssertLessThanOrEqual(first.height, 1)
    }

    func testCapsFloatAtThePeakAndShareTheBarWidth() throws {
        let levels = [Float](repeating: 0.2, count: AudioFeatures.spectrumBandCount)
        let peaks = [Float](repeating: 0.8, count: AudioFeatures.spectrumBandCount)
        let bars = AmpXAnalyzerBarLayout.bars(levels: levels, in: self.area)
        let caps = AmpXAnalyzerBarLayout.caps(peaks: peaks, in: self.area)

        XCTAssertEqual(caps.count, bars.count)
        let cap = try XCTUnwrap(caps.first)
        let bar = try XCTUnwrap(bars.first)
        XCTAssertEqual(cap.minX, bar.minX, accuracy: 0.001)
        XCTAssertEqual(cap.width, bar.width, accuracy: 0.001)
        XCTAssertLessThan(cap.maxY, bar.minY, "the cap floats above the bar it belongs to")
        XCTAssertGreaterThanOrEqual(cap.minY, self.area.minY - 0.001)
    }

    func testFullScaleCapStaysInsideTheArea() throws {
        let caps = AmpXAnalyzerBarLayout.caps(
            peaks: [Float](repeating: 1, count: AudioFeatures.spectrumBandCount),
            in: self.area
        )

        let cap = try XCTUnwrap(caps.first)
        XCTAssertGreaterThanOrEqual(cap.minY, self.area.minY - 0.001)
        XCTAssertLessThanOrEqual(cap.maxY, self.area.maxY + 0.001)
    }

    /// Colour comes from the shared segment palette, so the analyzer reads as the same instrument
    /// family as the bars mode.
    func testColourRisesThroughThePaletteWithLevel() {
        XCTAssertEqual(AmpXAnalyzerBarLayout.paletteIndex(forLevel: 0, count: 6), 0)
        XCTAssertEqual(AmpXAnalyzerBarLayout.paletteIndex(forLevel: 1, count: 6), 5)
        XCTAssertLessThan(
            AmpXAnalyzerBarLayout.paletteIndex(forLevel: 0.2, count: 6),
            AmpXAnalyzerBarLayout.paletteIndex(forLevel: 0.9, count: 6)
        )
    }
}
