@testable import AmpX
import AppKit
import XCTest

/// Winamp title-bar dragging: the Player carries its docked cluster, any other window moves alone,
/// and edges snap within 10 pt to other windows and to the screen (spec rules 2–4).
@MainActor
final class AmpXWindowDragTests: XCTestCase {
    private func makeCoordinator(enthea: Bool = false) -> AmpXHostCoordinator {
        var state = AmpXModuleState()
        if enthea {
            state.reopen(.enthea)
        }
        let coordinator = AmpXHostCoordinator(
            state: state,
            skin: ClassicModernSkin(),
            layoutStore: self.makeIsolatedLayoutStore(),
            screen: AmpXTestScreen.standard,
            entheaEnabled: enthea,
            terminate: {}
        )
        self.addTeardownBlock { @MainActor in coordinator.hideAllWindowsForTesting() }
        coordinator.showAll()
        return coordinator
    }

    private func frame(_ coordinator: AmpXHostCoordinator, _ id: AmpXModuleID) throws -> CGRect {
        try XCTUnwrap(coordinator.window(for: id)?.frame)
    }

    /// Drags `id`'s title bar by `delta`, grabbing it at its top-left corner.
    private func drag(_ coordinator: AmpXHostCoordinator, _ id: AmpXModuleID, by delta: CGVector) throws {
        let start = try self.frame(coordinator, id)
        let grab = CGPoint(x: start.minX + 20, y: start.maxY - 5)
        let session = coordinator.dragSession
        session.begin(id, at: grab)
        session.move(to: CGPoint(x: grab.x + delta.dx / 2, y: grab.y + delta.dy / 2))
        session.end(at: CGPoint(x: grab.x + delta.dx, y: grab.y + delta.dy))
    }

    func testPlayerDragMovesWholeChain() throws {
        let coordinator = self.makeCoordinator()
        let before = coordinator.openFrames()

        try self.drag(coordinator, .player, by: CGVector(dx: 50, dy: -30))

        for id: AmpXModuleID in [.player, .equalizer, .playlist] {
            XCTAssertEqual(try self.frame(coordinator, id), before[id]?.offsetBy(dx: 50, dy: -30), "\(id)")
        }
    }

    func testEqualizerDragMovesOnlyEqualizer() throws {
        let coordinator = self.makeCoordinator()
        let player = try self.frame(coordinator, .player)
        let playlist = try self.frame(coordinator, .playlist)
        let equalizer = try self.frame(coordinator, .equalizer)

        try self.drag(coordinator, .equalizer, by: CGVector(dx: 300, dy: -200))

        XCTAssertEqual(try self.frame(coordinator, .equalizer), equalizer.offsetBy(dx: 300, dy: -200))
        XCTAssertEqual(try self.frame(coordinator, .player), player)
        XCTAssertEqual(try self.frame(coordinator, .playlist), playlist)
    }

    func testReleaseNearEdgeSnapsFlush() throws {
        let coordinator = self.makeCoordinator()
        let player = try self.frame(coordinator, .player)
        let equalizer = try self.frame(coordinator, .equalizer)
        // 7 pt right of the Player's right edge, top 4 pt below the Player's top.
        let delta = CGVector(dx: player.maxX + 7 - equalizer.minX, dy: player.maxY - 4 - equalizer.maxY)

        try self.drag(coordinator, .equalizer, by: delta)

        let snapped = try self.frame(coordinator, .equalizer)
        XCTAssertEqual(snapped.minX, player.maxX)
        XCTAssertEqual(snapped.maxY, player.maxY)
    }

    func testReleaseOffsetAlongEdgeStaysOffset() throws {
        let coordinator = self.makeCoordinator()
        let player = try self.frame(coordinator, .player)

        try self.drag(coordinator, .equalizer, by: CGVector(dx: 40, dy: 0))

        let equalizer = try self.frame(coordinator, .equalizer)
        XCTAssertEqual(equalizer.minX, player.minX + 40, "Winamp never re-aligns a docked window on drop")
        XCTAssertEqual(equalizer.maxY, player.minY)
    }

    func testSnapsToScreenEdge() throws {
        let coordinator = self.makeCoordinator(enthea: true)
        let enthea = try self.frame(coordinator, .enthea)
        let visible = AmpXTestScreen.standard.visibleFrame

        try self.drag(coordinator, .enthea, by: CGVector(dx: visible.minX + 6 - enthea.minX, dy: -500))

        XCTAssertEqual(try self.frame(coordinator, .enthea).minX, visible.minX)
    }

    func testNoChildLinksRemainAfterDrag() throws {
        let coordinator = self.makeCoordinator()
        try self.drag(coordinator, .player, by: CGVector(dx: 30, dy: 30))

        for id: AmpXModuleID in [.player, .equalizer, .playlist] {
            XCTAssertNil(coordinator.window(for: id)?.parent, "\(id)")
            XCTAssertTrue(coordinator.window(for: id)?.childWindows?.isEmpty ?? true, "\(id)")
        }
        XCTAssertFalse(coordinator.dragSession.isDragging)
    }

    func testDragPersistsFinalFrames() throws {
        let store = self.makeIsolatedLayoutStore()
        let coordinator = AmpXHostCoordinator(
            state: AmpXModuleState(),
            skin: ClassicModernSkin(),
            layoutStore: store,
            screen: AmpXTestScreen.standard,
            entheaEnabled: false,
            terminate: {}
        )
        self.addTeardownBlock { @MainActor in coordinator.hideAllWindowsForTesting() }
        coordinator.showAll()

        try self.drag(coordinator, .equalizer, by: CGVector(dx: 300, dy: -200))

        XCTAssertEqual(store.load().frames[.equalizer], try self.frame(coordinator, .equalizer))
    }

    func testCollapseCancelsTitleDrag() throws {
        let coordinator = self.makeCoordinator()
        let player = try self.frame(coordinator, .player)
        coordinator.dragSession.begin(.player, at: CGPoint(x: player.midX, y: player.maxY - 5))
        XCTAssertTrue(coordinator.dragSession.isDragging)

        coordinator.setCollapsed(.equalizer, true)

        XCTAssertFalse(coordinator.dragSession.isDragging)
        XCTAssertNil(coordinator.window(for: .equalizer)?.parent)
    }

    func testHeaderTitleMouseDownStartsTitleDrag() throws {
        let coordinator = self.makeCoordinator()
        let header = try XCTUnwrap(coordinator.moduleView(for: .equalizer)?.header)
        let window = try XCTUnwrap(header.window)
        let point = header.convert(CGPoint(x: header.bounds.midX, y: header.bounds.midY), to: nil)
        let down = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))

        header.mouseDown(with: down)
        XCTAssertTrue(coordinator.dragSession.isDragging)

        let up = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        header.mouseUp(with: up)
        XCTAssertFalse(coordinator.dragSession.isDragging)
    }
}
