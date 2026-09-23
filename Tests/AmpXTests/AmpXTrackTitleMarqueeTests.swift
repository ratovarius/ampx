@testable import AmpX
import XCTest

@MainActor
final class AmpXTrackTitleMarqueeTests: XCTestCase {
    // MARK: - Layout

    func testTitleThatFitsStaysStill() {
        let layout = AmpXMarqueeLayout(textWidth: 100, separatorWidth: 20, viewportWidth: 100)
        XCTAssertFalse(layout.scrolls)
        XCTAssertEqual(layout.offset(elapsed: 5), 0)
        XCTAssertEqual(layout.copyOrigins(elapsed: 5), [0])
    }

    func testLongTitleMovesLeftAtConstantSpeedAndLoops() {
        let layout = AmpXMarqueeLayout(textWidth: 300, separatorWidth: 30, viewportWidth: 200)
        XCTAssertTrue(layout.scrolls)
        XCTAssertEqual(layout.cycleLength, 330)
        XCTAssertEqual(layout.offset(elapsed: 0), 0)
        XCTAssertEqual(layout.offset(elapsed: 1), AmpXMarqueeLayout.speed, accuracy: 0.001)
        XCTAssertEqual(layout.offset(elapsed: 2), 2 * AmpXMarqueeLayout.speed, accuracy: 0.001)
        let fullCycle = TimeInterval(330 / AmpXMarqueeLayout.speed)
        XCTAssertEqual(layout.offset(elapsed: fullCycle + 1), AmpXMarqueeLayout.speed, accuracy: 0.001)
    }

    func testSecondCopyFollowsTheSeparator() {
        let layout = AmpXMarqueeLayout(textWidth: 300, separatorWidth: 30, viewportWidth: 200)
        let origins = layout.copyOrigins(elapsed: 1)
        XCTAssertEqual(origins.count, 2)
        XCTAssertEqual(origins[0], -AmpXMarqueeLayout.speed, accuracy: 0.001)
        XCTAssertEqual(origins[1] - origins[0], 330, accuracy: 0.001)
    }

    func testSeparatorIsThreeAsterisks() {
        XCTAssertEqual(AmpXMarqueeLayout.separator.trimmingCharacters(in: .whitespaces), "***")
    }

    // MARK: - View

    private func makeView() -> TrackTitleMarqueeView {
        let view = TrackTitleMarqueeView(skin: ClassicModernSkin())
        view.frame = CGRect(x: 0, y: 0, width: 120, height: 28)
        view.textOrigin = CGPoint(x: 4, y: 20)
        return view
    }

    func testShortTitleParksTheDisplayLink() {
        let view = self.makeView()
        view.title = "Short"
        XCTAssertFalse(view.layout.scrolls)
        XCTAssertTrue(view.isContinuousRenderingPaused)
    }

    func testLongTitleRunsTheDisplayLinkAndRestartsOnChange() {
        let view = self.makeView()
        view.title = String(repeating: "Very long track title ", count: 4)
        XCTAssertTrue(view.layout.scrolls)
        XCTAssertFalse(view.isContinuousRenderingPaused)

        view.tick(at: 10)
        view.tick(at: 12)
        XCTAssertEqual(view.elapsed, 2, accuracy: 0.001)

        view.title = String(repeating: "Another long track title ", count: 4)
        XCTAssertEqual(view.elapsed, 0)
    }

    func testSuppressedScrollingHoldsTheTextStill() {
        let view = self.makeView()
        view.title = String(repeating: "Very long track title ", count: 4)
        view.isScrollingSuppressed = true
        XCTAssertTrue(view.isContinuousRenderingPaused)
    }

    func testTitleViewPassesClicksThrough() {
        let view = self.makeView()
        XCTAssertNil(view.hitTest(CGPoint(x: 10, y: 10)))
    }

    // MARK: - Player wiring

    func testPlayerFeedsCurrentTrackToTheMarquee() {
        let manager = PlaylistManager(
            audioPlayer: MockAudioPlayer(),
            restoreBookmarks: false,
            restorePlaylist: false,
            alertPresenter: SilentPlaylistAlertPresenter()
        )
        let content = PlayerModuleContent(
            skin: ClassicModernSkin(),
            audioPlayer: AudioPlayer(installRemoteCommands: false),
            playlistManager: manager,
            onToggleModule: { _ in }
        )
        XCTAssertEqual(content.trackTitleView.title, "")
        XCTAssertEqual(content.trackTitleView.frame, PlayerModuleContent.trackTitleFrame.integral)

        content.referencePresentation = AmpXReferenceFixtures.playerTitleOnly("4. Crusher-P - Echo (3:50)")
        XCTAssertEqual(content.trackTitleView.title, "4. Crusher-P - Echo (3:50)")
        XCTAssertTrue(content.trackTitleView.isScrollingSuppressed)
    }
}

private enum AmpXReferenceFixtures {
    static func playerTitleOnly(_ title: String) -> PlayerReferencePresentation {
        PlayerReferencePresentation(
            trackTitle: title,
            timeText: "00:00",
            bitrateText: "128",
            sampleRateText: "44",
            isMono: false,
            isStereo: true,
            isPlaying: false,
            spectrumLevels: [],
            spectrumPeaks: [],
            volume: 0.5,
            balance: 0.5,
            position: 0,
            equalizerOpen: false,
            playlistOpen: false,
            shuffleEnabled: false,
            repeatEnabled: false
        )
    }
}
