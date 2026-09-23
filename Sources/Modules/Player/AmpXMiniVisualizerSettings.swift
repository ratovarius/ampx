import CoreFoundation
import Foundation

// Keep persisted identifiers explicit even when a case is renamed.
// swiftformat:disable redundantRawValues
// swiftlint:disable redundant_string_enum_value
enum AmpXMiniVisualizerStyle: String, CaseIterable, Sendable {
    case classicSpectrum = "classicSpectrum"
    case smoothSpectrum = "smoothSpectrum"
    case dotSpectrum = "dotSpectrum"
    case mirroredSpectrum = "mirroredSpectrum"
    case lineWaveform = "lineWaveform"
    case waterfall = "waterfall"
    case particleWaveform = "particleWaveform"
    case stereoBars = "stereoBars"

    var title: String {
        switch self {
        case .classicSpectrum: "Classic Spectrum"
        case .smoothSpectrum: "Smooth Spectrum"
        case .dotSpectrum: "Dot Spectrum"
        case .mirroredSpectrum: "Mirrored Spectrum"
        case .lineWaveform: "Line Waveform"
        case .waterfall: "Waterfall"
        case .particleWaveform: "Particle Waveform"
        case .stereoBars: "Stereo Bars"
        }
    }

    /// Explicit renderer contract; persistence uses raw identifiers instead.
    var shaderIndex: UInt32 {
        switch self {
        case .classicSpectrum: 0
        case .smoothSpectrum: 1
        case .dotSpectrum: 2
        case .mirroredSpectrum: 3
        case .lineWaveform: 4
        case .waterfall: 5
        case .particleWaveform: 7
        case .stereoBars: 8
        }
    }

    func advanced() -> Self {
        switch self {
        case .classicSpectrum: .smoothSpectrum
        case .smoothSpectrum: .dotSpectrum
        case .dotSpectrum: .mirroredSpectrum
        case .mirroredSpectrum: .lineWaveform
        case .lineWaveform: .waterfall
        case .waterfall: .particleWaveform
        case .particleWaveform: .stereoBars
        case .stereoBars: .classicSpectrum
        }
    }
}

// swiftformat:enable redundantRawValues
// swiftlint:enable redundant_string_enum_value

struct AmpXMiniVisualizerSettings: Equatable {
    var style: AmpXMiniVisualizerStyle = .classicSpectrum
    var palette: AmpXMiniVisualizerPalette = .blue
}

struct AmpXMiniVisualizerSettingsStore {
    private static let styleKey = "miniVisualizer.style"
    private static let paletteKey = "miniVisualizer.palette"
    private static let legacyKey = "visualizationMode"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AmpXMiniVisualizerSettings {
        let style: AmpXMiniVisualizerStyle = if let storedStyle = self.defaults.object(forKey: Self.styleKey) {
            // Even an unknown new identifier takes precedence over the legacy key.
            (storedStyle as? String).flatMap(AmpXMiniVisualizerStyle.init(rawValue:)) ?? .classicSpectrum
        } else {
            self.legacyStyle()
        }
        let palette = (self.defaults.object(forKey: Self.paletteKey) as? String)
            .flatMap(AmpXMiniVisualizerPalette.init(rawValue:)) ?? .blue
        return AmpXMiniVisualizerSettings(style: style, palette: palette)
    }

    func save(_ settings: AmpXMiniVisualizerSettings) {
        self.defaults.set(settings.style.rawValue, forKey: Self.styleKey)
        self.defaults.set(settings.palette.rawValue, forKey: Self.paletteKey)
    }

    private func legacyStyle() -> AmpXMiniVisualizerStyle {
        // integer(forKey:) coerces missing/malformed values to zero.
        // Reject booleans and fractional values as well as unknown integers.
        guard let value = self.defaults.object(forKey: Self.legacyKey) as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID()
        else { return .classicSpectrum }

        switch value.doubleValue {
        case 0: return .classicSpectrum // The old segmented Retro style has been retired.
        case 1: return .lineWaveform
        case 2: return .classicSpectrum
        default: return .classicSpectrum
        }
    }
}
