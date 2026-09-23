@testable import AmpX
import AppKit
import XCTest

@MainActor
final class AmpXCompactHostTests: XCTestCase {
    func testWideCompactPlaylistPreservesBodySelectionScrollAndDetachedConstraints() async throws {
        let coordinator = self.makeCoordinator()
        coordinator.setPlaylistWidth(800)
        let module = try XCTUnwrap(coordinator.moduleView(for: .playlist))
        let body = try XCTUnwrap(module.content as? PlaylistModuleContent)
        let rows = try XCTUnwrap(body.subviews.compactMap { $0 as? PlaylistRowsView }.first)
        let adapter = try XCTUnwrap(rows.keyboardAdapter)
        let tracks = (0 ..< 100).map { Track(title: "\($0)", artist: "Test") }
        rows.manager?.addTracks(tracks)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        adapter.selection.selectOnly(tracks[50].id)
        adapter.onRevealCursor?()
        let bodyFrame = body.frame
        let scroll = body.scrollOffset
        XCTAssertGreaterThan(scroll, 0)
        let footer = try XCTUnwrap(body.subviews.compactMap { $0 as? PlaylistFooterView }.first)
        XCTAssertIdentical(footer.listOptionsMenu, body.listOptionsMenu)
        coordinator.setCollapsed(.playlist, true)
        let compact = try XCTUnwrap(module.compactContent as? PlaylistCompactContent)
        XCTAssertEqual(module.frame.width, 800)
        XCTAssertEqual(body.frame, bodyFrame)
        XCTAssertEqual(body.scrollOffset, scroll)
        XCTAssertTrue(body.resizeHandle.isHiddenOrHasHiddenAncestor)
        XCTAssertEqual(coordinator.stackWindow?.contentMinSize.width, coordinator.stackWindow?.contentMaxSize.width)
        coordinator.detach(.playlist, at: CGPoint(x: 700, y: 600), inheritedWidth: 490)
        let window = try XCTUnwrap(module.window)
        XCTAssertEqual(window.frame.width, 800)
        XCTAssertEqual(window.contentMinSize, window.contentMaxSize)
        XCTAssertEqual(window.frame.height, AmpXCompactMetrics.playlistHeight, accuracy: 0.5)
        XCTAssertEqual(window.contentView?.bounds.height, module.frame.height)
        XCTAssertEqual(compact.frame, module.bounds)
        coordinator.redock(.playlist, at: 2)
        XCTAssertIdentical(module.compactContent, compact)
        coordinator.setCollapsed(.playlist, false)
        XCTAssertEqual(body.frame, bodyFrame)
        XCTAssertEqual(body.scrollOffset, scroll)
        XCTAssertEqual(adapter.selection.selectedIDs, [tracks[50].id])
    }

    func testCompactChromeMinimizesClosesAndReopensTheSameHost() async throws {
        let coordinator = self.makeCoordinator()
        coordinator.setCollapsed(.player, true)
        let module = try XCTUnwrap(coordinator.moduleView(for: .player))
        let compact = try XCTUnwrap(module.compactContent)
        let window = try XCTUnwrap(coordinator.stackWindow)
        let minimized = self.expectation(forNotification: NSWindow.didMiniaturizeNotification, object: window)
        compact.minimizeButton?.action?()
        await self.fulfillment(of: [minimized], timeout: 3)
        XCTAssertTrue(window.isMiniaturized, "Minimize must complete")
        let restored = self.expectation(forNotification: NSWindow.didDeminiaturizeNotification, object: window)
        NSApp.activate()
        coordinator.showStack()
        await self.fulfillment(of: [restored], timeout: 3)
        XCTAssertFalse(window.isMiniaturized)
        compact.closeButton.action?()
        XCTAssertFalse(window.isVisible)
        coordinator.showStack()
        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(module.isContentCollapsed)
        XCTAssertIdentical(module.compactContent, compact)
    }

    func testCollapseCancelsPlaylistRowAndResizeTracking() throws {
        let coordinator = self.makeCoordinator()
        let module = try XCTUnwrap(coordinator.moduleView(for: .playlist))
        let content = try XCTUnwrap(module.content as? PlaylistModuleContent)
        let rows = try XCTUnwrap(content.subviews.compactMap { $0 as? PlaylistRowsView }.first)
        let manager = try XCTUnwrap(rows.manager)
        let tracks = [Track(title: "First", artist: "Test"), Track(title: "Second", artist: "Test")]
        manager.addTracks(tracks)
        let window = try XCTUnwrap(module.window)
        func mouse(_ type: NSEvent.EventType, view: NSView, point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(
                with: type,
                location: view.convert(point, to: nil),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )!
        }
        rows.mouseDown(with: mouse(.leftMouseDown, view: rows, point: CGPoint(x: 30, y: 3)))
        let handle = content.resizeHandle
        handle.mouseDown(with: mouse(
            .leftMouseDown,
            view: handle,
            point: CGPoint(x: handle.bounds.midX, y: handle.bounds.maxY - 1)
        ))
        coordinator.setCollapsed(.playlist, true)
        let collapsedSize = module.frame.size
        rows.mouseDragged(with: mouse(.leftMouseDragged, view: rows, point: CGPoint(x: 30, y: PlaylistRowLayout.rowHeight + 3)))
        rows.mouseUp(with: mouse(.leftMouseUp, view: rows, point: CGPoint(x: 30, y: PlaylistRowLayout.rowHeight + 3)))
        handle.mouseDragged(with: mouse(.leftMouseDragged, view: handle, point: CGPoint(x: 300, y: 200)))
        handle.mouseUp(with: mouse(.leftMouseUp, view: handle, point: CGPoint(x: 300, y: 200)))
        XCTAssertEqual(manager.tracks.map(\.id), tracks.map(\.id))
        XCTAssertEqual(module.frame.size, collapsedSize)
    }

    func testCollapseCancelsButtonAndNestedSeekTracking() throws {
        let coordinator = self.makeCoordinator()
        let player = try XCTUnwrap(coordinator.moduleView(for: .player))
        let window = try XCTUnwrap(coordinator.stackWindow)
        let seek = try XCTUnwrap(player.content.subviews.first { $0 is PositionBarView })
        let slider = try XCTUnwrap(seek.subviews.first as? AmpXSlider)
        let button = try XCTUnwrap(player.content.subviews.compactMap { $0 as? AmpXButton }.first)
        var changes = 0
        var actions = 0
        slider.onChange = { _ in changes += 1 }
        button.action = { actions += 1 }
        func mouse(_ type: NSEvent.EventType, in view: NSView, fraction: CGFloat) -> NSEvent {
            let point = view.convert(CGPoint(x: view.bounds.width * fraction, y: view.bounds.midY), to: nil)
            return NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )!
        }
        slider.mouseDown(with: mouse(.leftMouseDown, in: slider, fraction: 0.2))
        button.mouseDown(with: mouse(.leftMouseDown, in: button, fraction: 0.5))
        let before = changes
        coordinator.setCollapsed(.player, true)
        slider.mouseDragged(with: mouse(.leftMouseDragged, in: slider, fraction: 0.8))
        slider.mouseUp(with: mouse(.leftMouseUp, in: slider, fraction: 0.8))
        button.mouseUp(with: mouse(.leftMouseUp, in: button, fraction: 0.5))
        XCTAssertEqual(changes, before)
        XCTAssertEqual(actions, 0)
    }

    func testCollapsePreservesExpandedBodyAndWindowTopLeftAndRestoresIt() throws {
        let coordinator = self.makeCoordinator()
        let player = try XCTUnwrap(coordinator.moduleView(for: .player))
        let body = player.content
        let oldFrame = body.frame
        let window = try XCTUnwrap(coordinator.stackWindow)
        let topLeft = CGPoint(x: window.frame.minX, y: window.frame.maxY)
        let oldEQY = try XCTUnwrap(coordinator.moduleView(for: .equalizer)).frame.minY
        coordinator.setCollapsed(.player, true)
        let compact = try XCTUnwrap(player.compactContent)
        XCTAssertTrue(player.header.isHidden)
        XCTAssertTrue(body.isHidden)
        XCTAssertFalse(compact.isHidden)
        XCTAssertEqual(compact.frame, player.bounds)
        XCTAssertEqual(body.frame, oldFrame)
        XCTAssertLessThan(try XCTUnwrap(coordinator.moduleView(for: .equalizer)).frame.minY, oldEQY)
        XCTAssertEqual(window.frame.minX, topLeft.x, accuracy: 0.5)
        XCTAssertEqual(window.frame.maxY, topLeft.y, accuracy: 0.5)
        XCTAssertEqual(player.frame.height, AmpXCompactMetrics.playerHeight, accuracy: 0.5)
        compact.expandButton.action?()
        XCTAssertFalse(body.isHidden)
        XCTAssertTrue(compact.isHidden)
        XCTAssertIdentical(player.content, body)
        XCTAssertEqual(body.frame, oldFrame)
    }

    func testSharedBoundarySnappingNeverLeavesGaps() {
        for scale: CGFloat in [1, 2, 3] {
            var y: CGFloat = 0
            var lastMaxY: CGFloat = 0
            for height: CGFloat in [30.25, 30.25, 27.5] {
                let frame = AmpXModuleView.snappedFrame(CGRect(x: 0, y: y, width: 490, height: height), backingScale: scale)
                XCTAssertEqual(frame.minY, lastMaxY)
                XCTAssertEqual(frame.width, 490)
                y += height
                lastMaxY = frame.maxY
            }
        }
    }

    func testCollapseDoesNotStealFocusFromAnotherModule() throws {
        let coordinator = self.makeCoordinator()
        let eq = try XCTUnwrap(coordinator.moduleView(for: .equalizer))
        let window = try XCTUnwrap(coordinator.stackWindow)
        XCTAssertTrue(window.makeFirstResponder(eq.header))
        coordinator.setCollapsed(.player, true)
        XCTAssertIdentical(window.firstResponder, eq.header)
        coordinator.setCollapsed(.player, false)
        XCTAssertIdentical(window.firstResponder, eq.header)
    }

    func testFocusMovesBetweenRetainedExpandedAndCompactControls() throws {
        let coordinator = self.makeCoordinator()
        let player = try XCTUnwrap(coordinator.moduleView(for: .player))
        let window = try XCTUnwrap(coordinator.stackWindow)
        let button = try XCTUnwrap(player.content.focusableControls().first)
        XCTAssertTrue(window.makeFirstResponder(button))
        coordinator.setCollapsed(.player, true)
        let compact = try XCTUnwrap(player.compactContent)
        XCTAssertIdentical(window.firstResponder, compact.expandButton)
        XCTAssertTrue(player.focusableViews().allSatisfy { $0.isDescendant(of: compact) })
        coordinator.setCollapsed(.player, false)
        XCTAssertIdentical(window.firstResponder, button)
        XCTAssertTrue(player.focusableViews().allSatisfy { !$0.isDescendant(of: compact) })
    }

    func makeCoordinator() -> AmpXHostCoordinator {
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
        self.addTeardownBlock { @MainActor in
            for id in coordinator.state.detached {
                coordinator.closeModule(id)
            }
            coordinator.closeStack()
        }
        coordinator.showStack()
        return coordinator
    }
}
