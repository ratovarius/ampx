@testable import AmpX
import XCTest

final class AmpXWindowSnapTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Zoom can leave a scaled snap radius in this process — restore the base 15 pt value.
        AmpXWindowSnap.snapDistance = 15
    }

    override func tearDown() {
        AmpXWindowSnap.snapDistance = 15
        super.tearDown()
    }

    func testSnapWithinDeltaSticksToScreenEdges() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let box = AmpXWindowSnap.Box(frame: CGRect(x: 8, y: 870 - 116 + 1, width: 275, height: 116))
        let delta = AmpXWindowSnap.snapWithinDelta(moving: [box], bounds: bounds)
        XCTAssertEqual(delta.width, -8)
        XCTAssertEqual(delta.height, 875 - box.maxY)
    }

    func testSnapWithinDeltaIgnoresFarEdges() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let box = AmpXWindowSnap.Box(frame: CGRect(x: 400, y: 300, width: 275, height: 116))
        XCTAssertEqual(AmpXWindowSnap.snapWithinDelta(moving: [box], bounds: bounds), .zero)
    }

    func testNearWithinSnapDistance() {
        XCTAssertTrue(AmpXWindowSnap.near(100, 110))
        XCTAssertFalse(AmpXWindowSnap.near(100, 120))
    }

    func testAbutsVerticallyStackedWindows() {
        let main = AmpXWindowSnap.Box(frame: CGRect(x: 50, y: 200, width: 275, height: 116))
        let eq = AmpXWindowSnap.Box(frame: CGRect(x: 50, y: 116, width: 275, height: 84))
        XCTAssertTrue(AmpXWindowSnap.abuts(main, eq))
    }

    func testAbutsHorizontallyAdjacentWindows() {
        let left = AmpXWindowSnap.Box(frame: CGRect(x: 0, y: 100, width: 275, height: 116))
        let right = AmpXWindowSnap.Box(frame: CGRect(x: 275, y: 100, width: 275, height: 232))
        XCTAssertTrue(AmpXWindowSnap.abuts(left, right))
    }

    func testAbutsReturnsFalseForSeparatedWindows() {
        let a = AmpXWindowSnap.Box(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let b = AmpXWindowSnap.Box(frame: CGRect(x: 500, y: 500, width: 100, height: 100))
        XCTAssertFalse(AmpXWindowSnap.abuts(a, b))
    }

    func testSnappedOriginStacksBelowAnchor() throws {
        let anchor = AmpXWindowSnap.Box(frame: CGRect(x: 40, y: 300, width: 275, height: 116))
        let panel = AmpXWindowSnap.Box(frame: CGRect(x: 48, y: 108, width: 275, height: 200))
        let snapped = AmpXWindowSnap.snappedOrigin(
            box: panel,
            origin: NSPoint(x: 48, y: 108),
            against: anchor
        )
        XCTAssertNotNil(snapped)
        XCTAssertEqual(try XCTUnwrap(snapped?.x), 40, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(snapped?.y), 100, accuracy: 0.01)
    }

    func testSnappedOriginAlignsHorizontally() throws {
        let anchor = AmpXWindowSnap.Box(frame: CGRect(x: 0, y: 100, width: 275, height: 116))
        let panel = AmpXWindowSnap.Box(frame: CGRect(x: 288, y: 120, width: 275, height: 232))
        let snapped = AmpXWindowSnap.snappedOrigin(
            box: panel,
            origin: NSPoint(x: 288, y: 120),
            against: anchor
        )
        XCTAssertNotNil(snapped)
        XCTAssertEqual(try XCTUnwrap(snapped?.x), 275, accuracy: 0.01)
    }

    func testTraceConnectedIncludesSnappedNeighbor() {
        let main = self.makeTestWindow(frame: CGRect(x: 50, y: 200, width: 275, height: 116))
        let eq = self.makeTestWindow(frame: CGRect(x: 50, y: 116, width: 275, height: 84))
        let connected = MainActor.assumeIsolated {
            AmpXWindowSnap.traceConnected(from: main, among: [main, eq])
        }
        XCTAssertEqual(Set(connected.map(ObjectIdentifier.init)), Set([main, eq].map(ObjectIdentifier.init)))
    }

    private func makeTestWindow(frame: CGRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.setFrame(frame, display: false)
        return window
    }
}
