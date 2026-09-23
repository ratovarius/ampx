@testable import AmpX
import AppKit
import XCTest

@MainActor
final class AmpXCompactChromeTests: XCTestCase {
    func testCompactControlDoesNotCaptureItsNeighborsPoint() {
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 60, height: 24))
        let first = AmpXButton(skin: ClassicModernSkin())
        let second = AmpXButton(skin: ClassicModernSkin())
        first.frame = CGRect(x: 0, y: 0, width: 20, height: 24)
        second.frame = CGRect(x: 22, y: 0, width: 20, height: 24)
        first.confinesHitTestingToBounds = true
        second.confinesHitTestingToBounds = true
        root.addSubview(first)
        root.addSubview(second)
        XCTAssertNil(first.hitTest(CGPoint(x: 21, y: 12)))
        XCTAssertIdentical(root.hitTest(CGPoint(x: 23, y: 12)), second)
    }

    func testChromeActionsAreBoundedAndDisabledFacesRemainProtected() {
        for moduleID in [AmpXModuleID.player, .equalizer, .playlist] {
            let shell = AmpXCompactModuleView(moduleID: moduleID, skin: ClassicModernSkin())
            shell.frame = CGRect(x: 0, y: 0, width: 490, height: AmpXCompactMetrics.playerHeight)
            shell.layoutSubtreeIfNeeded()
            XCTAssertEqual(shell.minimizeButton != nil, moduleID == .player)
            XCTAssertEqual(shell.chromeLayout.minimize != nil, moduleID == .player)
            XCTAssertEqual(shell.subviews.compactMap { $0 as? AmpXButton }.count, moduleID == .player ? 3 : 2)
            var actions: [String] = []
            shell.onExpand = { actions.append("expand") }
            shell.onClose = { actions.append("close") }
            shell.onMinimize = { actions.append("minimize") }
            for button in [shell.expandButton, shell.closeButton] + [shell.minimizeButton].compactMap({ $0 }) {
                XCTAssertTrue(button.isAccessibilityElement(), "Compact chrome must be discoverable by assistive tools")
                XCTAssertTrue(shell.bounds.contains(button.frame))
                let point = CGPoint(x: button.frame.midX, y: button.frame.midY)
                XCTAssertIdentical(shell.hitTest(point), button)
                XCTAssertTrue(button.accessibilityPerformPress())
                button.isEnabled = false
                XCTAssertFalse(button.accessibilityPerformPress())
                XCTAssertIdentical(shell.hitTest(point), shell)
                XCTAssertTrue(shell.protectedRects.contains { $0.contains(point) })
            }
            XCTAssertEqual(actions, moduleID == .player ? ["expand", "close", "minimize"] : ["expand", "close"])
        }
    }
}
