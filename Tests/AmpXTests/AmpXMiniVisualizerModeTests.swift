@testable import AmpX
import XCTest

/// Classic behavior: clicking the mini visualizer cycles its modes and the choice persists;
/// double-clicking opens the visualizer instead. Peak marks belong to the analyzer mode only.
@MainActor
final class AmpXMiniVisualizerModeTests: XCTestCase {
    /// Each mode owns a distinct drawing: segmented columns with an afterglow, a waveform line, or
    /// thin per-band bars with floating caps.
    func testEachModeDrawsItsOwnLook() {
        XCTAssertTrue(SpectrumWellView.drawsTrail(in: .bars))
        XCTAssertFalse(SpectrumWellView.drawsAnalyzerBars(in: .bars))
        XCTAssertFalse(SpectrumWellView.drawsScopeLine(in: .bars))

        XCTAssertTrue(SpectrumWellView.drawsScopeLine(in: .oscilloscope))
        XCTAssertFalse(SpectrumWellView.drawsTrail(in: .oscilloscope))
        XCTAssertFalse(SpectrumWellView.drawsAnalyzerBars(in: .oscilloscope))

        XCTAssertTrue(SpectrumWellView.drawsAnalyzerBars(in: .analyzer))
        XCTAssertFalse(SpectrumWellView.drawsTrail(in: .analyzer))
        XCTAssertFalse(SpectrumWellView.drawsScopeLine(in: .analyzer))
    }

    /// The mode must change on the click itself. Deferring it until AppKit can no longer make a
    /// double-click out of it made every cycle wait a full `doubleClickInterval`, which reads as
    /// "clicking does nothing".
    func testClickCyclesToTheNextModeImmediately() {
        let well = SpectrumWellView(skin: ClassicModernSkin())
        well.settings.style = .classicSpectrum
        var reported: [AmpXMiniVisualizerStyle] = []
        well.onSettingsChanged = { reported.append($0.style) }

        well.mouseDown(with: self.click(count: 1))

        XCTAssertEqual(well.settings.style, .smoothSpectrum)
        XCTAssertEqual(reported, [.smoothSpectrum])
    }

    func testEverySingleClickAdvancesOneMode() {
        let well = SpectrumWellView(skin: ClassicModernSkin())
        well.settings.style = .classicSpectrum

        well.mouseDown(with: self.click(count: 1))
        XCTAssertEqual(well.settings.style, .smoothSpectrum)

        well.mouseDown(with: self.click(count: 1))
        XCTAssertEqual(well.settings.style, .dotSpectrum)

        well.mouseDown(with: self.click(count: 1))
        XCTAssertEqual(well.settings.style, .mirroredSpectrum)
    }

    /// The first click of a double-click already advanced the mode, so the second click undoes it —
    /// opening the visualizer still never leaves the mode changed.
    func testDoubleClickOpensVisualizerAndLeavesTheModeUnchanged() {
        let well = SpectrumWellView(skin: ClassicModernSkin())
        well.settings.style = .waterfall
        var opened = 0
        var reported: [AmpXMiniVisualizerStyle] = []
        well.onDoubleClick = { opened += 1 }
        well.onSettingsChanged = { reported.append($0.style) }

        // AppKit delivers the first click of a double-click as clickCount 1.
        well.mouseDown(with: self.click(count: 1))
        well.mouseDown(with: self.click(count: 2))

        XCTAssertEqual(opened, 1)
        XCTAssertEqual(well.settings.style, .waterfall)
        XCTAssertEqual(reported.last, .waterfall, "the revert must be persisted too")
    }

    /// A parked well gets no ticks, so a mode the user just picked would draw stale or empty state.
    func testCyclingTheModeWakesAParkedWell() {
        let well = SpectrumWellView(skin: ClassicModernSkin())
        well.setEffectivelyVisible(true)
        well.setContinuousRenderingPaused(true)

        well.mouseDown(with: self.click(count: 1))

        XCTAssertFalse(well.isContinuousRenderingPaused)
    }

    /// Waking must also drop the stale frame time: without it the first frame after a park spans the
    /// whole parked interval, and that delta runs the smoothing and falloff to their extremes.
    func testWakingClearsTheStaleFrameTimestamp() {
        let well = SpectrumWellView(skin: ClassicModernSkin())
        well.audioSource = { _ in AmpXMiniAudioSnapshot() }
        well.tick(at: 100)

        XCTAssertEqual(well.lastTimestamp, 100)

        well.wakeRendering()

        XCTAssertNil(well.lastTimestamp)
    }

    func testModeStoreDefaultsToBarsAndRoundTrips() throws {
        let suite = "AmpXMiniVisualizerModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        self.addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let store = AmpXMiniVisualizerModeStore(defaults: defaults)

        XCTAssertEqual(store.load(), .bars)

        store.save(.analyzer)

        XCTAssertEqual(store.load(), .analyzer)
        XCTAssertEqual(
            defaults.integer(forKey: "visualizationMode"),
            VisualizationMode.analyzer.storageValue,
            "must reuse the key the SwiftUI player stored, so an existing choice carries over"
        )
    }

    private func click(count: Int) -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: CGPoint(x: 40, y: 20),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: count,
            pressure: 1
        )!
    }
}
