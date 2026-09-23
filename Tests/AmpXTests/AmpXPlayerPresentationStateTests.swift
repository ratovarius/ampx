@testable import AmpX
import AppKit
import Combine
import XCTest

@MainActor
final class AmpXPlayerPresentationStateTests: XCTestCase {
    func testTwoTimerViewsShareTheModeInBothDirections() {
        let state = AmpXPlayerPresentationState(store: self.makeStore())
        let first = TimeDisplayView(skin: ClassicModernSkin(), presentationState: state)
        let second = TimeDisplayView(skin: ClassicModernSkin(), presentationState: state)
        first.showRemainingTime = true
        XCTAssertTrue(second.showRemainingTime)
        second.showRemainingTime = false
        XCTAssertFalse(first.showRemainingTime)
    }

    func testAttachingPlayerPreservesSavedStyleAndPalette() {
        let store = self.makeStore()
        let settings = AmpXMiniVisualizerSettings(style: .waterfall, palette: .amber)
        store.save(settings)
        let state = AmpXPlayerPresentationState(store: store)
        let player = PlayerModuleContent(
            skin: ClassicModernSkin(),
            audioPlayer: AudioPlayer(installRemoteCommands: false),
            playlistManager: PlaylistManager(
                audioPlayer: MockAudioPlayer(),
                restoreBookmarks: false,
                restorePlaylist: false,
                alertPresenter: SilentPlaylistAlertPresenter()
            ),
            onToggleModule: { _ in },
            presentationState: state
        )
        XCTAssertEqual(player.spectrumWell.settings, settings)
        XCTAssertEqual(store.load(), settings)
        let changed = AmpXMiniVisualizerSettings(style: .dotSpectrum, palette: .green)
        state.setVisualizerSettings(changed)
        XCTAssertEqual(player.spectrumWell.settings, changed)
        player.spectrumWell.onSettingsChanged?(settings)
        XCTAssertEqual(state.visualizerSettings, settings)
    }

    func testDuplicateSettingsDoNotPublishAndChangingStylePreservesTimerMode() {
        let store = self.makeStore()
        let state = AmpXPlayerPresentationState(store: store)
        XCTAssertFalse(state.showRemainingTime)
        state.toggleTimeMode()
        var observed: [AmpXMiniVisualizerSettings] = []
        let subscription = state.$visualizerSettings.dropFirst().sink { observed.append($0) }
        let changed = AmpXMiniVisualizerSettings(style: .particleWaveform, palette: .red)
        state.setVisualizerSettings(changed)
        state.setVisualizerSettings(changed)
        XCTAssertEqual(observed, [changed])
        XCTAssertEqual(store.load(), changed)
        XCTAssertTrue(state.showRemainingTime)
        withExtendedLifetime(subscription) {}
    }

    private func makeStore() -> AmpXMiniVisualizerSettingsStore {
        let suite = "AmpXPlayerPresentationStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        self.addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return AmpXMiniVisualizerSettingsStore(defaults: defaults)
    }
}
