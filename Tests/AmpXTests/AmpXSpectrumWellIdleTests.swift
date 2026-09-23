@testable import AmpX
import XCTest

/// The spectrum well must stop redrawing once playback stops and the bars have decayed, then draw
/// again when it is woken. Mirrors the Metal mini visualizer's idle behavior on `develop`.
///
/// The injected source keeps these deterministic: the shared `AudioFeatureBus` is a singleton that a
/// playing `AudioPlayer` updates from its audio thread, so reading it here would race the suite.
@MainActor
final class AmpXSpectrumWellIdleTests: XCTestCase {
    func testWellParksItselfAfterSilenceDecays() {
        let well = self.makeSilentWell()

        self.tick(well, seconds: 2)

        XCTAssertTrue(well.isContinuousRenderingPaused)
    }

    func testWokenWellKeepsRenderingWhileAudioPlays() {
        let well = self.makeSilentWell()
        self.tick(well, seconds: 2)
        XCTAssertTrue(well.isContinuousRenderingPaused)

        well.audioSource = { _ in
            AmpXMiniAudioSnapshot(spectrum: Array(repeating: 0.8, count: 32), isPlaying: true)
        }
        well.wakeRendering()
        self.tick(well, seconds: 0.5)

        XCTAssertFalse(well.isContinuousRenderingPaused)
    }

    private func makeSilentWell() -> SpectrumWellView {
        let well = SpectrumWellView(skin: ClassicModernSkin())
        well.audioSource = { _ in AmpXMiniAudioSnapshot() }
        well.setEffectivelyVisible(true)
        return well
    }

    private func tick(_ well: SpectrumWellView, seconds: TimeInterval) {
        let step = 1.0 / 60.0
        var time: TimeInterval = 0
        while time < seconds {
            time += step
            well.tick(at: time)
        }
    }
}
