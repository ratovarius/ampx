@testable import AmpX
import AppKit
import XCTest

@MainActor
final class AmpXPlaylistResizeHandleTests: XCTestCase {
    private func makeCoordinator() -> AmpXHostCoordinator {
        let suite = "AmpXPlaylistResizeHandleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let coordinator = AmpXHostCoordinator(
            state: AmpXModuleOrder(),
            skin: ClassicModernSkin(),
            layoutStore: AmpXLayoutStore(defaults: defaults),
            screen: NSScreen.main!
        )
        addTeardownBlock { @MainActor in
            for id in coordinator.state.detached {
                coordinator.closeModule(id)
            }
            coordinator.closeStack()
        }
        coordinator.showStack()
        return coordinator
    }

    private func playlist(_ coordinator: AmpXHostCoordinator) throws -> (AmpXModuleView, PlaylistModuleContent) {
        let module = try XCTUnwrap(coordinator.moduleView(for: .playlist))
        let content = try XCTUnwrap(module.content as? PlaylistModuleContent)
        return (module, content)
    }

    /// Deepest view under a point given in the module's own coordinates.
    private func hit(_ module: AmpXModuleView, at point: CGPoint) throws -> NSView? {
        let superview = try XCTUnwrap(module.superview)
        return module.hitTest(superview.convert(point, from: module))
    }

    func testBottomStripAndCornerGripResolveToResizeHandle() throws {
        let coordinator = self.makeCoordinator()
        let (module, _) = try self.playlist(coordinator)
        let bottom = module.bounds.maxY

        for point in [
            CGPoint(x: module.bounds.midX, y: bottom - 2),
            CGPoint(x: 30, y: bottom - 1),
            CGPoint(x: module.bounds.maxX - 16, y: bottom - 8),
        ] {
            XCTAssertTrue(try self.hit(module, at: point) is PlaylistResizeHandleView, "No resize handle at \(point)")
        }

        // Footer controls above the strip keep their hit areas.
        let footerButtonPoint = CGPoint(x: 40, y: bottom - 30)
        XCTAssertTrue(try self.hit(module, at: footerButtonPoint) is AmpXButton)
        XCTAssertEqual(PlaylistResizeHandleView.resizeCursor, NSCursor.frameResize(position: .bottom, directions: .all))
    }

    func testDraggingHandleResizesDockedPlaylistWithFixedTopEdge() throws {
        let coordinator = self.makeCoordinator()
        let (module, content) = try self.playlist(coordinator)
        let window = try XCTUnwrap(module.window)
        let handle = content.resizeHandle
        let top = window.frame.maxY
        let height = module.frame.height

        try self.drag(handle, in: window, byScreenDeltaY: 40)

        XCTAssertEqual(module.frame.height, height - 40, accuracy: 0.5)
        XCTAssertEqual(window.frame.maxY, top, accuracy: 0.5)
    }

    func testDraggingHandleResizesDetachedPlaylistWithFixedTopEdge() throws {
        let coordinator = self.makeCoordinator()
        coordinator.detach(.playlist, at: CGPoint(x: 700, y: 600), inheritedWidth: 490)
        let (module, content) = try self.playlist(coordinator)
        let window = try XCTUnwrap(module.window)
        XCTAssertTrue(window.windowController is AmpXDetachedModuleWindowController)
        let handle = content.resizeHandle
        let top = window.frame.maxY
        let height = window.frame.height

        try self.drag(handle, in: window, byScreenDeltaY: 40)

        XCTAssertEqual(window.frame.height, height - 40, accuracy: 0.5)
        XCTAssertEqual(window.frame.maxY, top, accuracy: 0.5)
        XCTAssertEqual(module.frame.height, window.frame.height, accuracy: 0.5)
    }

    func testCollapsedPlaylistExposesNoHandle() throws {
        let coordinator = self.makeCoordinator()
        let (module, content) = try self.playlist(coordinator)
        coordinator.handleModuleHeaderCollapse(.playlist)

        let handle = content.resizeHandle
        XCTAssertTrue(handle.isHiddenOrHasHiddenAncestor)
        XCTAssertFalse(try self.hit(module, at: CGPoint(x: module.bounds.midX, y: module.bounds.maxY - 2)) is PlaylistResizeHandleView)
    }

    /// Drags upward by `delta` screen points (shrinking the Playlist), re-deriving window coordinates per event.
    private func drag(_ handle: PlaylistResizeHandleView, in window: NSWindow, byScreenDeltaY delta: CGFloat) throws {
        let strip = handle.hitRect(for: .bottom)
        let local = CGPoint(x: strip.midX, y: strip.midY)
        let start = window.convertPoint(toScreen: handle.convert(local, to: nil))
        handle.mouseDown(with: self.event(.leftMouseDown, screenPoint: start, window: window))
        for step in 1 ... 4 {
            let point = CGPoint(x: start.x, y: start.y + delta * CGFloat(step) / 4)
            handle.mouseDragged(with: self.event(.leftMouseDragged, screenPoint: point, window: window))
        }
        let end = CGPoint(x: start.x, y: start.y + delta)
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
