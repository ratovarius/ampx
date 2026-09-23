@testable import AmpX
import AppKit
import XCTest

@MainActor
final class AmpXModuleInteractionRegressionTests: XCTestCase {
    private func makeCoordinator(state: AmpXModuleOrder = AmpXModuleOrder()) -> AmpXHostCoordinator {
        let suite = "AmpXModuleInteractionRegressionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let coordinator = AmpXHostCoordinator(
            state: state,
            skin: ClassicModernSkin(),
            layoutStore: AmpXLayoutStore(defaults: defaults),
            screen: NSScreen.main!,
            entheaEnabled: true
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

    func testPlayerEQToggleRemovesOnlyEQAndReopensSameView() throws {
        let coordinator = self.makeCoordinator()
        let eq = try XCTUnwrap(coordinator.moduleView(for: .equalizer))
        let playlist = try XCTUnwrap(coordinator.moduleView(for: .playlist))
        let player = try XCTUnwrap(coordinator.moduleView(for: .player))
        let button = try XCTUnwrap(player.content.subviews.compactMap { $0 as? AmpXButton }
            .first { $0.accessibilityLabel() == "Equalizer" })
        let oldPlaylistY = playlist.frame.minY

        XCTAssertTrue(button.accessibilityPerformPress())

        XCTAssertTrue(coordinator.state.closed.contains(.equalizer))
        XCTAssertTrue(eq.isHidden || eq.superview == nil, "Closed EQ must stop drawing and intercepting input")
        XCTAssertFalse(playlist.isHidden)
        XCTAssertLessThan(playlist.frame.minY, oldPlaylistY)
        XCTAssertFalse(button.isActive)

        XCTAssertTrue(button.accessibilityPerformPress())

        XCTAssertIdentical(coordinator.moduleView(for: .equalizer), eq)
        XCTAssertIdentical(eq.window, coordinator.stackWindow)
        XCTAssertFalse(eq.isHidden)
        XCTAssertTrue(button.isActive)
        XCTAssertEqual(playlist.frame.minY, oldPlaylistY)
    }

    func testInitiallyClosedModuleReopensIntoStack() throws {
        var state = AmpXModuleOrder()
        state.close(.equalizer)
        let coordinator = self.makeCoordinator(state: state)
        coordinator.reopenModule(.equalizer)
        let eq = try XCTUnwrap(coordinator.moduleView(for: .equalizer))
        XCTAssertIdentical(eq.window, coordinator.stackWindow)
        XCTAssertFalse(eq.isHidden)
        XCTAssertGreaterThan(eq.frame.height, AmpXMetrics.headerHeight)
    }

    func testClosedDetachedModuleReopensInDetachedHost() throws {
        let coordinator = self.makeCoordinator()
        coordinator.detach(.equalizer, at: CGPoint(x: 700, y: 500), inheritedWidth: 490)
        let eq = try XCTUnwrap(coordinator.moduleView(for: .equalizer))
        coordinator.closeModule(.equalizer)
        coordinator.reopenModule(.equalizer)
        XCTAssertTrue(coordinator.state.detached.contains(.equalizer))
        XCTAssertNotNil(eq.window)
        XCTAssertTrue(eq.window?.isVisible == true)
        XCTAssertFalse(eq.isHidden)
        XCTAssertFalse(eq.window === coordinator.stackWindow)
    }

    func testRestoredCollapseHidesContentAndReopenPreservesCollapse() throws {
        var state = AmpXModuleOrder()
        state.setCollapsed(.equalizer, true)
        let coordinator = self.makeCoordinator(state: state)
        let eq = try XCTUnwrap(coordinator.moduleView(for: .equalizer))
        XCTAssertTrue(eq.content.isHidden)
        coordinator.closeModule(.equalizer)
        coordinator.reopenModule(.equalizer)
        XCTAssertTrue(eq.content.isHidden)
        XCTAssertFalse(eq.isHidden)
    }

    func testHeaderGripTearOffKeepsGrabbedPointUnderPointerAndRedocks() throws {
        let coordinator = self.makeCoordinator()
        let stackWindow = try XCTUnwrap(coordinator.stackWindow)
        let eq = try XCTUnwrap(coordinator.moduleView(for: .equalizer))
        let header = eq.header
        let grip = CGPoint(x: header.gripFrame.midX, y: header.gripFrame.midY)
        let start = stackWindow.convertPoint(toScreen: header.convert(grip, to: nil))
        let down = self.event(.leftMouseDown, screenPoint: start, window: stackWindow)
        XCTAssertIdentical(stackWindow.contentView?.hitTest(down.locationInWindow), header)
        header.mouseDown(with: down)
        XCTAssertTrue(coordinator.dragController.isDragging)

        let visible = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let destination = CGPoint(x: min(stackWindow.frame.maxX + 70, visible.maxX - 510), y: visible.maxY - 120)
        // Place the stack away from the destination while preserving a valid on-screen detached frame.
        stackWindow.setFrameOrigin(CGPoint(x: visible.minX, y: stackWindow.frame.minY))
        let outside = CGPoint(x: max(destination.x, stackWindow.frame.maxX + 70), y: destination.y)
        header.mouseDragged(with: self.event(.leftMouseDragged, screenPoint: outside, window: stackWindow))
        XCTAssertTrue(coordinator.state.detached.contains(.equalizer))
        let detachedWindow = try XCTUnwrap(eq.window)
        XCTAssertFalse(detachedWindow === stackWindow)
        let grabbedPoint = detachedWindow.convertPoint(toScreen: header.convert(grip, to: nil))
        XCTAssertEqual(grabbedPoint.x, outside.x, accuracy: 1)
        XCTAssertEqual(grabbedPoint.y, outside.y, accuracy: 1)
        XCTAssertFalse(eq.isHidden)

        let target = stackWindow.convertPoint(toScreen: CGPoint(x: 100, y: stackWindow.frame.height - 80))
        header.mouseDragged(with: self.event(.leftMouseDragged, screenPoint: target, window: stackWindow))
        header.mouseUp(with: self.event(.leftMouseUp, screenPoint: target, window: stackWindow))
        XCTAssertFalse(coordinator.state.detached.contains(.equalizer))
        XCTAssertIdentical(eq.window, stackWindow)
        XCTAssertFalse(coordinator.dragController.isDragging)
    }

    func testVisualizerOpensAtRightWithoutScalingLeftModules() throws {
        let coordinator = self.makeCoordinator()
        let player = try XCTUnwrap(coordinator.moduleView(for: .player))
        let eq = try XCTUnwrap(coordinator.moduleView(for: .equalizer))
        let playerSize = player.frame.size
        let eqSize = eq.frame.size
        let stackWindow = try XCTUnwrap(coordinator.stackWindow)
        let height = stackWindow.frame.height
        coordinator.reopenModule(.enthea)
        let enthea = try XCTUnwrap(coordinator.moduleView(for: .enthea))
        XCTAssertIdentical(enthea.window, stackWindow)
        XCTAssertEqual(enthea.frame, CGRect(x: 496, y: 0, width: 490, height: 290))
        XCTAssertEqual(stackWindow.frame.width, 986)
        let rightHeaderPoint = enthea.header.convert(CGPoint(x: 15, y: 10), to: nil)
        XCTAssertIdentical(stackWindow.contentView?.hitTest(rightHeaderPoint), enthea.header)
        XCTAssertEqual(stackWindow.frame.height, height)
        XCTAssertEqual(player.frame.size, playerSize)
        XCTAssertEqual(eq.frame.size, eqSize)
        coordinator.closeModule(.enthea)
        XCTAssertEqual(stackWindow.frame.width, 490)
        XCTAssertTrue(enthea.isHidden || enthea.superview == nil)
    }

    func testOpeningVisualizerAtRightScreenEdgeKeepsItsHeaderOnScreen() throws {
        let coordinator = self.makeCoordinator()
        let window = try XCTUnwrap(coordinator.stackWindow)
        let visibleFrame = try XCTUnwrap(window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame)
        guard visibleFrame.width >= 986 else {
            throw XCTSkip("The fixed two-column host is wider than this display")
        }

        window.setFrameOrigin(CGPoint(x: visibleFrame.maxX - window.frame.width, y: window.frame.minY))
        coordinator.reopenModule(.enthea)

        XCTAssertEqual(window.frame.width, 986)
        XCTAssertGreaterThanOrEqual(window.frame.minX, visibleFrame.minX - 0.5)
        XCTAssertLessThanOrEqual(window.frame.maxX, visibleFrame.maxX + 0.5)
    }

    /// Spec Revision 9: horizontal resize follows an expanded docked Playlist; saved widths are still ignored.
    func testStackHorizontalResizeFollowsPlaylistOnly() throws {
        let coordinator = self.makeCoordinator()
        let controller = try XCTUnwrap(coordinator.stackWindowController)
        let window = try XCTUnwrap(controller.window)
        controller.applyStackFrame(CGRect(x: 100, y: 100, width: 660, height: 800))
        XCTAssertEqual(window.frame.width, 490)
        XCTAssertEqual(controller.clampedFrameSize(for: window, to: CGSize(width: 800, height: 700)).width, 800)

        coordinator.handleModuleHeaderCollapse(.playlist)
        XCTAssertEqual(controller.clampedFrameSize(for: window, to: CGSize(width: 800, height: 700)).width, 490)
        coordinator.handleModuleHeaderCollapse(.playlist)

        coordinator.reopenModule(.enthea)
        XCTAssertEqual(controller.clampedFrameSize(for: window, to: CGSize(width: 1100, height: 700)).width, 1100)
        XCTAssertEqual(controller.clampedFrameSize(for: window, to: CGSize(width: 500, height: 700)).width, 986)
    }

    func testDetachedEQInWideHostKeepsReferenceSizeAndReopenIsIdempotent() throws {
        let coordinator = self.makeCoordinator()
        coordinator.reopenModule(.enthea)
        coordinator.detach(.equalizer, at: CGPoint(x: 700, y: 500), inheritedWidth: 986)
        let eq = try XCTUnwrap(coordinator.moduleView(for: .equalizer))
        let window = try XCTUnwrap(eq.window)
        XCTAssertEqual(window.frame.width, 490)
        XCTAssertEqual(eq.frame.size, CGSize(width: 490, height: AmpXMetrics.equalizerHeight))
        coordinator.reopenModule(.equalizer)
        XCTAssertIdentical(eq.window, window)
        coordinator.stackWindowController?.updateLayout()
        XCTAssertFalse(eq.isHidden)
        XCTAssertEqual(eq.frame.origin, .zero)
    }

    func testTwoColumnLayoutFitsOnlyPlaylistAndIgnoresRequestedWidth() {
        var state = AmpXModuleOrder()
        state.reopen(.enthea)
        let tall = AmpXLayout.calculate(state: state, width: 986, playlistViewportHeight: 180, availableHeight: 10000)
        let short = AmpXLayout.calculate(state: state, width: 1200, playlistViewportHeight: 180, availableHeight: tall.contentHeight - 50)
        XCTAssertEqual(short.scale, 1)
        XCTAssertEqual(short.playlistViewportHeight, 130)
        XCTAssertEqual(short.frames[.enthea], CGRect(x: 496, y: 0, width: 490, height: 290))
        XCTAssertEqual(short.frames[.player], tall.frames[.player])
        XCTAssertEqual(short.frames[.equalizer], tall.frames[.equalizer])
        state.close(.equalizer)
        state.close(.playlist)
        let onlyPlayerAndVisualizer = AmpXLayout.calculate(state: state, width: 986, playlistViewportHeight: 180, availableHeight: 10000)
        XCTAssertEqual(onlyPlayerAndVisualizer.contentHeight, 290)
    }

    func testDropGeometryKeepsVisualizerOutOfLeftOrder() {
        let coordinator = self.makeCoordinator()
        coordinator.reopenModule(.enthea)
        let geometry = coordinator.makeDropGeometry(excluding: .equalizer)
        XCTAssertFalse(geometry.orderedFrames.contains { $0.0 == .enthea })
        XCTAssertEqual(geometry.bounds.width, 490)
        coordinator.detach(.enthea, at: CGPoint(x: 700, y: 500), inheritedWidth: 490)
        coordinator.redock(.enthea, at: 0)
        XCTAssertEqual(coordinator.moduleView(for: .enthea)?.frame.minX, 496)
        XCTAssertEqual(coordinator.moduleView(for: .player)?.frame.minY, 0)
    }

    func testRepeatedDetachUsesCurrentCollapsedHeight() throws {
        let coordinator = self.makeCoordinator()
        for collapsed in [false, true, false] {
            coordinator.setCollapsed(.equalizer, collapsed)
            coordinator.detach(.equalizer, at: CGPoint(x: 700, y: 500), inheritedWidth: 490)
            let eq = try XCTUnwrap(coordinator.moduleView(for: .equalizer))
            let expected = collapsed ? AmpXCompactMetrics.equalizerHeight : AmpXMetrics.equalizerHeight
            XCTAssertEqual(eq.window?.frame.height ?? 0, expected, accuracy: 0.5)
            XCTAssertEqual(eq.frame.height, AmpXPixelGrid.align(expected, backingScale: eq.window?.backingScaleFactor ?? 1))
            coordinator.redock(.equalizer, at: 1)
        }
    }

    /// Spec Revision 9: a detached Playlist resizes in both axes; every other detached module stays fixed.
    func testOnlyDetachedPlaylistAllowsResizing() throws {
        let coordinator = self.makeCoordinator()
        for id: AmpXModuleID in [.equalizer, .playlist] {
            coordinator.detach(id, at: CGPoint(x: 700, y: 600), inheritedWidth: 490)
            let window = try XCTUnwrap(coordinator.moduleView(for: id)?.window)
            let controller = try XCTUnwrap(window.windowController as? AmpXDetachedModuleWindowController)
            let proposed = CGSize(width: 800, height: window.frame.height + 80)
            let allowed = controller.windowWillResize(window, to: proposed)
            XCTAssertEqual(allowed.width, id == .playlist ? proposed.width : 490)
            XCTAssertEqual(allowed.height, id == .playlist ? proposed.height : window.frame.height, accuracy: 0.5)
            if id == .playlist {
                var frame = window.frame
                frame.size = allowed
                coordinator.handleDetachedResize(id, frame: frame)
                XCTAssertEqual(coordinator.moduleView(for: id)?.frame.height, allowed.height)
            }
        }
    }

    func testHostedRightVisualizerAndHiddenEQRendering() throws {
        let coordinator = self.makeCoordinator()
        coordinator.reopenModule(.enthea)
        try self.capture(coordinator, named: "ampx-two-column.png")
        coordinator.closeModule(.equalizer)
        try self.capture(coordinator, named: "ampx-two-column-eq-hidden.png")
        coordinator.adjustPlaylistViewport(byHeightDelta: -100, width: 490)
        try self.capture(coordinator, named: "ampx-two-column-short-playlist.png")
    }

    /// Spec Revision 9 evidence: a wide Playlist beside the fixed-width modules and the shifted right column.
    func testWidePlaylistWithVisualizerRendering() throws {
        let coordinator = self.makeCoordinator()
        coordinator.reopenModule(.enthea)
        coordinator.setPlaylistWidth(720)
        try self.capture(coordinator, named: "ampx-wide-playlist.png")

        XCTAssertEqual(coordinator.moduleView(for: .playlist)?.frame.width, 720)
        XCTAssertEqual(coordinator.moduleView(for: .player)?.frame.width, 490)
        XCTAssertEqual(coordinator.moduleView(for: .enthea)?.frame.minX, 726)
    }

    private func capture(_ coordinator: AmpXHostCoordinator, named name: String) throws {
        let view = try XCTUnwrap(coordinator.stackWindowController?.stackViewport)
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try png.write(to: url)
        print("AMPX_INTERACTION_CAPTURE \(url.path)")
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
