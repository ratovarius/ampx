@testable import AmpX
import Combine
import XCTest

/// A parked spectrum well receives no ticks, so it can only come back when playback tells it to.
@MainActor
final class AmpXPlayerSpectrumWakeTests: XCTestCase {
    func testPlaybackStartWakesTheParkedSpectrumWell() {
        let audioPlayer = AudioPlayer(installRemoteCommands: false)
        let content = PlayerModuleContent(
            skin: ClassicModernSkin(),
            audioPlayer: audioPlayer,
            playlistManager: PlaylistManager(
                audioPlayer: MockAudioPlayer(),
                restoreBookmarks: false,
                restorePlaylist: false,
                alertPresenter: SilentPlaylistAlertPresenter()
            ),
            onToggleModule: { _ in }
        )
        // Deterministic silence: the shared bus is a singleton other tests and audio threads touch.
        content.spectrumWell.audioSource = { _ in AmpXMiniAudioSnapshot() }
        content.spectrumWell.setEffectivelyVisible(true)

        var time: TimeInterval = 0
        while time < 2 {
            time += 1.0 / 60.0
            content.spectrumWell.tick(at: time)
        }
        XCTAssertTrue(content.spectrumWell.isContinuousRenderingPaused, "precondition: the well parks itself")

        // Wait for the binding to deliver rather than a fixed pause: a busy main queue must not race this.
        let delivered = expectation(description: "isPlaying delivered on the main queue")
        let subscription = audioPlayer.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { isPlaying in
                if isPlaying {
                    delivered.fulfill()
                }
            }
        audioPlayer.isPlaying = true
        wait(for: [delivered], timeout: 10)
        subscription.cancel()

        XCTAssertFalse(content.spectrumWell.isContinuousRenderingPaused)
    }
}
