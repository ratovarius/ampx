@testable import AmpX
import XCTest

@MainActor
final class AmpXApplicationControllerTests: XCTestCase {
    private func makeController(
        audioPlayer: AudioPlayer? = nil,
        playlistManager: PlaylistManager? = nil,
        entheaEnabled: Bool = false
    ) -> (AmpXApplicationController, AudioPlayer, PlaylistManager, AmpXHostCoordinator) {
        let player = audioPlayer ?? AudioPlayer(installRemoteCommands: false)
        let manager = playlistManager ?? PlaylistManager(
            audioPlayer: MockAudioPlayer(),
            restoreBookmarks: false,
            restorePlaylist: false,
            alertPresenter: SilentPlaylistAlertPresenter()
        )
        let hosts = AmpXHostCoordinator(
            state: AmpXModuleOrder(),
            skin: ClassicModernSkin(),
            layoutStore: makeIsolatedLayoutStore(),
            audioPlayer: player,
            playlistManager: manager,
            entheaEnabled: entheaEnabled
        )
        let application = AmpXApplicationController(
            audioPlayer: player,
            playlistManager: manager,
            hosts: hosts
        )
        return (application, player, manager, hosts)
    }

    func testStartBindsPlaybackCoordinationOnce() {
        let (application, player, manager, _) = self.makeController()
        application.start()
        XCTAssertTrue(application.isPlaybackCoordinationBound)
        XCTAssertNotNil(player.onTrackFinished)
        XCTAssertNotNil(player.onNextTrackRequested)
        XCTAssertNotNil(player.onPreviousTrackRequested)

        manager.tracks = [
            Track(title: "A", artist: "B", url: URL(fileURLWithPath: "/tmp/a.mp3")),
            Track(title: "C", artist: "D", url: URL(fileURLWithPath: "/tmp/c.mp3")),
        ]
        manager.currentIndex = 0
        player.onNextTrackRequested?()
        XCTAssertEqual(manager.currentIndex, 1)

        application.start()
        XCTAssertTrue(application.isPlaybackCoordinationBound)
    }

    func testStartSkipsStartupSoundUnderTest() {
        let mock = MockAudioPlayer()
        let manager = PlaylistManager(
            audioPlayer: mock,
            restoreBookmarks: false,
            restorePlaylist: false,
            alertPresenter: SilentPlaylistAlertPresenter()
        )
        let player = AudioPlayer(installRemoteCommands: false)
        let hosts = AmpXHostCoordinator(
            state: AmpXModuleOrder(),
            skin: ClassicModernSkin(),
            layoutStore: makeIsolatedLayoutStore(),
            audioPlayer: player,
            playlistManager: manager
        )
        let application = AmpXApplicationController(
            audioPlayer: player,
            playlistManager: manager,
            hosts: hosts,
            playsStartupSound: false
        )
        application.start()
        XCTAssertTrue(mock.loadTrackCalls.isEmpty)
    }

    func testCloseStackDoesNotStopPlayback() {
        let mock = MockAudioPlayer()
        let manager = PlaylistManager(
            audioPlayer: mock,
            restoreBookmarks: false,
            restorePlaylist: false,
            alertPresenter: SilentPlaylistAlertPresenter()
        )
        let player = AudioPlayer(installRemoteCommands: false)
        let hosts = AmpXHostCoordinator(
            state: AmpXModuleOrder(),
            skin: ClassicModernSkin(),
            layoutStore: makeIsolatedLayoutStore(),
            audioPlayer: player,
            playlistManager: manager
        )
        let application = AmpXApplicationController(
            audioPlayer: player,
            playlistManager: manager,
            hosts: hosts,
            playsStartupSound: false
        )
        application.start()
        mock.playCallCount = 1

        hosts.closeStack()
        XCTAssertEqual(mock.stopCallCount, 0)
        XCTAssertFalse(hosts.isStackVisible)
    }

    func testTerminateHandlesTheaterShutdown() {
        let (application, _, _, hosts) = self.makeController(entheaEnabled: true)
        application.start()
        hosts.reopenModule(.enthea)
        hosts.toggleTheater()
        XCTAssertTrue(hosts.isInTheater)
        application.terminate()
        XCTAssertFalse(hosts.isInTheater)
    }
}
