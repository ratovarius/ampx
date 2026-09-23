@testable import AmpX
import XCTest

final class AmpXMiniVisualizerSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        self.suiteName = "ampx-mini-settings-\(UUID().uuidString)"
        self.defaults = try XCTUnwrap(UserDefaults(suiteName: self.suiteName))
    }

    override func tearDownWithError() throws {
        self.defaults.removePersistentDomain(forName: self.suiteName)
        self.defaults = nil
        try super.tearDownWithError()
    }

    func testAbsentPreferencesUseClassicSpectrumAndBlue() {
        let loaded = AmpXMiniVisualizerSettingsStore(defaults: self.defaults).load()
        XCTAssertEqual(loaded.style, .classicSpectrum)
        XCTAssertEqual(loaded.palette, .blue)
        XCTAssertEqual(loaded, AmpXMiniVisualizerSettings())
    }

    func testRetroIsRemovedAndItsSavedSelectionFallsBackWithoutLosingPalette() {
        XCTAssertEqual(AmpXMiniVisualizerStyle.allCases.count, 8)
        XCTAssertFalse(AmpXMiniVisualizerStyle.allCases.contains { $0.rawValue == "retro" })
        self.defaults.set("retro", forKey: "miniVisualizer.style")
        self.defaults.set("classic", forKey: "miniVisualizer.palette")
        let loaded = AmpXMiniVisualizerSettingsStore(defaults: self.defaults).load()
        XCTAssertEqual(loaded.style, .classicSpectrum)
        XCTAssertEqual(loaded.palette, .classic)
    }

    func testLegacyValuesMigrateWithoutDeletingOldKey() {
        let cases: [(Int, AmpXMiniVisualizerStyle)] = [
            (0, .classicSpectrum), (1, .lineWaveform), (2, .classicSpectrum),
        ]
        for (legacy, expected) in cases {
            self.defaults.set(legacy, forKey: "visualizationMode")
            let loaded = AmpXMiniVisualizerSettingsStore(defaults: self.defaults).load()
            XCTAssertEqual(loaded.style, expected, "Legacy \(legacy)")
            XCTAssertEqual(loaded.palette, .blue)
            XCTAssertEqual(self.defaults.object(forKey: "visualizationMode") as? Int, legacy)
        }
    }

    func testInvalidLegacyValuesDefaultInsteadOfWrappingOrCoercing() {
        let invalidValues: [Any] = [-1, 3, 99, "invalid", "1", 1.5, true]
        for value in invalidValues {
            self.defaults.set(value, forKey: "visualizationMode")
            XCTAssertEqual(
                AmpXMiniVisualizerSettingsStore(defaults: self.defaults).load().style,
                .classicSpectrum,
                "Invalid legacy \(value)"
            )
        }
    }

    func testNewStyleTakesPrecedenceOverLegacy() {
        self.defaults.set(0, forKey: "visualizationMode")
        self.defaults.set("stereoBars", forKey: "miniVisualizer.style")
        XCTAssertEqual(AmpXMiniVisualizerSettingsStore(defaults: self.defaults).load().style, .stereoBars)
    }

    func testInvalidNewStyleDefaultsIndependentlyAndTakesPrecedenceOverLegacy() {
        self.defaults.set(1, forKey: "visualizationMode")
        self.defaults.set("classic", forKey: "miniVisualizer.palette")
        for value: Any in ["futureStyle", "", 3] {
            self.defaults.set(value, forKey: "miniVisualizer.style")
            let loaded = AmpXMiniVisualizerSettingsStore(defaults: self.defaults).load()
            XCTAssertEqual(loaded.style, .classicSpectrum)
            XCTAssertEqual(loaded.palette, .classic)
        }
    }

    func testInvalidPaletteKeepsValidStyle() {
        self.defaults.set("particleWaveform", forKey: "miniVisualizer.style")
        for value: Any in ["futurePalette", "", "Red", "GREEN", " amber ", 1, 1.5, true] {
            self.defaults.set(value, forKey: "miniVisualizer.palette")
            let loaded = AmpXMiniVisualizerSettingsStore(defaults: self.defaults).load()
            XCTAssertEqual(loaded.style, .particleWaveform)
            XCTAssertEqual(loaded.palette, .blue)
        }
    }

    func testPaletteDoesNotSuppressLegacyStyleMigration() {
        self.defaults.set(1, forKey: "visualizationMode")
        self.defaults.set("classic", forKey: "miniVisualizer.palette")
        let loaded = AmpXMiniVisualizerSettingsStore(defaults: self.defaults).load()
        XCTAssertEqual(loaded.style, .lineWaveform)
        XCTAssertEqual(loaded.palette, .classic)
    }

    func testAllSelectionsRoundTripUsingStableIdentifiersAndPreserveLegacy() throws {
        let styles: [(String, AmpXMiniVisualizerStyle)] = [
            ("classicSpectrum", .classicSpectrum), ("smoothSpectrum", .smoothSpectrum),
            ("dotSpectrum", .dotSpectrum), ("mirroredSpectrum", .mirroredSpectrum),
            ("lineWaveform", .lineWaveform), ("waterfall", .waterfall),
            ("particleWaveform", .particleWaveform), ("stereoBars", .stereoBars),
        ]
        let paletteIDs = ["blue", "classic", "red", "green", "amber"]
        self.defaults.set(1, forKey: "visualizationMode")
        for (styleID, style) in styles {
            for paletteID in paletteIDs {
                let palette = try XCTUnwrap(AmpXMiniVisualizerPalette(rawValue: paletteID), paletteID)
                let settings = AmpXMiniVisualizerSettings(style: style, palette: palette)
                AmpXMiniVisualizerSettingsStore(defaults: self.defaults).save(settings)
                XCTAssertEqual(self.defaults.string(forKey: "miniVisualizer.style"), styleID)
                XCTAssertEqual(self.defaults.string(forKey: "miniVisualizer.palette"), paletteID)
                XCTAssertEqual(AmpXMiniVisualizerSettingsStore(defaults: self.defaults).load(), settings)
                XCTAssertEqual(self.defaults.integer(forKey: "visualizationMode"), 1)
            }
        }
    }

    func testPaletteMenuOrderUsesStableIdentifiers() {
        XCTAssertEqual(
            AmpXMiniVisualizerPalette.allCases.map(\.rawValue),
            ["blue", "classic", "red", "green", "amber"]
        )
        XCTAssertEqual(
            AmpXMiniVisualizerPalette.allCases.map(\.title),
            ["Blue", "Classic", "Red", "Green", "Amber"]
        )
    }

    func testPaletteCyclingVisitsEveryPaletteInOrderAndWraps() {
        let transitions: [(AmpXMiniVisualizerPalette, AmpXMiniVisualizerPalette)] = [
            (.blue, .classic), (.classic, .red), (.red, .green), (.green, .amber), (.amber, .blue),
        ]
        for (palette, next) in transitions {
            XCTAssertEqual(palette.advanced(), next, "\(palette)")
        }
    }

    func testEachSavedPaletteSurvivesInvalidStyleFallback() {
        self.defaults.set("futureStyle", forKey: "miniVisualizer.style")
        for paletteID in ["blue", "classic", "red", "green", "amber"] {
            self.defaults.set(paletteID, forKey: "miniVisualizer.palette")
            let loaded = AmpXMiniVisualizerSettingsStore(defaults: self.defaults).load()
            XCTAssertEqual(loaded.style, .classicSpectrum)
            XCTAssertEqual(loaded.palette.rawValue, paletteID)
        }
    }

    func testCyclingVisitsEveryShaderInOrderAndWraps() {
        var style = AmpXMiniVisualizerStyle.classicSpectrum
        var visited: [AmpXMiniVisualizerStyle] = []
        // Slot 6 belonged to the removed Retro effect; surviving shader IDs stay unchanged.
        for index: UInt32 in [0, 1, 2, 3, 4, 5, 7, 8] {
            visited.append(style)
            XCTAssertEqual(style.shaderIndex, index)
            XCTAssertFalse(style.title.isEmpty)
            style = style.advanced()
        }
        XCTAssertEqual(visited, [
            .classicSpectrum, .smoothSpectrum, .dotSpectrum, .mirroredSpectrum,
            .lineWaveform, .waterfall, .particleWaveform, .stereoBars,
        ])
        XCTAssertEqual(visited, AmpXMiniVisualizerStyle.allCases)
        XCTAssertEqual(style, .classicSpectrum)
    }

    func testPaletteColorsAreFiniteNormalizedOpaqueRGBA() {
        for palette in AmpXMiniVisualizerPalette.allCases {
            XCTAssertFalse(palette.title.isEmpty)
            XCTAssertEqual(palette.backgroundColor, SIMD4(0, 0, 0, 1), "\(palette)")
            let colors = [
                palette.backgroundColor, palette.lowColor, palette.midColor, palette.highColor,
                palette.traceColor, palette.peakColor, palette.dimCellColor, palette.historyColor,
            ]
            for color in colors {
                for channel in 0 ..< 4 {
                    XCTAssertTrue(color[channel].isFinite)
                    XCTAssertTrue((0 ... 1).contains(color[channel]))
                }
                XCTAssertEqual(color.w, 1)
            }
        }
    }

    func testNewPalettesKeepDimCellsRestrainedAndPeaksReadable() throws {
        for paletteID in ["red", "green", "amber"] {
            let palette = try XCTUnwrap(AmpXMiniVisualizerPalette(rawValue: paletteID), paletteID)
            // Relative sRGB luminance checks legibility independently of the chosen hex stops.
            let luminance: (SIMD4<Float>) -> Float = { color in
                let linear = (0 ..< 3).map { index -> Float in
                    let value = color[index]
                    return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
                }
                return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
            }
            XCTAssertLessThan(luminance(palette.dimCellColor), 0.02, paletteID)
            XCTAssertLessThan(luminance(palette.historyColor), luminance(palette.lowColor), paletteID)
            XCTAssertLessThan(luminance(palette.lowColor), luminance(palette.midColor), paletteID)
            XCTAssertLessThan(luminance(palette.midColor), luminance(palette.highColor), paletteID)
            XCTAssertGreaterThan(luminance(palette.traceColor), luminance(palette.lowColor), paletteID)
            XCTAssertGreaterThan(luminance(palette.peakColor), luminance(palette.highColor), paletteID)
            XCTAssertGreaterThan(luminance(palette.peakColor), 0.75, paletteID)
        }
    }
}
