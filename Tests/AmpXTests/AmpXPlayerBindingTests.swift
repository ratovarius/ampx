@testable import AmpX
import XCTest

@MainActor
final class AmpXPlayerBindingTests: XCTestCase {
    private var audioPlayer: SpyAudioPlayer!
    private var playlistManager: SpyPlaylistManager!
    private var content: PlayerModuleContent!

    override func setUp() {
        super.setUp()
        self.audioPlayer = SpyAudioPlayer(installRemoteCommands: false)
        self.playlistManager = SpyPlaylistManager(
            audioPlayer: MockAudioPlayer(),
            restoreBookmarks: false,
            restorePlaylist: false,
            alertPresenter: SilentPlaylistAlertPresenter()
        )
        self.content = PlayerModuleContent(
            skin: ClassicModernSkin(),
            audioPlayer: self.audioPlayer,
            playlistManager: self.playlistManager,
            onToggleModule: { _ in }
        )
        self.content.updateModuleToggleStates(eqOpen: true, plOpen: true)
    }

    func testPlayButtonCallsPlayOrResume() {
        self.tapTransport(accessibilityTitle: "Play")
        XCTAssertEqual(self.audioPlayer.playOrResumeCallCount, 1)
    }

    func testPauseButtonCallsPause() {
        self.tapTransport(accessibilityTitle: "Pause")
        XCTAssertEqual(self.audioPlayer.pauseCallCount, 1)
    }

    func testStopButtonCallsStop() {
        self.tapTransport(accessibilityTitle: "Stop")
        XCTAssertEqual(self.audioPlayer.stopCallCount, 1)
    }

    func testPreviousButtonCallsPlaylistPrevious() {
        self.tapTransport(accessibilityTitle: "Previous")
        XCTAssertEqual(self.playlistManager.previousCallCount, 1)
    }

    func testNextButtonCallsPlaylistNext() {
        self.tapTransport(accessibilityTitle: "Next")
        XCTAssertEqual(self.playlistManager.nextCallCount, 1)
    }

    func testEjectButtonShowsFilePicker() {
        self.tapTransport(accessibilityTitle: "Eject")
        XCTAssertEqual(self.playlistManager.showFilePickerCallCount, 1)
    }

    func testVolumeSliderCallsSetVolume() {
        let sliders = self.controlSliders(in: self.content)
        XCTAssertGreaterThanOrEqual(sliders.count, 1)
        sliders[0].onChange?(0.42)
        XCTAssertEqual(self.audioPlayer.lastVolume ?? -1, 0.42, accuracy: 0.0001)
    }

    func testBalanceSliderCallsSetBalance() {
        let sliders = self.controlSliders(in: self.content)
        XCTAssertGreaterThanOrEqual(sliders.count, 2)
        sliders[1].onChange?(0.75)
        XCTAssertEqual(self.audioPlayer.lastBalance ?? -1, 0.5, accuracy: 0.0001)
    }

    func testPositionBarSeekCallsAudioPlayerSeek() {
        self.audioPlayer.duration = 200
        let positionBar = self.firstSubview(ofType: PositionBarView.self, in: self.content)
        XCTAssertNotNil(positionBar)
        positionBar?.onChange?(100)
        XCTAssertEqual(self.audioPlayer.lastSeekTime ?? -1, 100, accuracy: 0.0001)
    }

    func testShuffleToggleUpdatesPlaylistManager() {
        self.tapTransport(accessibilityTitle: "Shuffle")
        XCTAssertTrue(self.playlistManager.shuffleEnabled)
        self.tapTransport(accessibilityTitle: "Shuffle")
        XCTAssertFalse(self.playlistManager.shuffleEnabled)
    }

    func testRepeatToggleUpdatesPlaylistManager() {
        self.tapTransport(accessibilityTitle: "Repeat")
        XCTAssertTrue(self.playlistManager.repeatEnabled)
        self.tapTransport(accessibilityTitle: "Repeat")
        XCTAssertFalse(self.playlistManager.repeatEnabled)
    }

    private func tapTransport(accessibilityTitle: String) {
        let button = self.subviews(ofType: AmpXButton.self, in: self.content)
            .first { $0.accessibilityTitle == accessibilityTitle }
        XCTAssertNotNil(button)
        button?.action?()
    }

    private func firstSubview<T: NSView>(ofType type: T.Type, in root: NSView) -> T? {
        self.subviews(ofType: type, in: root).first
    }

    private func subviews<T: NSView>(ofType type: T.Type, in root: NSView) -> [T] {
        var found: [T] = []
        for subview in root.subviews {
            if let match = subview as? T {
                found.append(match)
            }
            found.append(contentsOf: self.subviews(ofType: type, in: subview))
        }
        return found
    }

    private func controlSliders(in root: NSView) -> [AmpXSlider] {
        self.subviews(ofType: AmpXSlider.self, in: root)
            .filter { !($0.superview is PositionBarView) }
    }
}

@MainActor
private final class SpyAudioPlayer: AudioPlayer {
    var playOrResumeCallCount = 0
    var pauseCallCount = 0
    var stopCallCount = 0
    var lastVolume: Float?
    var lastBalance: Float?
    var lastSeekTime: TimeInterval?

    override func playOrResume() {
        self.playOrResumeCallCount += 1
    }

    override func pause() {
        self.pauseCallCount += 1
    }

    override func stop() {
        self.stopCallCount += 1
    }

    override func setVolume(_ newVolume: Float) {
        self.lastVolume = newVolume
        super.setVolume(newVolume)
    }

    override func setBalance(_ newBalance: Float) {
        self.lastBalance = newBalance
        super.setBalance(newBalance)
    }

    override func seek(to time: TimeInterval) {
        self.lastSeekTime = time
        super.seek(to: time)
    }
}

@MainActor
private final class SpyPlaylistManager: PlaylistManager {
    var previousCallCount = 0
    var nextCallCount = 0
    var showFilePickerCallCount = 0

    override func previous() {
        self.previousCallCount += 1
    }

    override func next() {
        self.nextCallCount += 1
    }

    override func showFilePicker() {
        self.showFilePickerCallCount += 1
    }
}
