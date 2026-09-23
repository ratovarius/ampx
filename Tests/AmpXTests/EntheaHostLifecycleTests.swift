@testable import AmpX
import XCTest

@MainActor
final class FakeEntheaHost: AmpXEntheaHosting {
    var activeCalls: [Bool] = []
    var teardownCount = 0

    func setAudioBridgeActive(_ active: Bool) {
        self.activeCalls.append(active)
    }

    func teardown() {
        self.teardownCount += 1
    }
}

@MainActor
final class EntheaHostLifecycleTests: XCTestCase {
    func testVisibilityForwardsToAudioBridgeActive() {
        let host = FakeEntheaHost()
        let lifecycle = EntheaHostLifecycle(host: host)
        lifecycle.setVisible(true)
        lifecycle.setVisible(false)
        lifecycle.setVisible(false)
        XCTAssertEqual(host.activeCalls, [true, false])
        lifecycle.close()
        XCTAssertEqual(host.teardownCount, 1)
        XCTAssertNil(lifecycle.host)
    }

    func testCloseReleasesHostWithoutExternalStrongOwner() {
        weak var weakHost: FakeEntheaHost?
        autoreleasepool {
            let host = FakeEntheaHost()
            weakHost = host
            let lifecycle = EntheaHostLifecycle(host: host)
            lifecycle.close()
        }
        XCTAssertNil(weakHost)
    }

    func testCloseReleasesActualHostView() {
        weak var weakHost: EntheaWKHostView?
        autoreleasepool {
            let host = EntheaWKHostView()
            weakHost = host
            let lifecycle = EntheaHostLifecycle(host: host)
            lifecycle.close()
        }
        XCTAssertNil(weakHost)
    }

    func testModuleCloseRemovesHostSubviewAndClearsOwnership() {
        let content = EntheaModuleContent(
            skin: ClassicModernSkin(),
            audioPlayer: AudioPlayer.shared,
            isTheater: { false },
            onToggleTheater: {}
        )
        content.reopenHost()
        let host = content.hostViewForTesting
        XCTAssertNotNil(host)
        XCTAssertTrue(host?.superview === content)

        content.closeHost()
        XCTAssertNil(content.hostViewForTesting)
        XCTAssertNil(content.lifecycleForTesting?.host)
        XCTAssertTrue(content.subviews.allSatisfy { !($0 is EntheaWKHostView) })
    }

    func testDelayedCallbackCannotResurrectClosedHost() {
        let content = EntheaModuleContent(
            skin: ClassicModernSkin(),
            audioPlayer: AudioPlayer.shared,
            isTheater: { false },
            onToggleTheater: {}
        )
        content.reopenHost()
        content.scheduleDeferredLayoutForTesting()
        content.closeHost()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertNil(content.hostViewForTesting)
    }

    func testReopenCreatesFreshHostAfterClose() {
        let content = EntheaModuleContent(
            skin: ClassicModernSkin(),
            audioPlayer: AudioPlayer.shared,
            isTheater: { false },
            onToggleTheater: {}
        )
        content.reopenHost()
        let first = content.hostViewForTesting
        content.closeHost()
        content.reopenHost()
        let second = content.hostViewForTesting
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertFalse(first === second)
    }
}
