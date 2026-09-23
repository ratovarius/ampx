@testable import AmpX
import XCTest

@MainActor
final class EntheaWebViewLaunchTests: XCTestCase {
    func testHostViewDoesNotCreateWKWebViewDuringInit() {
        let host = EntheaWKHostView(frame: CGRect(x: 0, y: 0, width: 275, height: 116))
        XCTAssertNil(
            host.webView,
            "Creating WKWebView during SwiftUI makeNSView at process start SIGSEGVs on macOS 26"
        )
    }

    func testWebKitSpawnDelayCoversFirstCATransaction() {
        XCTAssertGreaterThanOrEqual(
            EntheaWebViewLaunch.webKitSpawnDelayNanoseconds,
            100_000_000
        )
    }

    func testXCTestHostSkipsWKWebViewSpawn() {
        XCTAssertTrue(EntheaWebViewLaunch.isRunningUnderTest)
    }
}
