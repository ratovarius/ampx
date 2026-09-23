@testable import AmpX
import AppKit
import XCTest

@MainActor
final class AmpXCompactReviewRegressionTests: XCTestCase {
    func testRemainingTimerWaitsForNewTracksDecodedDuration() {
        let audio = AudioPlayer(installRemoteCommands: false)
        let timer = TimeDisplayView(skin: ClassicModernSkin())
        timer.audioPlayer = audio
        timer.style = .compact
        timer.showRemainingTime = true
        audio.currentTrack = Track(title: "Old", artist: "", duration: 100)
        audio.duration = 110
        XCTAssertEqual(timer.compactText, "-01:50")
        audio.currentTrack = Track(title: "Loading", artist: "", duration: 200)
        XCTAssertEqual(timer.compactText, "00:00")
        audio.duration = 110
        XCTAssertEqual(timer.compactText, "-01:50")
    }

    func testEarlierPressResetCannotCancelSecondMousePress() async {
        let button = AmpXButton(skin: ClassicModernSkin())
        button.frame = CGRect(x: 0, y: 0, width: 40, height: 30)
        var actions = 0
        button.action = { actions += 1 }
        let down = self.mouse(.leftMouseDown, in: button)
        let up = self.mouse(.leftMouseUp, in: button)
        button.mouseDown(with: down)
        button.mouseUp(with: up)
        button.mouseDown(with: down)
        let pastReset = self.expectation(description: "Earlier visual reset deadline")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { pastReset.fulfill() }
        await self.fulfillment(of: [pastReset], timeout: 1)
        button.mouseUp(with: up)
        XCTAssertEqual(actions, 2)
    }

    func testExpandingCompactGripCancelsSharedDragAndLateMouseUp() throws {
        let coordinator = self.makeCoordinator()
        coordinator.setCollapsed(.equalizer, true)
        let compact = try XCTUnwrap(coordinator.moduleView(for: .equalizer)?.compactContent)
        let grip = compact.chromeLayout.grip
        let point = CGPoint(x: grip.midX, y: grip.midY)
        compact.mouseDown(with: self.mouse(.leftMouseDown, in: compact, point: point))
        XCTAssertTrue(coordinator.dragController.isDragging)
        coordinator.setCollapsed(.equalizer, false)
        XCTAssertFalse(coordinator.dragController.isDragging)
        let order = coordinator.state.order
        compact.mouseUp(with: self.mouse(.leftMouseUp, in: compact, point: point))
        XCTAssertEqual(coordinator.state.order, order)
    }

    func testCollapsedPlaylistRejectsLateScrollbarDragAndWheelForwarding() async throws {
        let coordinator = self.makeCoordinator()
        let module = try XCTUnwrap(coordinator.moduleView(for: .playlist))
        let content = try XCTUnwrap(module.content as? PlaylistModuleContent)
        let rows = try XCTUnwrap(content.subviews.compactMap { $0 as? PlaylistRowsView }.first)
        rows.manager?.addTracks((0 ..< 100).map { Track(title: "\($0)", artist: "") })
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        let bar = try XCTUnwrap(content.subviews.compactMap { $0 as? AmpXScrollbar }.first)
        let thumb = bar.thumbRect()
        bar.mouseDown(with: self.mouse(.leftMouseDown, in: bar, point: CGPoint(x: thumb.midX, y: thumb.midY)))
        coordinator.setCollapsed(.playlist, true)
        let offset = content.scrollOffset
        bar.mouseDragged(with: self.mouse(.leftMouseDragged, in: bar, point: CGPoint(x: thumb.midX, y: thumb.midY + 50)))
        bar.mouseUp(with: self.mouse(.leftMouseUp, in: bar))
        XCTAssertEqual(content.scrollOffset, offset, "Hidden scrollbar drag must be cancelled")
        let viewport = try XCTUnwrap(module.superview?.superview as? AmpXStackViewport)
        let cgEvent = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -5, wheel2: 0, wheel3: 0))
        try viewport.scrollWheel(with: XCTUnwrap(NSEvent(cgEvent: cgEvent)))
        XCTAssertEqual(content.scrollOffset, offset, "Compact Playlist must not scroll hidden rows")
    }

    private func mouse(_ type: NSEvent.EventType, in view: NSView, point: CGPoint? = nil) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: view.convert(point ?? CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    private func makeCoordinator() -> AmpXHostCoordinator {
        let coordinator = AmpXHostCoordinator(
            state: AmpXModuleOrder(), skin: ClassicModernSkin(), layoutStore: makeIsolatedLayoutStore(),
            audioPlayer: AudioPlayer(installRemoteCommands: false),
            playlistManager: PlaylistManager(
                audioPlayer: MockAudioPlayer(),
                restoreBookmarks: false,
                restorePlaylist: false,
                alertPresenter: SilentPlaylistAlertPresenter()
            ),
            entheaEnabled: false
        )
        self.addTeardownBlock { @MainActor in coordinator.closeStack() }
        coordinator.showStack()
        return coordinator
    }
}
