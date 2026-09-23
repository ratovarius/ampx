@testable import AmpX
import XCTest

@MainActor
final class AmpXEQBindingTests: XCTestCase {
    private var audioPlayer: SpyEQAudioPlayer!
    private var content: EqualizerModuleContent!

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults(suiteName: "AmpXEQBindingTests.\(UUID().uuidString)")!
        self.audioPlayer = SpyEQAudioPlayer(
            installRemoteCommands: false,
            eqSettingsStore: EQSettingsStore(
                userDefaults: defaults,
                settingsKey: "settings",
                presetsKey: "presets"
            )
        )
        self.content = EqualizerModuleContent(skin: ClassicModernSkin(), audioPlayer: self.audioPlayer)
    }

    func testDecibelsFromNormalized() {
        XCTAssertEqual(EQValueMapping.decibels(normalized: 0.5), 6)
    }

    func testNormalizedFromDecibels() {
        XCTAssertEqual(EQValueMapping.normalized(decibels: -12), -1)
    }

    func testValueMappingClampsToPlusMinusTwelveDecibels() {
        XCTAssertEqual(EQValueMapping.decibels(normalized: 2), 12)
        XCTAssertEqual(EQValueMapping.normalized(decibels: 24), 1)
    }

    func testBandSliderCallsSetEQBandWithDecibels() {
        let slider = self.bandSlider(named: "60")
        XCTAssertNotNil(slider)
        slider?.onChange?(6)
        XCTAssertEqual(self.audioPlayer.lastEQBandIndex, 0)
        XCTAssertEqual(self.audioPlayer.lastEQBandGain ?? 0, 6, accuracy: 0.0001)
    }

    func testPreampSliderCallsSetEQPreampWithNormalizedValue() {
        let slider = self.preampSlider()
        XCTAssertNotNil(slider)
        slider?.onChange?(-6)
        XCTAssertEqual(self.audioPlayer.lastEQPreamp ?? 0, -0.5, accuracy: 0.0001)
    }

    func testOnToggleCallsSetEQEnabled() {
        self.audioPlayer.eqEnabled = true
        self.tapButton(accessibilityTitle: "Equalizer on")
        XCTAssertEqual(self.audioPlayer.setEQEnabledCalls, [false])
    }

    func testAutoToggleCallsSetEQAutoEnabled() {
        self.tapButton(accessibilityTitle: "Equalizer auto")
        XCTAssertEqual(self.audioPlayer.setEQAutoEnabledCalls, [true])
    }

    func testAutoAdjustedPreampUpdatesSliderWithoutUISetterFeedback() {
        self.audioPlayer.setEQAutoEnabled(true)
        self.audioPlayer.setEQBand(0, gain: 12)
        waitForMainQueue()

        let slider = self.preampSlider()
        let expectedDB = EQValueMapping.decibels(normalized: self.audioPlayer.eqPreampValue)
        XCTAssertLessThan(expectedDB, 0)
        XCTAssertEqual(slider?.value ?? 0, -2, accuracy: 0.01)
        XCTAssertNil(self.audioPlayer.lastEQPreamp)
    }

    func testModelBandChangesUpdateSliderDisplay() {
        self.audioPlayer.setEQBand(2, gain: 3)
        waitForMainQueue()

        let slider = self.bandSlider(named: "310")
        XCTAssertEqual(slider?.value ?? 0, 3, accuracy: 0.01)
    }

    private func preampSlider() -> AmpXSlider? {
        self.slider(accessibilityTitle: "Preamp")
    }

    private func bandSlider(named label: String) -> AmpXSlider? {
        self.slider(accessibilityTitle: "\(label) band")
    }

    private func slider(accessibilityTitle: String) -> AmpXSlider? {
        self.subviews(ofType: AmpXSlider.self, in: self.content)
            .first { $0.accessibilityTitle == accessibilityTitle }
    }

    private func tapButton(accessibilityTitle: String) {
        let button = self.subviews(ofType: AmpXButton.self, in: self.content)
            .first { $0.accessibilityTitle == accessibilityTitle }
        XCTAssertNotNil(button)
        button?.action?()
    }

    private func subviews<T: NSView>(ofType type: T.Type, in root: NSView) -> [T] {
        var found: [T] = []
        for subview in root.subviews {
            if let match = subview as? T {
                found.append(match)
            }
            found.append(contentsOf: self.subviews(ofType: type, in: subview))
        }
        return found
    }
}

@MainActor
private final class SpyEQAudioPlayer: AudioPlayer {
    var lastEQBandIndex: Int?
    var lastEQBandGain: Float?
    var lastEQPreamp: Float?
    var setEQEnabledCalls: [Bool] = []
    var setEQAutoEnabledCalls: [Bool] = []

    override func setEQBand(_ band: Int, gain: Float) {
        self.lastEQBandIndex = band
        self.lastEQBandGain = gain
        super.setEQBand(band, gain: gain)
    }

    override func setEQPreamp(_ normalizedValue: Float) {
        self.lastEQPreamp = normalizedValue
        super.setEQPreamp(normalizedValue)
    }

    override func setEQEnabled(_ enabled: Bool) {
        self.setEQEnabledCalls.append(enabled)
        super.setEQEnabled(enabled)
    }

    override func setEQAutoEnabled(_ enabled: Bool) {
        self.setEQAutoEnabledCalls.append(enabled)
        super.setEQAutoEnabled(enabled)
    }
}
