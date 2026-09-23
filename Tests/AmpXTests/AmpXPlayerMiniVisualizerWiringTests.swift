@testable import AmpX
import XCTest

/// The Player owns the mini visualizer's persistence and its double-click target.
@MainActor
final class AmpXPlayerMiniVisualizerWiringTests: XCTestCase {
    func testPlayerStartsInThePersistedModeAndSavesEveryChange() {
        let defaults = self.makeDefaults()
        defaults.set(VisualizationMode.analyzer.storageValue, forKey: AmpXMiniVisualizerModeStore.key)
        let content = self.makeContent(defaults: defaults)

        XCTAssertEqual(content.spectrumWell.settings.style, .classicSpectrum)

        content.spectrumWell.mouseDown(with: self.click(count: 1))

        XCTAssertEqual(content.spectrumWell.settings.style, .smoothSpectrum)
        XCTAssertEqual(defaults.string(forKey: "miniVisualizer.style"), "smoothSpectrum")
        XCTAssertEqual(defaults.integer(forKey: AmpXMiniVisualizerModeStore.key), 2)
    }

    func testDoubleClickingTheWellTogglesTheVisualizerModuleAndKeepsTheStoredMode() {
        var toggled: [AmpXModuleID] = []
        let defaults = self.makeDefaults()
        let content = self.makeContent(defaults: defaults) { toggled.append($0) }

        content.spectrumWell.mouseDown(with: self.click(count: 1))
        content.spectrumWell.mouseDown(with: self.click(count: 2))

        XCTAssertEqual(toggled, [.enthea])
        XCTAssertEqual(content.spectrumWell.settings.style, .classicSpectrum)
        XCTAssertEqual(defaults.string(forKey: "miniVisualizer.style"), "classicSpectrum")
        XCTAssertNil(defaults.object(forKey: AmpXMiniVisualizerModeStore.key))
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "AmpXPlayerMiniVisualizerWiringTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        self.addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func makeContent(
        defaults: UserDefaults,
        onToggleModule: @escaping (AmpXModuleID) -> Void = { _ in }
    ) -> PlayerModuleContent {
        PlayerModuleContent(
            skin: ClassicModernSkin(),
            audioPlayer: AudioPlayer(installRemoteCommands: false),
            playlistManager: PlaylistManager(
                audioPlayer: MockAudioPlayer(),
                restoreBookmarks: false,
                restorePlaylist: false,
                alertPresenter: SilentPlaylistAlertPresenter()
            ),
            onToggleModule: onToggleModule,
            settingsStore: AmpXMiniVisualizerSettingsStore(defaults: defaults)
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
