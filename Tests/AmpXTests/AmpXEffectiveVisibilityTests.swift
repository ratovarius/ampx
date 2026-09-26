@testable import AmpX
import QuartzCore
import XCTest

@MainActor
final class AmpXEffectiveVisibilityTests: XCTestCase {
    // MARK: - Visibility predicate

    func testVisibleWhenAllInputsAllow() {
        var input = AmpXVisibilityInputs(
            collapsed: false,
            closed: false,
            windowVisible: true,
            miniaturized: false,
            occluded: false
        )
        XCTAssertTrue(input.isVisible)

        input.collapsed = true
        XCTAssertFalse(input.isVisible)
    }

    func testEachInputIndependentlyBlocksVisibility() {
        XCTAssertFalse(self.makeInputs(closed: true).isVisible)
        XCTAssertFalse(self.makeInputs(windowVisible: false).isVisible)
        XCTAssertFalse(self.makeInputs(miniaturized: true).isVisible)
        XCTAssertFalse(self.makeInputs(occluded: true).isVisible)
        XCTAssertFalse(self.makeInputs(collapsed: true).isVisible)
    }

    func testModuleWindowHonorsWindowAndCollapseInputs() {
        let visible = AmpXEffectiveVisibility.windowInputs(
            collapsed: false,
            closed: false,
            window: self.visibleWindow()
        )
        if visible.windowVisible, !visible.occluded {
            XCTAssertTrue(visible.isVisible)
        }

        let collapsed = AmpXEffectiveVisibility.windowInputs(
            collapsed: true,
            closed: false,
            window: self.visibleWindow()
        )
        XCTAssertFalse(collapsed.isVisible)

        let missing = AmpXEffectiveVisibility.windowInputs(collapsed: false, closed: false, window: nil)
        XCTAssertFalse(missing.isVisible)
    }

    func testTheaterHostHonorsOtherInputs() {
        let visible = AmpXEffectiveVisibility.theaterInputs(
            collapsed: false,
            closed: false,
            window: self.visibleWindow()
        )
        if visible.windowVisible, !visible.occluded {
            XCTAssertTrue(visible.isVisible)
        }

        let closed = AmpXEffectiveVisibility.theaterInputs(
            collapsed: false,
            closed: true,
            window: self.visibleWindow()
        )
        XCTAssertFalse(closed.isVisible)
    }

    // MARK: - Display-link lifecycle

    func testBecomingVisibleStartsDisplayLinkOnce() {
        let view = self.makeContinuousView()
        view.setEffectivelyVisible(true)
        XCTAssertEqual(view.displayLinkStartCount, 1)
        XCTAssertEqual(view.displayLinkStopCount, 0)
    }

    func testBecomingHiddenStopsDisplayLinkOnce() {
        let view = self.makeContinuousView()
        view.setEffectivelyVisible(true)
        view.setEffectivelyVisible(false)
        XCTAssertEqual(view.displayLinkStartCount, 1)
        XCTAssertEqual(view.displayLinkStopCount, 1)
    }

    func testRepeatedFalseDoesNotStopTwice() {
        let view = self.makeContinuousView()
        view.setEffectivelyVisible(false)
        view.setEffectivelyVisible(false)
        XCTAssertEqual(view.displayLinkStopCount, 0)

        view.setEffectivelyVisible(true)
        view.setEffectivelyVisible(false)
        view.setEffectivelyVisible(false)
        XCTAssertEqual(view.displayLinkStopCount, 1)
    }

    func testRepeatedTrueDoesNotStartTwice() {
        let view = self.makeContinuousView()
        view.setEffectivelyVisible(true)
        view.setEffectivelyVisible(true)
        XCTAssertEqual(view.displayLinkStartCount, 1)
        XCTAssertEqual(view.displayLinkStopCount, 0)
    }

    func testTickInvalidatesLeafBoundsOnly() {
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let leaf = TrackingContinuousView(skin: ClassicModernSkin())
        leaf.frame = CGRect(x: 20, y: 20, width: 80, height: 40)
        container.addSubview(leaf)

        leaf.tick(at: 1.0)

        XCTAssertEqual(leaf.invalidatedRect, leaf.bounds)
        XCTAssertFalse(container.needsDisplay)
    }

    func testForwarderDoesNotRetainContinuousView() {
        weak var weakView: AmpXContinuousView?
        autoreleasepool {
            let view = self.makeContinuousView()
            weakView = view
            view.setEffectivelyVisible(true)
        }
        XCTAssertNil(weakView)
    }

    // MARK: - Host integration

    func testCoordinatorCollapseStopsContinuousRendering() throws {
        let coordinator = self.makeCoordinator()
        coordinator.showAll()
        let continuous = try self.attachContinuousView(to: XCTUnwrap(coordinator.moduleView(for: .player)))
        continuous.setEffectivelyVisible(true)

        coordinator.setCollapsed(.player, true)
        XCTAssertEqual(continuous.displayLinkStopCount, 1)
    }

    // MARK: - Helpers

    private func makeInputs(
        collapsed: Bool = false,
        closed: Bool = false,
        windowVisible: Bool = true,
        miniaturized: Bool = false,
        occluded: Bool = false
    ) -> AmpXVisibilityInputs {
        AmpXVisibilityInputs(
            collapsed: collapsed,
            closed: closed,
            windowVisible: windowVisible,
            miniaturized: miniaturized,
            occluded: occluded
        )
    }

    private func visibleWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 490, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.orderFrontRegardless()
        return window
    }

    private func makeContinuousView() -> InstrumentedContinuousView {
        InstrumentedContinuousView(skin: ClassicModernSkin())
    }

    private func makeCoordinator() -> AmpXHostCoordinator {
        AmpXHostCoordinator(
            state: AmpXModuleState(),
            skin: ClassicModernSkin(),
            layoutStore: makeIsolatedLayoutStore(),
            screen: AmpXTestScreen.standard
        )
    }

    private func attachContinuousView(to moduleView: AmpXModuleView) -> InstrumentedContinuousView {
        let continuous = InstrumentedContinuousView(skin: ClassicModernSkin())
        moduleView.content.addSubview(continuous)
        return continuous
    }
}

private final class InstrumentedContinuousView: AmpXContinuousView {
    private(set) var displayLinkStartCount = 0
    private(set) var displayLinkStopCount = 0

    override init(skin: any AmpXSkin) {
        super.init(skin: skin)
        displayLinkFactory = { view, target, selector in
            view.displayLink(target: target, selector: selector)
        }
        displayLinkStarter = { [weak self] _ in
            self?.displayLinkStartCount += 1
        }
        displayLinkStopper = { [weak self] _ in
            self?.displayLinkStopCount += 1
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class TrackingContinuousView: AmpXContinuousView {
    private(set) var invalidatedRect: NSRect?

    override func tick(at time: TimeInterval) {
        self.invalidatedRect = bounds
        super.tick(at: time)
    }
}
