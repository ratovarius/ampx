@testable import AmpX
import AppKit
import Combine
import XCTest

@MainActor
final class AmpXCompactEqualizerTests: XCTestCase {
    func testCompactEQAndExpandedPlayerControlsStaySynchronized() async throws {
        let player = self.makePlayer()
        let manager = PlaylistManager(
            audioPlayer: MockAudioPlayer(),
            restoreBookmarks: false,
            restorePlaylist: false,
            alertPresenter: SilentPlaylistAlertPresenter()
        )
        let expanded = PlayerModuleContent(
            skin: ClassicModernSkin(),
            audioPlayer: player,
            playlistManager: manager,
            onToggleModule: { _ in }
        )
        let compact = EqualizerCompactContent(skin: ClassicModernSkin(), audioPlayer: player)
        let volume = try XCTUnwrap(expanded.subviews.compactMap { $0 as? AmpXSlider }.first { $0.accessibilityTitle == "Volume" })
        compact.volumeSlider.setValue(0.27, sendChange: true)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        XCTAssertEqual(volume.value, 0.27, accuracy: 0.0001)
        volume.setValue(0.61, sendChange: true)
        XCTAssertEqual(compact.volumeSlider.value, 0.61, accuracy: 0.0001)
    }

    func testVolumeAndBalanceBindBothWaysWithoutChangingEqualization() {
        let player = self.makePlayer()
        let bands = player.eqBandValues
        let preamp = player.eqPreampValue
        let enabled = player.eqEnabled
        let auto = player.eqAutoEnabled
        let compact = EqualizerCompactContent(skin: ClassicModernSkin(), audioPlayer: player)
        for value in [0.0, 0.5, 1.0] {
            compact.volumeSlider.setValue(value, sendChange: true)
            compact.balanceSlider.setValue(value, sendChange: true)
            XCTAssertEqual(player.volume, Float(value), accuracy: 0.0001)
            XCTAssertEqual(player.balance, Float(value * 2 - 1), accuracy: 0.0001)
        }
        player.setVolume(0.32)
        player.setBalance(-0.7)
        XCTAssertEqual(compact.volumeSlider.value, 0.32, accuracy: 0.0001)
        XCTAssertEqual(compact.balanceSlider.value, 0.15, accuracy: 0.0001)
        XCTAssertEqual(player.eqBandValues, bands)
        XCTAssertEqual(player.eqPreampValue, preamp)
        XCTAssertEqual(player.eqEnabled, enabled)
        XCTAssertEqual(player.eqAutoEnabled, auto)
    }

    func testAccessibleIncrementsAndPointerMappingRemainContinuous() {
        let compact = EqualizerCompactContent(skin: ClassicModernSkin(), audioPlayer: self.makePlayer())
        compact.frame = CGRect(x: 0, y: 0, width: 490, height: AmpXCompactMetrics.equalizerHeight)
        compact.layoutSubtreeIfNeeded()
        XCTAssertNil(compact.minimizeButton)
        for slider in [compact.volumeSlider, compact.balanceSlider] {
            XCTAssertTrue(slider.isAccessibilityElement())
            XCTAssertEqual(slider.step, 0)
            slider.setValue(0.333, sendChange: true)
            XCTAssertEqual(slider.value, 0.333, accuracy: 0.0001)
            XCTAssertEqual(slider.value(at: CGPoint(x: slider.thumbRect.midX, y: slider.thumbRect.midY)), 0.333, accuracy: 0.0001)
            XCTAssertTrue(slider.accessibilityPerformIncrement())
            XCTAssertEqual(slider.value, 0.383, accuracy: 0.0001)
            XCTAssertTrue(slider.accessibilityPerformDecrement())
            XCTAssertEqual(slider.value, 0.333, accuracy: 0.0001)
            XCTAssertTrue(compact.bounds.contains(slider.frame))
            XCTAssertGreaterThan(slider.frame.width, 0)
            slider.isEnabled = false
            let point = CGPoint(x: slider.frame.midX, y: slider.frame.midY)
            XCTAssertIdentical(compact.hitTest(point), compact)
            XCTAssertTrue(compact.protectedRects.contains { $0.contains(point) })
        }
        compact.balanceSlider.setValue(0.5, sendChange: true)
        XCTAssertEqual(compact.balanceSlider.accessibilityValue() as? String, "Center")
        compact.volumeSlider.setValue(0.5, sendChange: true)
        XCTAssertEqual(compact.volumeSlider.accessibilityValue() as? String, "50%")
        XCTAssertEqual(compact.balanceSlider.accessibilityMinValue() as? Double, -100)
        XCTAssertEqual(compact.balanceSlider.accessibilityMaxValue() as? Double, 100)
    }

    func testTrackPixelsFillToThumbAndRetainDarkRemainder() throws {
        for fill in [AmpXTrackFill.volume, .balance] {
            let slider = AmpXSlider(skin: ClassicModernSkin())
            slider.frame = CGRect(x: 0, y: 0, width: 160, height: 22)
            slider.trackSize = CGSize(width: 150, height: 8)
            slider.thumbSize = CGSize(width: 16, height: 16)
            slider.artwork = .compact(fill)
            for value in [0.0, 0.5, 1.0] {
                slider.value = value
                let png = try AmpXCompactCaptureSupport.capture(slider, scale: 2)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
                var litLeft = 0
                var litRight = 0
                for x in 50 ..< 260 {
                    let c = try XCTUnwrap(bitmap.colorAt(x: x, y: 22)?.usingColorSpace(.sRGB))
                    let lit: Bool = switch fill {
                    case .volume: c.redComponent > 0.8 && c.greenComponent > 0.25 && c.blueComponent < 0.15
                    case .balance: c.greenComponent > 0.7 && c.blueComponent < 0.15
                    }
                    if lit {
                        if x < 130 {
                            litLeft += 1
                        }
                        if x > 190 {
                            litRight += 1
                        }
                    }
                }
                if value == 0 {
                    XCTAssertEqual(litLeft + litRight, 0)
                }
                if value > 0 {
                    XCTAssertGreaterThan(litLeft, 20)
                }
                if value < 1 {
                    XCTAssertEqual(litRight, 0)
                }
                if value == 1 {
                    XCTAssertGreaterThan(litRight, 20)
                }
                let thumb = try XCTUnwrap(bitmap.colorAt(x: Int((slider.thumbRect.minX + 3) * 2), y: 20)?.usingColorSpace(.sRGB))
                XCTAssertGreaterThan(thumb.blueComponent, 0.25, "Thumb must have a visible steel face")
            }
        }
    }

    private func makePlayer() -> AudioPlayer {
        let suite = "AmpXCompactEqualizerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        self.addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return AudioPlayer(
            installRemoteCommands: false,
            eqSettingsStore: EQSettingsStore(userDefaults: defaults, settingsKey: "settings", presetsKey: "presets")
        )
    }
}
