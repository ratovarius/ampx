@testable import AmpX
import AppKit
import XCTest

@MainActor
final class AmpXCompactVisibilityTests: XCTestCase {
    func testEveryHostGateAppliesToBothPresentations() {
        for collapsed in [false, true] {
            let visible = AmpXVisibilityInputs(
                collapsed: collapsed,
                closed: false,
                windowVisible: true,
                miniaturized: false,
                occluded: false,
                intersectsViewport: true
            )
            XCTAssertEqual(
                visible.presentationVisibility(hasCompactPresentation: true),
                AmpXPresentationVisibility(expanded: !collapsed, compact: collapsed)
            )
            XCTAssertEqual(
                visible.presentationVisibility(hasCompactPresentation: false),
                AmpXPresentationVisibility(expanded: !collapsed, compact: false)
            )
            let gates: [WritableKeyPath<AmpXVisibilityInputs, Bool>] = [
                \.closed, \.windowVisible, \.miniaturized, \.occluded, \.intersectsViewport,
            ]
            for gate in gates {
                var input = visible
                input[keyPath: gate].toggle()
                XCTAssertEqual(
                    input.presentationVisibility(hasCompactPresentation: true),
                    AmpXPresentationVisibility(expanded: false, compact: false)
                )
            }
        }
    }

    func testActualDisplayLinksStopBeforeTheOtherPresentationStarts() {
        let expanded = AmpXModuleContent(skin: ClassicModernSkin())
        let compact = AmpXCompactModuleView(moduleID: .player, skin: ClassicModernSkin())
        let first = AmpXContinuousView(skin: ClassicModernSkin())
        let second = AmpXContinuousView(skin: ClassicModernSkin())
        expanded.addSubview(first)
        compact.addSubview(second)
        let module = AmpXModuleView(moduleID: .player, content: expanded, skin: ClassicModernSkin(), compactContent: compact)
        var events: [String] = []
        first.displayLinkStarter = { _ in events.append("expanded start") }
        first.displayLinkStopper = { _ in events.append("expanded stop") }
        second.displayLinkStarter = { _ in events.append("compact start") }
        second.displayLinkStopper = { _ in events.append("compact stop") }
        module.applyPresentationVisibility(.init(expanded: true, compact: false))
        module.applyPresentationVisibility(.init(expanded: true, compact: false))
        module.applyPresentationVisibility(.init(expanded: false, compact: true))
        module.applyPresentationVisibility(.init(expanded: false, compact: true))
        module.applyPresentationVisibility(.init(expanded: false, compact: false))
        XCTAssertEqual(events, ["expanded start", "expanded stop", "compact start", "compact stop"])
    }
}
