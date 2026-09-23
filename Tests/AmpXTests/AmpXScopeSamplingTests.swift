@testable import AmpX
import XCTest

@MainActor
final class AmpXScopeSamplingTests: XCTestCase {
    private let width: CGFloat = 137.5

    func testScopeLineDrawsOnlyInOscilloscopeMode() {
        XCTAssertTrue(SpectrumWellView.drawsScopeLine(in: .oscilloscope))
        XCTAssertFalse(SpectrumWellView.drawsScopeLine(in: .bars))
        XCTAssertFalse(SpectrumWellView.drawsScopeLine(in: .analyzer))
    }

    func testScopeLevelsGiveOnePerPolylinePoint() {
        let waveform = (0 ..< AudioFeatures.scopeWaveformSampleCount).map { Float(sin(Double($0) * 0.01)) }

        let levels = SpectrumWellView.scopeLevels(fromWaveform: waveform, width: self.width)

        XCTAssertEqual(levels.count, AmpXScopeLineLayout.columnCount(forWidth: self.width))
    }

    func testSilenceSitsAtZeroAmplitude() {
        let levels = SpectrumWellView.scopeLevels(
            fromWaveform: Array(repeating: 0, count: AudioFeatures.scopeWaveformSampleCount),
            width: self.width
        )

        XCTAssertFalse(levels.isEmpty)
        XCTAssertTrue(levels.allSatisfy { abs($0) < 0.001 }, "a silent waveform must draw flat through the centre")
    }

    func testFullScaleSampleReachesAnEdge() throws {
        let levels = SpectrumWellView.scopeLevels(
            fromWaveform: Array(repeating: 1, count: AudioFeatures.scopeWaveformSampleCount),
            width: self.width
        )

        XCTAssertFalse(levels.isEmpty)
        try XCTSkipIf(levels.isEmpty)
        XCTAssertEqual(abs(levels[0]), 1, accuracy: 0.001)
    }
}
