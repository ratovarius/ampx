@testable import AmpX
import XCTest

@MainActor
final class AmpXTheaterTests: XCTestCase {
    func testTheaterPreservesHostIdentityAndPresentation() throws {
        let hosts = AmpXHostCoordinator(
            state: AmpXModuleState(),
            skin: ClassicModernSkin(),
            layoutStore: makeIsolatedLayoutStore(),
            entheaEnabled: true
        )
        hosts.reopenModule(.enthea)
        hosts.showAll()
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

    func testTheaterRestoresEntheaWindowFrameAndLeavesDockedNeighbours() throws {
        let hosts = AmpXHostCoordinator(
            state: AmpXModuleState(),
            skin: ClassicModernSkin(),
            layoutStore: makeIsolatedLayoutStore(),
            screen: AmpXTestScreen.standard,
            entheaEnabled: true
        )
        hosts.reopenModule(.enthea)
        hosts.showAll()
        defer { AmpXModuleID.allCases.forEach { hosts.window(for: $0)?.orderOut(nil) } }

        let view = try XCTUnwrap(hosts.moduleView(for: .enthea))
        let identity = ObjectIdentifier(view.content)
        let entheaFrame = try XCTUnwrap(hosts.window(for: .enthea)?.frame)
        let equalizerHeight = try XCTUnwrap(hosts.window(for: .equalizer)?.frame.height)
        let under = CGRect(x: entheaFrame.minX, y: entheaFrame.minY - equalizerHeight, width: entheaFrame.width, height: equalizerHeight)
        hosts.applyFrames([.equalizer: under])

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
        XCTAssertEqual(hosts.window(for: .equalizer)?.frame, under)

        controller.exit()
        XCTAssertEqual(ObjectIdentifier(view.content), identity)
        XCTAssertEqual(hosts.window(for: .enthea)?.frame, entheaFrame)
        XCTAssertEqual(hosts.window(for: .equalizer)?.frame, under)
        XCTAssertEqual(presentation, [])
    }

    func testTheaterExpandsCollapsedEntheaBeforeEntering() throws {
        let hosts = AmpXHostCoordinator(
            state: AmpXModuleState(),
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
            state: AmpXModuleState(),
            skin: ClassicModernSkin(),
            layoutStore: makeIsolatedLayoutStore(),
            entheaEnabled: true
        )
        hosts.reopenModule(.enthea)
        hosts.showAll()

        var presentation: NSApplication.PresentationOptions = []
        let controller = AmpXTheaterController(
            hosts: hosts,
            screenFrame: { CGRect(x: 0, y: 0, width: 1200, height: 800) },
            getPresentation: { presentation },
            setPresentation: { presentation = $0 }
        )
        controller.enter()
        XCTAssertTrue(controller.isActive)

        controller.exit()

        XCTAssertFalse(controller.isActive)
        // ENTHEA returns to its own window after theater teardown.
        XCTAssertNotNil(hosts.moduleView(for: .enthea))
        XCTAssertEqual(hosts.window(for: .enthea)?.isVisible, true)
        XCTAssertTrue(hosts.moduleView(for: .enthea)?.window === hosts.window(for: .enthea))
    }
}
