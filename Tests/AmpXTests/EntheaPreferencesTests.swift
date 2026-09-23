@testable import AmpX
import XCTest

final class EntheaPreferencesTests: XCTestCase {
    func testPhotosensitiveWarningDefaultsFalse() throws {
        let suiteName = "EntheaPreferencesTests.\(#function)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        suite.removePersistentDomain(forName: suiteName)
        XCTAssertFalse(EntheaPreferences(defaults: suite).photosensitiveWarningAccepted)
    }

    func testPhotosensitiveWarningPersists() throws {
        let suiteName = "EntheaPreferencesTests.\(#function)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        suite.removePersistentDomain(forName: suiteName)
        let prefs = EntheaPreferences(defaults: suite)
        prefs.photosensitiveWarningAccepted = true
        XCTAssertTrue(EntheaPreferences(defaults: suite).photosensitiveWarningAccepted)
    }

    func testBackingScaleClampsToBudget() {
        // Theater-sized panel at Retina would exceed 2.0 Mpx at full DPR.
        let scale = EntheaBackingScale.scale(
            forSize: CGSize(width: 1728, height: 1080),
            screenScale: 2
        )
        XCTAssertLessThan(scale, 1.2)
        XCTAssertGreaterThanOrEqual(scale, 1.0)
    }

    func testBackingScaleAllowsFullDPRAtPanelSize() {
        let scale = EntheaBackingScale.scale(
            forSize: CGSize(width: 600, height: 450),
            screenScale: 2
        )
        XCTAssertEqual(scale, 2, accuracy: 0.01)
    }

    func testAutopilotDefaultsTrue() throws {
        let suiteName = "EntheaPreferencesTests.\(#function)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        suite.removePersistentDomain(forName: suiteName)
        XCTAssertTrue(EntheaPreferences(defaults: suite).autopilot)
    }

    func testModeAndAutopilotPersist() throws {
        let suiteName = "EntheaPreferencesTests.\(#function)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        suite.removePersistentDomain(forName: suiteName)
        let prefs = EntheaPreferences(defaults: suite)
        prefs.modeID = 12
        prefs.autopilot = false
        let again = EntheaPreferences(defaults: suite)
        XCTAssertEqual(again.modeID, 12)
        XCTAssertFalse(again.autopilot)
    }

    func testPushRatePolicyCapsDockedSmall() {
        let hz = EntheaPushRatePolicy.pushHz(
            forContentSize: CGSize(width: 400, height: 300),
            isTheater: false
        )
        XCTAssertEqual(hz, EntheaPushRatePolicy.dockedSmallHz)
    }

    func testPushRatePolicyFullInTheater() {
        let hz = EntheaPushRatePolicy.pushHz(
            forContentSize: CGSize(width: 100, height: 100),
            isTheater: true
        )
        XCTAssertEqual(hz, EntheaPushRatePolicy.theaterOrLargeHz)
    }

    func testPushRatePolicyFullWhenLarge() {
        let hz = EntheaPushRatePolicy.pushHz(
            forContentSize: CGSize(width: 800, height: 600),
            isTheater: false
        )
        XCTAssertEqual(hz, EntheaPushRatePolicy.theaterOrLargeHz)
    }
}
