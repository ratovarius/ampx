@testable import AmpX
import AppKit
import XCTest

@MainActor
final class AmpXModuleInteractionRegressionTests: XCTestCase {
    private func makeCoordinator(state: AmpXModuleState = AmpXModuleState()) -> AmpXHostCoordinator {
        let suite = "AmpXModuleInteractionRegressionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let coordinator = AmpXHostCoordinator(
            state: state,
            skin: ClassicModernSkin(),
            layoutStore: AmpXLayoutStore(defaults: defaults, screen: AmpXTestScreen.standard),
            screen: AmpXTestScreen.standard,
            entheaEnabled: true
        )
        addTeardownBlock { @MainActor in coordinator.hideAllWindowsForTesting() }
        coordinator.showAll()
        return coordinator
    }

    func testPlayerEQToggleClosesOnlyEQLeavingTheGapAndReopensSameView() throws {
        let coordinator = self.makeCoordinator()
        let eq = try XCTUnwrap(coordinator.moduleView(for: .equalizer))
        let player = try XCTUnwrap(coordinator.moduleView(for: .player))
        let button = try XCTUnwrap(player.content.subviews.compactMap { $0 as? AmpXButton }
            .first { $0.accessibilityLabel() == "Equalizer" })
        let eqWindow = try XCTUnwrap(eq.window)
        let playlistFrame = try XCTUnwrap(coordinator.window(for: .playlist)?.frame)

        XCTAssertTrue(button.accessibilityPerformPress())

        XCTAssertTrue(coordinator.state.closed.contains(.equalizer))
        XCTAssertFalse(eqWindow.isVisible, "Closed EQ must stop drawing and intercepting input")
        XCTAssertEqual(coordinator.window(for: .playlist)?.frame, playlistFrame, "Winamp leaves the gap")
        XCTAssertFalse(button.isActive)

        XCTAssertTrue(button.accessibilityPerformPress())

        XCTAssertIdentical(coordinator.moduleView(for: .equalizer), eq)
        XCTAssertIdentical(eq.window, eqWindow)
        XCTAssertTrue(eqWindow.isVisible)
        XCTAssertTrue(button.isActive)
        XCTAssertEqual(coordinator.window(for: .playlist)?.frame, playlistFrame)
    }

    func testInitiallyClosedModuleReopensAtItsDefaultFrame() throws {
        var state = AmpXModuleState()
        state.close(.equalizer)
        let coordinator = self.makeCoordinator(state: state)
        coordinator.reopenModule(.equalizer)
        let eq = try XCTUnwrap(coordinator.moduleView(for: .equalizer))
        let player = try XCTUnwrap(coordinator.window(for: .player))
        XCTAssertIdentical(eq.window, coordinator.window(for: .equalizer))
        XCTAssertFalse(eq.isHidden)
        XCTAssertEqual(eq.window?.frame.maxY, player.frame.minY)
        XCTAssertGreaterThan(eq.frame.height, AmpXMetrics.headerHeight)
    }

    func testRestoredCollapseHidesContentAndReopenPreservesCollapse() throws {
        var state = AmpXModuleState()
        state.setCollapsed(.equalizer, true)
        let coordinator = self.makeCoordinator(state: state)
        let eq = try XCTUnwrap(coordinator.moduleView(for: .equalizer))
        XCTAssertTrue(eq.content.isHidden)
        coordinator.closeModule(.equalizer)
        coordinator.reopenModule(.equalizer)
        XCTAssertTrue(eq.content.isHidden)
        XCTAssertFalse(eq.isHidden)
    }

    func testVisualizerOpensRightOfPlayerWithoutMovingOrScalingOthers() throws {
        let coordinator = self.makeCoordinator()
        let before = coordinator.openFrames()
        let playerSize = try XCTUnwrap(coordinator.moduleView(for: .player)).frame.size

        coordinator.reopenModule(.enthea)

        let enthea = try XCTUnwrap(coordinator.window(for: .enthea))
        let player = try XCTUnwrap(coordinator.window(for: .player))
        XCTAssertEqual(enthea.frame.minX, player.frame.maxX)
        XCTAssertEqual(enthea.frame.maxY, player.frame.maxY)
        XCTAssertEqual(enthea.frame.size, CGSize(width: 490, height: 290))
        XCTAssertEqual(coordinator.moduleView(for: .player)?.frame.size, playerSize)
        for (id, frame) in before {
            XCTAssertEqual(coordinator.window(for: id)?.frame, frame, "\(id)")
        }

        coordinator.closeModule(.enthea)
        XCTAssertFalse(enthea.isVisible)
    }

    func testCollapseTogglesUseWholePointWindowHeights() throws {
        let coordinator = self.makeCoordinator()
        for collapsed in [false, true, false] {
            coordinator.setCollapsed(.equalizer, collapsed)
            let window = try XCTUnwrap(coordinator.window(for: .equalizer))
            let expected = (collapsed ? AmpXCompactMetrics.equalizerHeight : AmpXMetrics.equalizerHeight).rounded()
            XCTAssertEqual(window.frame.height, expected)
            XCTAssertEqual(coordinator.moduleView(for: .equalizer)?.frame.height, expected)
        }
    }

    /// Spec Revision 9: only an expanded Playlist window resizes; every other module stays fixed.
    func testOnlyPlaylistWindowAllowsResizing() throws {
        let coordinator = self.makeCoordinator()
        for id: AmpXModuleID in [.player, .equalizer, .playlist] {
            let window = try XCTUnwrap(coordinator.window(for: id))
            let controller = try XCTUnwrap(window.windowController as? AmpXModuleWindowController)
            let proposed = CGSize(width: 800, height: window.frame.height + 80)
            let allowed = controller.windowWillResize(window, to: proposed)
            XCTAssertEqual(allowed.width, id == .playlist ? proposed.width : 490)
            XCTAssertEqual(allowed.height, id == .playlist ? proposed.height : window.frame.height, accuracy: 0.5)
        }
    }

    func testLiveTopEdgeResizeOfPlaylistLeavesWindowBelowInPlace() throws {
        let coordinator = self.makeCoordinator()
        let playlist = try XCTUnwrap(coordinator.window(for: .playlist))
        let eqHeight = try XCTUnwrap(coordinator.window(for: .equalizer)).frame.height
        let below = CGRect(x: playlist.frame.minX, y: playlist.frame.minY - eqHeight, width: 490, height: eqHeight)
        coordinator.applyFrames([.equalizer: below])

        coordinator.moduleWindowWillStartLiveResize(.playlist)
        var grown = playlist.frame
        grown.size.height += 60
        playlist.setFrame(grown, display: false)
        coordinator.moduleWindowDidLiveResize(.playlist, frame: grown)
        coordinator.moduleWindowDidEndLiveResize(.playlist, frame: grown)

        XCTAssertEqual(coordinator.window(for: .equalizer)?.frame, below)
        XCTAssertEqual(coordinator.moduleView(for: .playlist)?.frame.height, grown.height)
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
