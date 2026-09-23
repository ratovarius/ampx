@testable import AmpX
import AppKit
import XCTest

extension AmpXReferenceRenderingTests {
    func testCompactPlaylistCapturesAtAllScalesAndWidths() throws {
        let audio = AudioPlayer(installRemoteCommands: false)
        let manager = PlaylistManager(
            audioPlayer: MockAudioPlayer(),
            restoreBookmarks: false,
            restorePlaylist: false,
            alertPresenter: SilentPlaylistAlertPresenter()
        )
        let owner = PlaylistListOptionsMenu(manager: manager, keyboardAdapter: PlaylistKeyboardAdapter(manager: manager))
        let view = PlaylistCompactContent(skin: ClassicModernSkin(), manager: manager, audioPlayer: audio, listOptionsMenu: owner)
        view.referencePresentation = .init(title: "7. SLEAZE - GOD DAMN", duration: "3:46")
        for width: CGFloat in [490, 800] {
            view.frame = CGRect(x: 0, y: 0, width: width, height: AmpXCompactMetrics.playlistHeight)
            for scale: CGFloat in [1, 2, 3] {
                let png = try AmpXCompactCaptureSupport.capture(view, scale: scale)
                XCTAssertEqual(png, try AmpXCompactCaptureSupport.capture(view, scale: scale))
                let suffix = width == 490 ? "" : "-wide"
                try self.export(png, named: "compact-playlist\(suffix)-\(Int(scale))x.png", backingScale: scale)
            }
        }
        view.referencePresentation = .init(title: "1000. Björk - " + String(repeating: "東京🎵 café ", count: 20), duration: "100:00:01")
        try self.export(AmpXCompactCaptureSupport.capture(view, scale: 2), named: "compact-playlist-long-2x.png", backingScale: 2)
    }

    func testCompactEqualizerCapturesAtAllScales() throws {
        let audio = AudioPlayer(installRemoteCommands: false)
        let equalizer = EqualizerCompactContent(skin: ClassicModernSkin(), audioPlayer: audio)
        equalizer.frame = CGRect(x: 0, y: 0, width: 490, height: AmpXCompactMetrics.equalizerHeight)
        equalizer.volumeSlider.displayValueOverride = 0.7
        equalizer.balanceSlider.displayValueOverride = 0.7
        for scale: CGFloat in [1, 2, 3] {
            let png = try AmpXCompactCaptureSupport.capture(equalizer, scale: scale)
            XCTAssertEqual(png, try AmpXCompactCaptureSupport.capture(equalizer, scale: scale))
            try self.export(png, named: "compact-equalizer-\(Int(scale))x.png", backingScale: scale)
        }
    }

    func testCompactPlayerProductionCapturesAreDeterministic() throws {
        let suite = "AmpXCompactCapture.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AmpXPlayerPresentationState(store: .init(defaults: defaults))
        let audio = AudioPlayer(installRemoteCommands: false)
        let playlist = PlaylistManager(
            audioPlayer: MockAudioPlayer(),
            restoreBookmarks: false,
            restorePlaylist: false,
            alertPresenter: SilentPlaylistAlertPresenter()
        )
        let player = PlayerCompactContent(
            skin: ClassicModernSkin(),
            audioPlayer: audio,
            playlistManager: playlist,
            presentationState: state,
            onToggleModule: { _ in }
        )
        player.frame = CGRect(x: 0, y: 0, width: 490, height: AmpXCompactMetrics.playerHeight)
        player.timeDisplay.referenceText = "01:51"
        player.transportButtons[1].displayActiveOverride = true
        let settings = AmpXMiniVisualizerSettings(style: .dotSpectrum, palette: .classic)
        for scale: CGFloat in [1, 2, 3] {
            let first = try AmpXCompactCaptureSupport.capture(
                player,
                scale: scale,
                visualizer: player.spectrumWell,
                frame: AmpXCompactCaptureSupport.signal,
                settings: settings
            )
            let second = try AmpXCompactCaptureSupport.capture(
                player,
                scale: scale,
                visualizer: player.spectrumWell,
                frame: AmpXCompactCaptureSupport.signal,
                settings: settings
            )
            XCTAssertEqual(first, second)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: first))
            let rect = player.spectrumWell.frame
            var greenPixels = 0
            for y in Int(rect.minY * scale) ..< Int(rect.maxY * scale) {
                for x in Int(rect.minX * scale) ..< Int(rect.maxX * scale) {
                    let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    if color.greenComponent > 0.4, color.blueComponent < 0.2 {
                        greenPixels += 1
                    }
                }
            }
            XCTAssertGreaterThan(greenPixels, 20, "Composited spectrum must contain the supplied signal")
            try self.export(first, named: "compact-player-\(Int(scale))x.png", backingScale: scale)
        }
        XCTAssertNil(defaults.string(forKey: "miniVisualizer.style"), "Capture choices must not persist")
    }
}
