@testable import AmpX
import AppKit
import XCTest

extension AmpXReferenceRenderingTests {
    func testCompactCompositionCaptureMatrix() throws {
        for name in ["compact", "mixed", "wide", "right"] {
            var state = AmpXModuleState()
            state.collapsed = [.player, .equalizer, .playlist]
            if name == "mixed" {
                state.collapsed.remove(.equalizer)
            }
            if name == "right" {
                state.reopen(.enthea)
            }
            let width: CGFloat = name == "wide" ? 800 : 490
            let audio = AudioPlayer(installRemoteCommands: false)
            let coordinator = AmpXHostCoordinator(
                state: state, skin: ClassicModernSkin(), layoutStore: makeIsolatedLayoutStore(), audioPlayer: audio,
                playlistManager: PlaylistManager(
                    audioPlayer: MockAudioPlayer(),
                    restoreBookmarks: false,
                    restorePlaylist: false,
                    alertPresenter: SilentPlaylistAlertPresenter()
                ),
                entheaEnabled: true
            )
            let views = Dictionary(uniqueKeysWithValues: AmpXModuleID.allCases.compactMap { id in
                coordinator.moduleView(for: id).map { (id, $0) }
            })
            let player = try XCTUnwrap(views[.player]?.compactContent as? PlayerCompactContent)
            player.timeDisplay.referenceText = name == "wide" ? "-100:00:00" : "01:51"
            player.transportButtons[1].displayActiveOverride = true
            (views[.player]?.content as? PlayerModuleContent)?.referencePresentation = Self.playerReference
            (views[.equalizer]?.content as? EqualizerModuleContent)?.referencePresentation = Self.equalizerReference
            let eq = try XCTUnwrap(views[.equalizer]?.compactContent as? EqualizerCompactContent)
            eq.volumeSlider.displayValueOverride = 0.7
            eq.balanceSlider.displayValueOverride = 0.7
            (views[.playlist]?.compactContent as? PlaylistCompactContent)?.referencePresentation = .init(
                title: "7. SLEAZE - GOD DAMN",
                duration: "3:46"
            )
            let layout = ReferenceStackView.defaultComposition(state: state, playlistViewportHeight: 180, playlistWidth: width)
            let stack = ReferenceStackView(frame: CGRect(origin: .zero, size: layout.size))
            for (id, frame) in layout.frames {
                guard let view = views[id] else { continue }
                stack.addSubview(view)
                view.applyLayout(frame: frame)
            }
            (views[.playlist]?.content as? PlaylistModuleContent)?.setRowViewportHeight(180)
            for scale: CGFloat in [1, 2, 3] {
                let png = try AmpXCompactCaptureSupport.capture(
                    stack,
                    scale: scale,
                    visualizer: player.spectrumWell,
                    frame: AmpXCompactCaptureSupport.signal,
                    settings: .init(style: .dotSpectrum, palette: .classic)
                )
                try self.export(png, named: "matrix-\(name)-\(Int(scale))x.png", backingScale: scale)
            }
        }
    }
}
