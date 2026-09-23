@testable import AmpX
import AppKit
import XCTest

@MainActor
final class AmpXMiniVisualizerIntegrationTests: XCTestCase {
    func testEightStylesCycleAndDoubleClickRestoresSelection() throws {
        let well = SpectrumWellView(skin: ClassicModernSkin())
        well.settings = AmpXMiniVisualizerSettings(style: .classicSpectrum, palette: .classic)
        let expected: [AmpXMiniVisualizerStyle] = [
            .smoothSpectrum, .dotSpectrum, .mirroredSpectrum, .lineWaveform,
            .waterfall, .particleWaveform, .stereoBars, .classicSpectrum,
        ]
        for style in expected {
            try well.mouseDown(with: self.click(1))
            XCTAssertEqual(well.settings.style, style)
            XCTAssertEqual(well.settings.palette, .classic)
        }
        var opened = 0
        well.onDoubleClick = { opened += 1 }
        try well.mouseDown(with: self.click(1))
        try well.mouseDown(with: self.click(2))
        XCTAssertEqual(well.settings.style, .classicSpectrum)
        XCTAssertEqual(opened, 1)
    }

    func testPaletteChangePreservesPreparedHistoryAndReportsSettings() {
        let well = SpectrumWellView(skin: ClassicModernSkin())
        well.audioSource = { time in
            AmpXMiniAudioSnapshot(
                sequence: 1,
                time: time,
                spectrum: [Float](repeating: 0.7, count: 32),
                isPlaying: true
            )
        }
        well.tick(at: 1)
        let history = well.preparedFrame.history
        var changes: [AmpXMiniVisualizerSettings] = []
        well.onSettingsChanged = { changes.append($0) }
        well.selectPalette(.classic)
        XCTAssertEqual(well.preparedFrame.history, history)
        XCTAssertEqual(changes.map(\.palette), [.classic])
        XCTAssertEqual(well.accessibilityValue() as? String, "Classic Spectrum, Classic")
    }

    func testMenuReflectsSelectionsAndStyleChangeWakesParkedHost() {
        let well = SpectrumWellView(skin: ClassicModernSkin())
        well.frame = CGRect(x: 0, y: 0, width: 180, height: 100)
        well.audioSource = { _ in AmpXMiniAudioSnapshot() }
        well.tick(at: 1)
        well.tick(at: 3)
        XCTAssertTrue(well.isContinuousRenderingPaused)
        well.selectStyle(.waterfall)
        well.selectPalette(.classic)
        let menu = well.makeContextMenu()
        XCTAssertEqual(menu.items.filter { $0.representedObject is AmpXMiniVisualizerStyle }.count, 8)
        XCTAssertEqual(menu.items.first { $0.title == "Waterfall" }?.state, .on)
        XCTAssertEqual(menu.items.last?.submenu?.items.first { $0.title == "Classic" }?.state, .on)
        XCTAssertFalse(well.isContinuousRenderingPaused)
    }

    func testAccessiblePaletteActionVisitsEveryPaletteAndPersistsSelection() throws {
        let well = SpectrumWellView(skin: ClassicModernSkin())
        var selected: [AmpXMiniVisualizerPalette] = []
        well.onSettingsChanged = { selected.append($0.palette) }
        let action = try XCTUnwrap(well.accessibilityCustomActions()?.first { $0.name == "Next palette" })
        let target = try XCTUnwrap(action.target as? NSObject)
        for palette in [AmpXMiniVisualizerPalette.classic, .red, .green, .amber, .blue] {
            _ = target.perform(action.selector)
            XCTAssertEqual(well.settings.palette, palette)
        }
        XCTAssertEqual(selected, [.classic, .red, .green, .amber, .blue])
    }

    func testPauseAndResumeWhileHiddenPreserveWaterfallHistory() {
        let well = SpectrumWellView(skin: ClassicModernSkin())
        well.settings.style = .waterfall
        var snapshot = AmpXMiniAudioSnapshot(isPlaying: true)
        well.audioSource = { _ in snapshot }
        for index in 0 ... 128 {
            snapshot.sequence = UInt64(index + 1)
            snapshot.time = Double(index) / 32
            snapshot.spectrum = [Float](repeating: 0.25, count: 32)
            well.tick(at: snapshot.time)
        }
        let history = well.preparedFrame.history
        XCTAssertTrue(history.allSatisfy { $0 == 0.25 })
        well.setEffectivelyVisible(false)
        // Hidden playback notifications must reach the state without requiring display ticks.
        well.playbackStateDidChange(isPlaying: false)
        well.playbackStateDidChange(isPlaying: true)
        snapshot.sequence += 1
        snapshot.time = 15
        snapshot.spectrum = [Float](repeating: 0.75, count: 32)
        well.tick(at: 15)
        XCTAssertEqual(well.preparedFrame.history, history)
        snapshot.sequence += 1
        snapshot.time += 1.0 / 32
        well.tick(at: snapshot.time)
        XCTAssertEqual(Array(well.preparedFrame.history.suffix(32)), snapshot.spectrum)
        XCTAssertEqual(Array(well.preparedFrame.history.dropLast(32)), Array(history.dropFirst(32)))
    }

    private func click(_ count: Int) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: count,
            pressure: 1
        ))
    }
}
