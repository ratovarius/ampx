@testable import AmpX
import XCTest

final class AmpXBootstrapTests: XCTestCase {
    func testBundledFontsRegister() {
        AmpXFonts.register()
        XCTAssertNotNil(AmpXFonts.font(size: 12))
    }

    @MainActor
    func testFixedSizeModuleWindowsRejectResize() throws {
        let coordinator = AmpXHostCoordinator(
            state: AmpXModuleState(),
            skin: ClassicModernSkin(),
            layoutStore: makeIsolatedLayoutStore(),
            screen: AmpXTestScreen.standard
        )
        coordinator.showAll()
        defer { coordinator.hideAllWindowsForTesting() }
        let window = try XCTUnwrap(coordinator.window(for: .equalizer))
        let controller = try XCTUnwrap(window.windowController as? AmpXModuleWindowController)

        let proposed = controller.windowWillResize(window, to: NSSize(width: 300, height: 80))
        XCTAssertEqual(proposed, window.frame.size)
    }

    @MainActor
    func testPlaylistWindowRejectsResizeBelowMinimumWidth() throws {
        let coordinator = AmpXHostCoordinator(
            state: AmpXModuleState(),
            skin: ClassicModernSkin(),
            layoutStore: makeIsolatedLayoutStore(),
            screen: AmpXTestScreen.standard
        )
        coordinator.showAll()
        defer { coordinator.hideAllWindowsForTesting() }
        let window = try XCTUnwrap(coordinator.window(for: .playlist))
        let controller = try XCTUnwrap(window.windowController as? AmpXModuleWindowController)

        let proposed = controller.windowWillResize(window, to: NSSize(width: 300, height: window.frame.height))
        XCTAssertEqual(proposed.width, AmpXMetrics.minimumPlaylistWidth)
    }
}
