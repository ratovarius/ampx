@testable import AmpX
import XCTest

/// A continuous view must be able to stop its display link while staying effectively visible, so an
/// idle visualizer costs nothing once audio and its decay tails go quiet.
@MainActor
final class AmpXContinuousViewPauseTests: XCTestCase {
    func testPausingWhileVisibleStopsTheDisplayLink() {
        let view = CountingContinuousView(skin: ClassicModernSkin())
        view.setEffectivelyVisible(true)
        XCTAssertEqual(view.startCount, 1)

        view.setContinuousRenderingPaused(true)

        XCTAssertEqual(view.stopCount, 1)
        XCTAssertTrue(view.isContinuousRenderingPaused)
    }

    func testResumingRestartsTheDisplayLink() {
        let view = CountingContinuousView(skin: ClassicModernSkin())
        view.setEffectivelyVisible(true)
        view.setContinuousRenderingPaused(true)

        view.setContinuousRenderingPaused(false)

        XCTAssertEqual(view.startCount, 2)
        XCTAssertFalse(view.isContinuousRenderingPaused)
    }

    func testPausedViewDoesNotRenderWhenItBecomesVisible() {
        let view = CountingContinuousView(skin: ClassicModernSkin())
        view.setContinuousRenderingPaused(true)
        XCTAssertEqual(view.stopCount, 0, "nothing to stop while the view is not visible")

        view.setEffectivelyVisible(true)

        XCTAssertEqual(view.startCount, 0)
    }

    func testQueuedDisplayCallbacksCoalesceBeforeMainActorRuns() async {
        let view = CountingContinuousView(skin: ClassicModernSkin())
        view.setEffectivelyVisible(true)
        let forwarder = AmpXDisplayLinkForwarder()
        forwarder.view = view
        let link = view.displayLink(target: forwarder, selector: #selector(AmpXDisplayLinkForwarder.displayLinkFired(_:)))
        for _ in 0 ..< 100 {
            forwarder.displayLinkFired(link)
        }
        await self.drainMainQueue()
        XCTAssertEqual(view.tickCount, 1)
        view.setEffectivelyVisible(false)
    }

    func testQueuedCallbackCannotTickAfterViewIsHiddenOrParked() async {
        for hide in [true, false] {
            let view = CountingContinuousView(skin: ClassicModernSkin())
            view.setEffectivelyVisible(true)
            let forwarder = AmpXDisplayLinkForwarder()
            forwarder.view = view
            let link = view.displayLink(target: forwarder, selector: #selector(AmpXDisplayLinkForwarder.displayLinkFired(_:)))
            forwarder.displayLinkFired(link)
            if hide {
                view.setEffectivelyVisible(false)
            } else {
                view.setContinuousRenderingPaused(true)
            }
            await self.drainMainQueue()
            XCTAssertEqual(view.tickCount, 0)
            view.setEffectivelyVisible(false)
        }
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

private final class CountingContinuousView: AmpXContinuousView {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var tickCount = 0

    override func tick(at _: TimeInterval) {
        self.tickCount += 1
    }

    override init(skin: any AmpXSkin) {
        super.init(skin: skin)
        displayLinkFactory = { view, target, selector in
            view.displayLink(target: target, selector: selector)
        }
        displayLinkStarter = { [weak self] _ in
            self?.startCount += 1
        }
        displayLinkStopper = { [weak self] _ in
            self?.stopCount += 1
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
