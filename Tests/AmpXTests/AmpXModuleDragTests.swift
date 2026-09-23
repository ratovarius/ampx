@testable import AmpX
import XCTest

final class AmpXModuleDragTests: XCTestCase {
    func testDropIndexBetweenModulesUsesMidpoints() {
        let geometry = AmpXDropGeometry(
            bounds: CGRect(x: 0, y: 0, width: 490, height: 300),
            orderedFrames: [
                (.player, CGRect(x: 0, y: 0, width: 490, height: 100)),
                (.playlist, CGRect(x: 0, y: 106, width: 490, height: 190)),
            ]
        )

        XCTAssertEqual(
            AmpXModuleDragController.dropIndex(geometry: geometry, point: CGPoint(x: 20, y: 104)),
            1
        )
    }

    func testDropIndexRejectsOutOfBoundsPoints() {
        let geometry = AmpXDropGeometry(
            bounds: CGRect(x: 0, y: 0, width: 490, height: 300),
            orderedFrames: [
                (.player, CGRect(x: 0, y: 0, width: 490, height: 100)),
                (.playlist, CGRect(x: 0, y: 106, width: 490, height: 190)),
            ]
        )

        XCTAssertNil(AmpXModuleDragController.dropIndex(geometry: geometry, point: CGPoint(x: -1, y: 104)))
        XCTAssertNil(AmpXModuleDragController.dropIndex(geometry: geometry, point: CGPoint(x: 20, y: -1)))
        XCTAssertNil(AmpXModuleDragController.dropIndex(geometry: geometry, point: CGPoint(x: 491, y: 104)))
        XCTAssertNil(AmpXModuleDragController.dropIndex(geometry: geometry, point: CGPoint(x: 20, y: 301)))
    }

    func testDropIndexAboveFirstModule() {
        let geometry = AmpXDropGeometry(
            bounds: CGRect(x: 0, y: 0, width: 490, height: 300),
            orderedFrames: [
                (.player, CGRect(x: 0, y: 0, width: 490, height: 100)),
                (.playlist, CGRect(x: 0, y: 106, width: 490, height: 190)),
            ]
        )

        XCTAssertEqual(
            AmpXModuleDragController.dropIndex(geometry: geometry, point: CGPoint(x: 20, y: 10)),
            0
        )
    }

    func testDropIndexBelowLastModule() {
        let geometry = AmpXDropGeometry(
            bounds: CGRect(x: 0, y: 0, width: 490, height: 300),
            orderedFrames: [
                (.player, CGRect(x: 0, y: 0, width: 490, height: 100)),
                (.playlist, CGRect(x: 0, y: 106, width: 490, height: 190)),
            ]
        )

        XCTAssertEqual(
            AmpXModuleDragController.dropIndex(geometry: geometry, point: CGPoint(x: 20, y: 280)),
            2
        )
    }

    func testDropIndexWithEmptyStackReturnsZero() {
        let geometry = AmpXDropGeometry(
            bounds: CGRect(x: 0, y: 0, width: 490, height: 300),
            orderedFrames: []
        )

        XCTAssertEqual(
            AmpXModuleDragController.dropIndex(geometry: geometry, point: CGPoint(x: 20, y: 50)),
            0
        )
    }

    func testFullOrderIndexMapsThroughClosedInterveningEntry() {
        var state = AmpXModuleOrder()
        state.close(.equalizer)

        XCTAssertEqual(
            AmpXModuleDragController.fullOrderIndex(forVisibleDropIndex: 1, excluding: .playlist, in: state),
            1
        )
    }

    func testFullOrderIndexMapsThroughDetachedInterveningEntry() {
        var state = AmpXModuleOrder()
        state.detach(.equalizer)

        XCTAssertEqual(
            AmpXModuleDragController.fullOrderIndex(forVisibleDropIndex: 1, excluding: .playlist, in: state),
            1
        )
    }

    @MainActor
    func testDetachRedockTransfersSameModuleViewInstance() throws {
        let coordinator = self.makeCoordinator()
        coordinator.showStack()
        let viewBefore = try XCTUnwrap(coordinator.moduleView(for: .equalizer))

        coordinator.detach(.equalizer, at: CGPoint(x: 200, y: 400), inheritedWidth: 490)
        XCTAssertTrue(coordinator.state.detached.contains(.equalizer))
        XCTAssertIdentical(coordinator.moduleView(for: .equalizer), viewBefore)

        coordinator.redock(.equalizer, at: 0)
        XCTAssertIdentical(coordinator.moduleView(for: .equalizer), viewBefore)
        XCTAssertFalse(coordinator.state.detached.contains(.equalizer))
    }

    @MainActor
    func testDetachKeepsReferenceWidth() {
        let coordinator = self.makeCoordinator()
        coordinator.showStack()
        coordinator.stackWindow?.setFrame(
            CGRect(x: 100, y: 100, width: 661.5, height: 600),
            display: false
        )

        coordinator.detach(.equalizer, at: CGPoint(x: 200, y: 400), inheritedWidth: 661.5)

        XCTAssertEqual(coordinator.detachedWindowFrame(for: .equalizer)?.width ?? 0, 490, accuracy: 0.5)
    }

    @MainActor
    func testRedockKeepsReferenceWidth() {
        let coordinator = self.makeCoordinator()
        coordinator.showStack()
        coordinator.stackWindow?.setFrame(
            CGRect(x: 100, y: 100, width: 661.5, height: 600),
            display: false
        )
        coordinator.detach(.equalizer, at: CGPoint(x: 200, y: 400), inheritedWidth: 490)

        coordinator.redock(.equalizer, at: 0)
        coordinator.stackWindowController?.updateLayout()

        let moduleWidth = coordinator.moduleView(for: .equalizer)?.frame.width ?? 0
        XCTAssertEqual(moduleWidth, 490, accuracy: 0.5)
    }

    @MainActor
    func testMenuRedockShowsHiddenStackFirst() {
        let coordinator = self.makeCoordinator()
        coordinator.showStack()
        coordinator.detach(.equalizer, at: CGPoint(x: 200, y: 400), inheritedWidth: 490)
        coordinator.closeStack()
        XCTAssertFalse(coordinator.isStackVisible)

        coordinator.menuRedock(.equalizer, at: 0)

        XCTAssertTrue(coordinator.isStackVisible)
        XCTAssertFalse(coordinator.state.detached.contains(.equalizer))
    }

    @MainActor
    func testMoveCommandsRedockDetachedModule() {
        let coordinator = self.makeCoordinator()
        coordinator.showStack()
        coordinator.detach(.equalizer, at: CGPoint(x: 200, y: 400), inheritedWidth: 490)
        coordinator.noteFocusedModule(.equalizer)
        XCTAssertTrue(coordinator.state.detached.contains(.equalizer))

        coordinator.performModuleCommand(.moveDown)
        XCTAssertFalse(coordinator.state.detached.contains(.equalizer))
        XCTAssertEqual(coordinator.state.order.last, .equalizer)

        coordinator.detach(.playlist, at: CGPoint(x: 220, y: 420), inheritedWidth: 490)
        coordinator.noteFocusedModule(.playlist)
        coordinator.performModuleCommand(.moveUp)
        XCTAssertFalse(coordinator.state.detached.contains(.playlist))
        // After Player at index 0, move-up inserts at index 1.
        XCTAssertEqual(coordinator.state.order.firstIndex(of: .playlist), 1)
    }

    @MainActor
    func testCollapseDuringDragCancelsWithoutChangingOrder() {
        let coordinator = self.makeCoordinator()
        coordinator.showStack()
        let orderBefore = coordinator.state.order

        coordinator.dragController.beginGripDrag(moduleID: .equalizer, event: self.makeMouseEvent())
        coordinator.setCollapsed(.equalizer, true)

        XCTAssertEqual(coordinator.state.order, orderBefore)
        XCTAssertFalse(coordinator.dragController.isDragging)
    }

    @MainActor
    private func makeCoordinator() -> AmpXHostCoordinator {
        AmpXHostCoordinator(
            state: AmpXModuleOrder(),
            skin: ClassicModernSkin(),
            layoutStore: makeIsolatedLayoutStore(),
            screen: NSScreen.main!
        )
    }

    private func makeMouseEvent() -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: CGPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )!
    }
}
