@testable import AmpX
import XCTest

@MainActor
final class AmpXTheaterTests: XCTestCase {
    func testTheaterPreservesHostIdentityAndPresentation() throws {
        let hosts = AmpXHostCoordinator(
            state: AmpXModuleOrder(),
            skin: ClassicModernSkin(),
            layoutStore: makeIsolatedLayoutStore(),
            entheaEnabled: true
        )
        hosts.reopenModule(.enthea)
        let view = try XCTUnwrap(hosts.moduleView(for: .enthea))
        let identity = ObjectIdentifier(view.content)
        let previousFrame = view.frame
        var presentation: NSApplication.PresentationOptions = []
        let controller = AmpXTheaterController(
            hosts: hosts,
            screenFrame: { CGRect(x: 0, y: 0, width: 1200, height: 800) },
            getPresentation: { presentation },
            setPresentation: { presentation = $0 }
        )
        controller.enter()
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(view.content.bounds.size, CGSize(width: 1200, height: 800))
        XCTAssertTrue(presentation.contains(.autoHideDock))
        controller.exit()
        XCTAssertEqual(ObjectIdentifier(view.content), identity)
        XCTAssertEqual(view.frame, previousFrame)
        XCTAssertEqual(presentation, [])
    }

    func testTheaterPreservesDetachedHostIdentityAndWindowFrame() throws {
        let hosts = AmpXHostCoordinator(
            state: AmpXModuleOrder(),
            skin: ClassicModernSkin(),
            layoutStore: makeIsolatedLayoutStore(),
            entheaEnabled: true
        )
        hosts.reopenModule(.enthea)
        hosts.showStack()
        hosts.detach(.enthea, at: CGPoint(x: 400, y: 500), inheritedWidth: 490)

        let view = try XCTUnwrap(hosts.moduleView(for: .enthea))
        let identity = ObjectIdentifier(view.content)
        let previousWindowFrame = try XCTUnwrap(hosts.detachedWindowFrame(for: .enthea))

        var presentation: NSApplication.PresentationOptions = []
        let controller = AmpXTheaterController(
            hosts: hosts,
            screenFrame: { CGRect(x: 0, y: 0, width: 1200, height: 800) },
            getPresentation: { presentation },
            setPresentation: { presentation = $0 }
        )

        controller.enter()
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(view.content.bounds.size, CGSize(width: 1200, height: 800))

        controller.exit()
        XCTAssertEqual(ObjectIdentifier(view.content), identity)

        let restoredWindowFrame = try XCTUnwrap(hosts.detachedWindowFrame(for: .enthea))
        let clampedPrevious = try AmpXLayoutStore.clampedToVisibleFrame(
            previousWindowFrame,
            screen: XCTUnwrap(NSScreen.main)
        )
        XCTAssertEqual(restoredWindowFrame.origin.x, clampedPrevious.origin.x, accuracy: 1)
        XCTAssertEqual(restoredWindowFrame.origin.y, clampedPrevious.origin.y, accuracy: 1)
        XCTAssertEqual(restoredWindowFrame.width, clampedPrevious.width, accuracy: 1)
        XCTAssertEqual(restoredWindowFrame.height, clampedPrevious.height, accuracy: 1)
        XCTAssertEqual(presentation, [])
    }

    func testTheaterExpandsCollapsedEntheaBeforeEntering() throws {
        let hosts = AmpXHostCoordinator(
            state: AmpXModuleOrder(),
            skin: ClassicModernSkin(),
            layoutStore: makeIsolatedLayoutStore(),
            entheaEnabled: true
        )
        hosts.reopenModule(.enthea)
        hosts.setCollapsed(.enthea, true)
        XCTAssertTrue(hosts.state.collapsed.contains(.enthea))

        var presentation: NSApplication.PresentationOptions = []
        let controller = AmpXTheaterController(
            hosts: hosts,
            screenFrame: { CGRect(x: 0, y: 0, width: 1200, height: 800) },
            getPresentation: { presentation },
            setPresentation: { presentation = $0 }
        )
        controller.enter()
        defer { controller.exit() }

        XCTAssertTrue(controller.isActive)
        XCTAssertFalse(hosts.state.collapsed.contains(.enthea))
        let view = try XCTUnwrap(hosts.moduleView(for: .enthea))
        XCTAssertEqual(view.content.bounds.size, CGSize(width: 1200, height: 800))
    }

    func testTheaterExitRefreshesVisibilityAfterDeactivating() {
        let hosts = AmpXHostCoordinator(
            state: AmpXModuleOrder(),
            skin: ClassicModernSkin(),
            layoutStore: makeIsolatedLayoutStore(),
            entheaEnabled: true
        )
        hosts.reopenModule(.enthea)
        hosts.showStack()
        hosts.detach(.enthea, at: CGPoint(x: 400, y: 500), inheritedWidth: 490)

        var presentation: NSApplication.PresentationOptions = []
        let controller = AmpXTheaterController(
            hosts: hosts,
            screenFrame: { CGRect(x: 0, y: 0, width: 1200, height: 800) },
            getPresentation: { presentation },
            setPresentation: { presentation = $0 }
        )
        controller.enter()
        XCTAssertTrue(controller.isActive)

        hosts.closeStack()
        controller.exit()

        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(hosts.state.detached.contains(.enthea))
        // Detached ENTHEA should remain reachable after theater teardown.
        XCTAssertNotNil(hosts.moduleView(for: .enthea))
        XCTAssertNotNil(hosts.detachedWindowFrame(for: .enthea))
    }
}
