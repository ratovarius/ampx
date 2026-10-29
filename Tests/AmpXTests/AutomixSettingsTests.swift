@testable import AmpX
import XCTest

/// DJ mode spec Revision 2 § Delivery 2: Automix, User-facing settings.
@MainActor
final class AutomixSettingsTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    func testDefaultsMatchSpec() {
        let settings = AutomixSettings()
        XCTAssertFalse(settings.enabled)
        XCTAssertEqual(settings.mixPoints, .introOutro)
        XCTAssertEqual(settings.transition, .crossfade)
        XCTAssertEqual(settings.lastPhraseBlendBars, 16)
        XCTAssertEqual(settings.longestBlendBars, 32)
        XCTAssertFalse(settings.glideBack)
        XCTAssertEqual(settings.glideSpeed, 0.1)
        XCTAssertTrue(settings.continueWithMixesWell)
        XCTAssertEqual(settings.pickFrom, .currentView)
        XCTAssertEqual(AutomixSettings.lastPhraseBlendChoices, [8, 16, 32])
        XCTAssertEqual(AutomixSettings.longestBlendChoices, [16, 32, 64])
        XCTAssertEqual(AutomixSettings.glideSpeedChoices, [0.05, 0.1, 0.2])
    }

    func testSettingsRoundTripThroughDefaults() {
        let defaults = self.makeDefaults()
        let store = AutomixSettingsStore(defaults: defaults)
        var changed = AutomixSettings()
        changed.enabled = true
        changed.mixPoints = .lastPhrase
        changed.transition = .bassSwap
        changed.lastPhraseBlendBars = 32
        changed.longestBlendBars = 64
        changed.glideBack = true
        changed.glideSpeed = 0.2
        changed.continueWithMixesWell = false
        changed.pickFrom = .wholeLibrary
        store.settings = changed
        XCTAssertEqual(AutomixSettingsStore(defaults: defaults).settings, changed)
    }

    func testCorruptSettingsFallBackToDefaults() {
        let defaults = self.makeDefaults()
        defaults.set(Data("x".utf8), forKey: AutomixSettingsStore.settingsKey)
        XCTAssertEqual(AutomixSettingsStore(defaults: defaults).settings, AutomixSettings())
    }

    func testPickFilterRoundTrip() {
        let defaults = self.makeDefaults()
        var query = LibraryQuery()
        query.search = "drumcode"
        query.genres = [.text("Techno")]
        query.bpmRange = 124 ... 130
        AutomixSettingsStore(defaults: defaults).pickFilter = query
        XCTAssertEqual(AutomixSettingsStore(defaults: defaults).pickFilter, query)
    }
}
