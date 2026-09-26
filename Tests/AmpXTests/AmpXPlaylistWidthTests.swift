@testable import AmpX
import AppKit
import XCTest

/// Spec Revision 9: the Playlist is the only module with a variable width (min 490 pt, no maximum).
@MainActor
final class AmpXPlaylistWidthTests: XCTestCase {
    private func makeCoordinator() -> AmpXHostCoordinator {
        let suite = "AmpXPlaylistWidthTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let coordinator = AmpXHostCoordinator(
            state: AmpXModuleState(),
            skin: ClassicModernSkin(),
            layoutStore: AmpXLayoutStore(defaults: defaults, screen: AmpXTestScreen.standard),
            screen: AmpXTestScreen.standard
        )
        addTeardownBlock { @MainActor in coordinator.hideAllWindowsForTesting() }
        coordinator.showAll()
        return coordinator
    }

    // MARK: - Layout

    func testWidePlaylistWidensOnlyItsOwnWindow() {
        var state = AmpXModuleState()
        state.reopen(.enthea)
        let frames = AmpXLayout.defaultFrames(state: state, playlistViewportHeight: 180, playlistWidth: 700, anchorTopLeft: .zero)

        XCTAssertEqual(frames[.playlist]?.width, 700)
        XCTAssertEqual(frames[.player]?.width, 490)
        XCTAssertEqual(frames[.equalizer]?.width, 490)
        XCTAssertEqual(frames[.enthea]?.minX, 490, "ENTHEA docks to the Player, not past the Playlist")
    }

    func testPlaylistWidthClampsToEqualizerWidth() {
        let size = AmpXLayout.moduleSize(.playlist, state: AmpXModuleState(), playlistViewportHeight: 180, playlistWidth: 300)
        XCTAssertEqual(size.width, AmpXMetrics.compositionWidth)
    }

    // MARK: - Stretching, not scaling

    func testWidePlaylistStretchesContentWithoutScaling() throws {
        let coordinator = self.makeCoordinator()
        coordinator.setPlaylistWidth(700)

        let module = try XCTUnwrap(coordinator.moduleView(for: .playlist))
        let content = try XCTUnwrap(module.content as? PlaylistModuleContent)
        let window = try XCTUnwrap(module.window)

        XCTAssertEqual(module.frame.width, 700)
        XCTAssertEqual(window.frame.width, 700)
        XCTAssertEqual(coordinator.moduleView(for: .player)?.frame.width, 490)
        // Stretch, not scale: content points stay 1:1 and the header keeps its reference height.
        XCTAssertEqual(content.bounds.width, 700)
        XCTAssertEqual(module.header.frame.height, AmpXMetrics.headerHeight)

        let frames = PlaylistModuleContent.layout(viewportHeight: 196, width: 700)
        XCTAssertEqual(frames.rows.width, 647)
        XCTAssertEqual(frames.scrollbar.minX, 666)
        XCTAssertEqual(frames.scrollbar.width, AmpXMetrics.playlistScrollbar.width)
        XCTAssertEqual(frames.footer.width, 700)
    }

    func testWideFooterKeepsLeftButtonsAndRightGroupAnchored() throws {
        let coordinator = self.makeCoordinator()
        coordinator.setPlaylistWidth(700)
        let module = try XCTUnwrap(coordinator.moduleView(for: .playlist))
        let content = try XCTUnwrap(module.content as? PlaylistModuleContent)
        let buttons = self.descendants(ofType: AmpXButton.self, in: content)

        let add = try XCTUnwrap(buttons.first { $0.accessibilityTitle == "ADD" })
        XCTAssertEqual(add.frame.minX, AmpXMetrics.playlistFooterButtons[0].rect.minX)
        XCTAssertEqual(add.frame.width, AmpXMetrics.playlistFooterButtons[0].rect.width)

        let listOpts = try XCTUnwrap(buttons.first { $0.accessibilityTitle == "LIST OPTS" })
        let referenceTrailingGap = AmpXMetrics.compositionWidth - AmpXMetrics.playlistFooterButtons[4].rect.maxX
        XCTAssertEqual(listOpts.frame.maxX, 700 - referenceTrailingGap, accuracy: 0.01)
        XCTAssertEqual(listOpts.frame.width, AmpXMetrics.playlistFooterButtons[4].rect.width)
    }

    func testWideHeaderCentersTitleAndRightAnchorsButtons() throws {
        let coordinator = self.makeCoordinator()
        coordinator.setPlaylistWidth(700)
        let module = try XCTUnwrap(coordinator.moduleView(for: .playlist))
        let header = module.header
        let reference = AmpXModuleHeaderView(moduleID: .playlist, skin: ClassicModernSkin())
        reference.frame = CGRect(x: 0, y: 0, width: AmpXMetrics.compositionWidth, height: AmpXMetrics.headerHeight)

        let close = try XCTUnwrap(header.headerButtonLayout().first { $0.button == .close })
        let referenceClose = try XCTUnwrap(reference.headerButtonLayout().first { $0.button == .close })
        XCTAssertEqual(close.frame.size, referenceClose.frame.size, "Header buttons must not scale")
        XCTAssertEqual(
            AmpXMetrics.compositionWidth - referenceClose.frame.maxX,
            700 - close.frame.maxX,
            accuracy: 0.01
        )
        XCTAssertEqual(header.titleGroupFrame.midX, 350, accuracy: 1, "Title group stays centered")
    }

    // MARK: - Handle

    func testRightStripAndCornerResolveToResizeHandle() throws {
        let coordinator = self.makeCoordinator()
        let module = try XCTUnwrap(coordinator.moduleView(for: .playlist))

        for point in [
            CGPoint(x: module.bounds.maxX - 2, y: module.bounds.midY),
            CGPoint(x: module.bounds.maxX - 1, y: module.bounds.maxY - 20),
        ] {
            let superview = try XCTUnwrap(module.superview)
            XCTAssertTrue(
                module.hitTest(superview.convert(point, from: module)) is PlaylistResizeHandleView,
                "No resize handle at \(point)"
            )
        }
        XCTAssertEqual(
            PlaylistResizeHandleView.cursor(for: .right),
            NSCursor.frameResize(position: .right, directions: .all)
        )
        XCTAssertEqual(
            PlaylistResizeHandleView.cursor(for: .corner),
            NSCursor.frameResize(position: .bottomRight, directions: .all)
        )
    }

    func testDraggingRightStripWidensPlaylistKeepingLeftEdge() throws {
        let coordinator = self.makeCoordinator()
        let module = try XCTUnwrap(coordinator.moduleView(for: .playlist))
        let content = try XCTUnwrap(module.content as? PlaylistModuleContent)
        let window = try XCTUnwrap(module.window)
        let left = window.frame.minX
        let height = module.frame.height

        try self.drag(content.resizeHandle, edge: .right, in: window, by: CGSize(width: 120, height: 0))

        XCTAssertEqual(module.frame.width, 610, accuracy: 0.5)
        XCTAssertEqual(window.frame.width, 610, accuracy: 0.5)
        XCTAssertEqual(window.frame.minX, left, accuracy: 0.5)
        XCTAssertEqual(module.frame.height, height, accuracy: 0.5, "Right strip must not change height")
    }

    func testDraggingCornerResizesBothAxesAndClampsWidth() throws {
        let coordinator = self.makeCoordinator()
        let module = try XCTUnwrap(coordinator.moduleView(for: .playlist))
        let content = try XCTUnwrap(module.content as? PlaylistModuleContent)
        let window = try XCTUnwrap(module.window)
        let height = module.frame.height

        try self.drag(content.resizeHandle, edge: .corner, in: window, by: CGSize(width: 100, height: -40))
        XCTAssertEqual(module.frame.width, 590, accuracy: 0.5)
        XCTAssertEqual(module.frame.height, height - 40, accuracy: 0.5)

        // Dragging far left clamps at the Equalizer width.
        try self.drag(content.resizeHandle, edge: .corner, in: window, by: CGSize(width: -400, height: 0))
        XCTAssertEqual(module.frame.width, AmpXMetrics.compositionWidth, accuracy: 0.5)
    }

    func testPlaylistWidthSurvivesCloseAndReopen() {
        let coordinator = self.makeCoordinator()
        coordinator.setPlaylistWidth(640)
        coordinator.closeModule(.playlist)
        coordinator.reopenModule(.playlist)
        XCTAssertEqual(coordinator.window(for: .playlist)?.frame.width, 640)
        XCTAssertEqual(coordinator.moduleView(for: .playlist)?.frame.width, 640)
    }

    // MARK: - Persistence

    func testLayoutStoreRoundTripsPlaylistWidth() throws {
        let suite = "AmpXPlaylistWidthTests.store.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let store = AmpXLayoutStore(defaults: defaults, screen: AmpXTestScreen.standard)

        var layout = AmpXLayoutStore.defaultLayout(for: AmpXTestScreen.standard)
        XCTAssertEqual(layout.playlistWidth, AmpXMetrics.compositionWidth)
        layout.playlistWidth = 812
        store.save(layout)
        XCTAssertEqual(store.load().playlistWidth, 812)

        layout.playlistWidth = 120
        store.save(layout)
        XCTAssertEqual(store.load().playlistWidth, AmpXMetrics.compositionWidth, "Too-small widths use the minimum")
    }

    // MARK: - Helpers

    private func descendants<T: NSView>(ofType type: T.Type, in view: NSView) -> [T] {
        view.subviews.flatMap { subview -> [T] in
            let nested = self.descendants(ofType: type, in: subview)
            return (subview as? T).map { [$0] + nested } ?? nested
        }
    }

    private func drag(
        _ handle: PlaylistResizeHandleView,
        edge: PlaylistResizeHandleView.Edge,
        in window: NSWindow,
        by delta: CGSize
    ) throws {
        let local = handle.hitRect(for: edge)
        let start = window.convertPoint(toScreen: handle.convert(CGPoint(x: local.midX, y: local.midY), to: nil))
        handle.mouseDown(with: self.event(.leftMouseDown, screenPoint: start, window: window))
        for step in 1 ... 4 {
            let fraction = CGFloat(step) / 4
            let point = CGPoint(x: start.x + delta.width * fraction, y: start.y - delta.height * fraction)
            handle.mouseDragged(with: self.event(.leftMouseDragged, screenPoint: point, window: window))
        }
        let end = CGPoint(x: start.x + delta.width, y: start.y - delta.height)
        handle.mouseUp(with: self.event(.leftMouseUp, screenPoint: end, window: window))
    }

    private func event(_ type: NSEvent.EventType, screenPoint: CGPoint, window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: window.convertPoint(fromScreen: screenPoint),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }
}
