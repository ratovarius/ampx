@testable import AmpX
import AppKit
import XCTest

@MainActor
final class AmpXCompactPlayerTests: XCTestCase {
    func testFiveTransportButtonsCallOnlyTheirCorrespondingModelAction() {
        for index in 0 ..< 5 {
            let audio = CompactAudioSpy(installRemoteCommands: false)
            let playlist = CompactPlaylistSpy(
                audioPlayer: MockAudioPlayer(),
                restoreBookmarks: false,
                restorePlaylist: false,
                alertPresenter: SilentPlaylistAlertPresenter()
            )
            let player = self.makePlayer(audio: audio, playlist: playlist)
            player.transportButtons[index].action?()
            XCTAssertEqual(
                [playlist.previousCount, audio.playCount, audio.pauseCount, audio.stopCount, playlist.nextCount],
                (0 ..< 5).map { $0 == index ? 1 : 0 }
            )
        }
    }

    func testMeasuredControlsStayInsideTheirCellsAndCannotOverlapChrome() throws {
        let audio = CompactAudioSpy(installRemoteCommands: false)
        let playlist = CompactPlaylistSpy(
            audioPlayer: MockAudioPlayer(),
            restoreBookmarks: false,
            restorePlaylist: false,
            alertPresenter: SilentPlaylistAlertPresenter()
        )
        let player = self.makePlayer(audio: audio, playlist: playlist)
        let layout = AmpXCompactMetrics.playerLayout()
        let buttons = try player.transportButtons + [XCTUnwrap(player.minimizeButton), player.expandButton, player.closeButton]
        for button in buttons {
            XCTAssertTrue(button.isAccessibilityElement(), "Compact transport must be discoverable by assistive tools")
            XCTAssertTrue(player.bounds.contains(button.frame))
            XCTAssertGreaterThan(button.frame.width, 0)
            XCTAssertTrue(button.bounds.contains(button.resolvedIconRect))
        }
        for pair in zip(buttons, buttons.dropFirst()) {
            XCTAssertFalse(pair.0.frame.intersects(pair.1.frame))
            let insideFirst = CGPoint(x: pair.0.frame.maxX - 0.1, y: pair.0.frame.midY)
            XCTAssertIdentical(player.hitTest(insideFirst), pair.0)
        }
        XCTAssertTrue(layout.well.contains(player.timeDisplay.frame))
        XCTAssertTrue(layout.well.contains(player.spectrumWell.frame))
        XCTAssertFalse(player.timeDisplay.frame.intersects(player.spectrumWell.frame))
    }

    func testCompactVisualizerAndTimerShareStateWithExpandedViews() throws {
        let audio = CompactAudioSpy(installRemoteCommands: false)
        let playlist = CompactPlaylistSpy(
            audioPlayer: MockAudioPlayer(),
            restoreBookmarks: false,
            restorePlaylist: false,
            alertPresenter: SilentPlaylistAlertPresenter()
        )
        let player = self.makePlayer(audio: audio, playlist: playlist)
        player.spectrumWell.selectPalette(.amber)
        player.spectrumWell.selectStyle(.waterfall)
        XCTAssertEqual(self.sharedState?.visualizerSettings, AmpXMiniVisualizerSettings(style: .waterfall, palette: .amber))
        self.sharedState?.setVisualizerSettings(.init(style: .stereoBars, palette: .green))
        XCTAssertEqual(player.spectrumWell.settings.style, .stereoBars)
        player.timeDisplay.performKeyboardPress()
        XCTAssertTrue(try XCTUnwrap(self.sharedState?.showRemainingTime))
    }

    private var sharedState: AmpXPlayerPresentationState?
    private func makePlayer(audio: AudioPlayer, playlist: PlaylistManager) -> PlayerCompactContent {
        let suite = "AmpXCompactPlayerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        self.addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let state = AmpXPlayerPresentationState(store: .init(defaults: defaults))
        self.sharedState = state
        let player = PlayerCompactContent(
            skin: ClassicModernSkin(),
            audioPlayer: audio,
            playlistManager: playlist,
            presentationState: state,
            onToggleModule: { _ in }
        )
        player.frame = CGRect(x: 0, y: 0, width: 490, height: AmpXCompactMetrics.playerHeight)
        player.layoutSubtreeIfNeeded()
        return player
    }
}

@MainActor
private final class CompactAudioSpy: AudioPlayer {
    var playCount = 0
    var pauseCount = 0
    var stopCount = 0
    override func playOrResume() {
        self.playCount += 1
    }

    override func pause() {
        self.pauseCount += 1
    }

    override func stop() {
        self.stopCount += 1
    }
}

@MainActor
private final class CompactPlaylistSpy: PlaylistManager {
    var previousCount = 0
    var nextCount = 0
    override func previous() {
        self.previousCount += 1
    }

    override func next() {
        self.nextCount += 1
    }
}
