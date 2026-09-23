@testable import AmpX
import XCTest

final class AmpXControlsTests: XCTestCase {
    func testValueClampsTrackEndpoints() {
        XCTAssertEqual(AmpXControlMath.value(fraction: -0.2, range: -12 ... 12), -12)
        XCTAssertEqual(AmpXControlMath.value(fraction: 0.5, range: -12 ... 12), 0)
        XCTAssertEqual(AmpXControlMath.value(fraction: 1.2, range: -12 ... 12), 12)
    }

    func testFractionRoundTrip() {
        let range = -12.0 ... 12.0
        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let value = AmpXControlMath.value(fraction: fraction, range: range)
            XCTAssertEqual(AmpXControlMath.fraction(value: value, range: range), fraction, accuracy: 0.0001)
        }
    }

    func testVerticalFractionMapsHighValueToTop() {
        let track = CGRect(x: 0, y: 0, width: 18, height: 120)
        let top = AmpXControlMath.verticalFraction(point: CGPoint(x: 9, y: track.minY), track: track)
        let bottom = AmpXControlMath.verticalFraction(point: CGPoint(x: 9, y: track.maxY), track: track)
        XCTAssertEqual(top, 1, accuracy: 0.0001)
        XCTAssertEqual(bottom, 0, accuracy: 0.0001)
        XCTAssertEqual(
            AmpXControlMath.value(fraction: top, range: -12 ... 12),
            12,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AmpXControlMath.value(fraction: bottom, range: -12 ... 12),
            -12,
            accuracy: 0.0001
        )
    }

    func testHorizontalFractionMapsEndpoints() {
        let track = CGRect(x: 10, y: 0, width: 100, height: 20)
        let start = AmpXControlMath.horizontalFraction(point: CGPoint(x: track.minX, y: 10), track: track)
        let end = AmpXControlMath.horizontalFraction(point: CGPoint(x: track.maxX, y: 10), track: track)
        XCTAssertEqual(start, 0, accuracy: 0.0001)
        XCTAssertEqual(end, 1, accuracy: 0.0001)
    }

    func testStepSnapsToIncrement() {
        let value = AmpXControlMath.value(fraction: 0.53, range: -12 ... 12, step: 1)
        XCTAssertEqual(value, 1)
    }

    func testScrollbarOffsetClampsToLimits() {
        XCTAssertEqual(AmpXControlMath.clampedScrollOffset(-10, contentLength: 200, viewportLength: 80), 0)
        XCTAssertEqual(AmpXControlMath.clampedScrollOffset(500, contentLength: 200, viewportLength: 80), 120)
        XCTAssertEqual(AmpXControlMath.clampedScrollOffset(40, contentLength: 200, viewportLength: 80), 40)
    }

    func testExpandedHitRectMeetsMinimumSize() {
        let rect = CGRect(x: 10, y: 10, width: 20, height: 16)
        let expanded = AmpXControlMath.expandedHitRect(for: rect)
        XCTAssertGreaterThanOrEqual(expanded.width, AmpXControlMath.minimumHitSize)
        XCTAssertGreaterThanOrEqual(expanded.height, AmpXControlMath.minimumHitSize)
        XCTAssertEqual(expanded.midX, rect.midX, accuracy: 0.0001)
        XCTAssertEqual(expanded.midY, rect.midY, accuracy: 0.0001)
    }

    @MainActor
    func testDisabledButtonDoesNotActivate() throws {
        let skin = ClassicModernSkin()
        let button = AmpXButton(skin: skin)
        button.frame = CGRect(x: 0, y: 0, width: 44, height: 40)
        button.isEnabled = false
        var fired = false
        button.action = { fired = true }

        try button.mouseDown(with: XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 22, y: 20),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )))
        try button.mouseUp(with: XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: NSPoint(x: 22, y: 20),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )))

        XCTAssertFalse(fired)
        XCTAssertFalse(button.isPressed)
    }

    @MainActor
    func testReleaseOutsideBoundsDoesNotFire() throws {
        let skin = ClassicModernSkin()
        let button = AmpXButton(skin: skin)
        button.frame = CGRect(x: 0, y: 0, width: 44, height: 40)
        var fired = false
        button.action = { fired = true }

        try button.mouseDown(with: XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 22, y: 20),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )))
        try button.mouseUp(with: XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: NSPoint(x: 80, y: 80),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )))

        XCTAssertFalse(fired)
        XCTAssertFalse(button.isPressed)
    }

    @MainActor
    func testProgrammaticSliderValueDoesNotInvokeOnChange() {
        let skin = ClassicModernSkin()
        let slider = AmpXSlider(skin: skin)
        slider.frame = CGRect(x: 0, y: 0, width: 100, height: 20)
        slider.range = 0 ... 1
        var changes = 0
        slider.onChange = { _ in changes += 1 }

        slider.setValue(0.5, sendChange: false)
        slider.setValue(0.75, sendChange: false)

        XCTAssertEqual(changes, 0)
        XCTAssertEqual(slider.value, 0.75, accuracy: 0.0001)
    }

    @MainActor
    func testSliderDragInvokesOnChange() throws {
        let skin = ClassicModernSkin()
        let slider = AmpXSlider(skin: skin)
        slider.frame = CGRect(x: 0, y: 0, width: 100, height: 20)
        slider.range = 0 ... 100
        var lastValue: Double?
        slider.onChange = { lastValue = $0 }

        try slider.mouseDown(with: XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 50, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )))

        XCTAssertNotNil(lastValue)
        XCTAssertEqual(lastValue ?? -1, 50, accuracy: 1)
    }
}
