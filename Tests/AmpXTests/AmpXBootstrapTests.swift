@testable import AmpX
import XCTest

final class AmpXBootstrapTests: XCTestCase {
    func testBundledFontsRegister() {
        AmpXFonts.register()
        XCTAssertNotNil(AmpXFonts.font(size: 12))
    }

    @MainActor
    func testStackWindowSetsMinimumContentWidth() {
        let coordinator = AmpXHostCoordinator(
            state: AmpXModuleOrder(),
            skin: ClassicModernSkin(),
            layoutStore: makeIsolatedLayoutStore()
        )
        coordinator.showStack()
        XCTAssertEqual(coordinator.stackWindow?.contentMinSize.width, 490)
    }

    @MainActor
    func testStackWindowRejectsResizeBelowMinimumWidth() throws {
        let coordinator = AmpXHostCoordinator(
            state: AmpXModuleOrder(),
            skin: ClassicModernSkin(),
            layoutStore: makeIsolatedLayoutStore()
        )
        coordinator.showStack()
        guard let window = coordinator.stackWindow else {
            return XCTFail("Expected stack window")
        }

        let controller = try XCTUnwrap(window.windowController as? AmpXStackWindowController)
        let proposed = controller.clampedFrameSize(
            for: window,
            to: NSSize(width: 300, height: window.frame.height)
        )
        XCTAssertEqual(proposed.width, 490)
    }
}
