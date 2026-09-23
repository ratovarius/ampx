@testable import AmpX
import AppKit
import XCTest

@MainActor
final class AmpXCompactDisplayTests: XCTestCase {
    func testCompactTimeHandlesMinutesHoursAndRemaining() {
        for (seconds, expected) in [
            (0.0, "00:00"),
            (111, "01:51"),
            (3599, "59:59"),
            (3600, "1:00:00"),
            (360_000, "100:00:00"),
        ] {
            XCTAssertEqual(
                AmpXCompactTimeLayout.text(current: seconds, duration: 400_000, remaining: false, hasLoadedTrack: true),
                expected
            )
            XCTAssertEqual(
                AmpXCompactTimeLayout.text(current: 0, duration: seconds + 1, remaining: true, hasLoadedTrack: true),
                "-" + AmpXCompactTimeLayout.text(
                    current: seconds + 1,
                    duration: 400_000,
                    remaining: false,
                    hasLoadedTrack: true
                )
            )
        }
        XCTAssertEqual(AmpXCompactTimeLayout.text(current: 500, duration: 100, remaining: true, hasLoadedTrack: true), "-00:00")
    }

    func testUnknownAndMalformedTimesAreSafe() {
        for value in [Double.nan, .infinity, -.infinity, Double.greatestFiniteMagnitude] {
            XCTAssertEqual(AmpXCompactTimeLayout.text(current: value, duration: 120, remaining: false, hasLoadedTrack: true), "00:00")
            XCTAssertEqual(AmpXCompactTimeLayout.text(current: 5, duration: value, remaining: true, hasLoadedTrack: true), "00:00")
        }
        XCTAssertEqual(AmpXCompactTimeLayout.text(current: -1, duration: 120, remaining: false, hasLoadedTrack: true), "00:00")
        XCTAssertEqual(AmpXCompactTimeLayout.text(current: 5, duration: 0, remaining: true, hasLoadedTrack: true), "00:00")
        XCTAssertEqual(AmpXCompactTimeLayout.text(current: 5, duration: 120, remaining: false, hasLoadedTrack: false), "00:00")
    }

    func testNegativeLongTimerFitsInsideItsOwnRectangle() {
        let rect = CGRect(x: 0, y: 0, width: 52, height: 18)
        let text = AmpXCompactTimeLayout.text(current: 0, duration: 360_000, remaining: true, hasLoadedTrack: true)
        XCTAssertEqual(text, "-100:00:00")
        let metrics = AmpXCompactTimeLayout.metrics(for: text, in: rect)
        let cells = AmpXSegmentDigits.cells(for: text, in: rect, metrics: metrics)
        XCTAssertTrue(cells.allSatisfy { rect.contains($0.rect) })
        for pair in zip(cells, cells.dropFirst()) {
            XCTAssertFalse(pair.0.rect.intersects(pair.1.rect))
        }
    }

    func testCompactSpectrumUsesOnlyItsBounds() {
        let well = SpectrumWellView(skin: ClassicModernSkin())
        let expanded = AmpXMetrics.playerSpectrum.offsetBy(dx: -AmpXMetrics.playerDisplayWell.minX, dy: -AmpXMetrics.playerDisplayWell.minY)
        XCTAssertEqual(well.spectrumRect, expanded)
        well.geometry = .compact
        for size in [CGSize(width: 110, height: 18), CGSize(width: 122, height: 16)] {
            well.frame.size = size
            well.layoutSubtreeIfNeeded()
            well.viewDidChangeBackingProperties()
            XCTAssertEqual(well.spectrumRect, well.bounds)
            XCTAssertTrue(well.bounds.contains(well.segmentRect(column: 15, segment: 5)))
        }
        well.geometry = .expanded
        XCTAssertEqual(well.spectrumRect, expanded)
    }

    func testTimerKeyboardAndAccessibilityShareMode() {
        let timer = TimeDisplayView(skin: ClassicModernSkin())
        timer.style = .compact
        XCTAssertTrue(timer.performKeyboardPress())
        XCTAssertTrue(timer.showRemainingTime)
        XCTAssertTrue(timer.accessibilityPerformPress())
        XCTAssertFalse(timer.showRemainingTime)
    }
}
