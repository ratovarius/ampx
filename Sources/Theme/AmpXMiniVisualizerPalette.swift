// swiftformat:disable redundantRawValues
// swiftlint:disable redundant_string_enum_value
/// Opaque, normalized sRGB RGBA values. Renderers apply effect opacity separately
/// and use the same color-space conversion for every style.
enum AmpXMiniVisualizerPalette: String, CaseIterable, Sendable {
    case blue = "blue"
    case classic = "classic"
    case red = "red"
    case green = "green"
    case amber = "amber"

    var title: String {
        switch self {
        case .blue: "Blue"
        case .classic: "Classic"
        case .red: "Red"
        case .green: "Green"
        case .amber: "Amber"
        }
    }

    func advanced() -> Self {
        switch self {
        case .blue: .classic
        case .classic: .red
        case .red: .green
        case .green: .amber
        case .amber: .blue
        }
    }

    var backgroundColor: SIMD4<Float> {
        SIMD4(0, 0, 0, 1)
    }

    var lowColor: SIMD4<Float> {
        self.colors.low
    }

    var midColor: SIMD4<Float> {
        self.colors.mid
    }

    var highColor: SIMD4<Float> {
        self.colors.high
    }

    var traceColor: SIMD4<Float> {
        self.colors.trace
    }

    var peakColor: SIMD4<Float> {
        self.colors.peak
    }

    var dimCellColor: SIMD4<Float> {
        self.colors.dimCell
    }

    var historyColor: SIMD4<Float> {
        self.colors.history
    }

    /// Low-color hold end, middle stop, high stop, and whether peaks follow the ramp.
    var rampParameters: SIMD4<Float> {
        self == .classic ? SIMD4(0, 0.5, 1, 1) : SIMD4(0.3, 0.72, 1, 0)
    }

    /// Keep each spectral ramp, trace, peak, and quiet-cell tint together.
    private struct Colors {
        let low: SIMD4<Float>
        let mid: SIMD4<Float>
        let high: SIMD4<Float>
        let trace: SIMD4<Float>
        let peak: SIMD4<Float>
        let dimCell: SIMD4<Float>
        let history: SIMD4<Float>
    }

    private var colors: Colors {
        switch self {
        case .blue:
            Colors(
                low: SIMD4(0.02, 0.28, 0.85, 1),
                mid: SIMD4(0.02, 0.65, 1, 1),
                high: SIMD4(0.35, 0.95, 1, 1),
                trace: SIMD4(0.2, 0.9, 1, 1),
                peak: SIMD4(0.7, 1, 1, 1),
                dimCell: SIMD4(0.015, 0.055, 0.12, 1),
                history: SIMD4(0.015, 0.08, 0.35, 1)
            )
        case .classic:
            Colors(
                low: SIMD4(0, 1, 50.0 / 255, 1),
                mid: SIMD4(1, 210.0 / 255, 26.0 / 255, 1),
                high: Self.rgb(0xF02008),
                trace: SIMD4(0, 1, 50.0 / 255, 1),
                peak: Self.rgb(0xF02008),
                dimCell: SIMD4(0.025, 0.09, 0.025, 1),
                history: SIMD4(0.015, 0.2, 0.04, 1)
            )
        case .red:
            Colors(
                low: Self.rgb(0xCA2343), mid: Self.rgb(0xFF4557), high: Self.rgb(0xFFAF91),
                trace: Self.rgb(0xFF6475), peak: Self.rgb(0xFFE1D5),
                dimCell: Self.rgb(0x210C13), history: Self.rgb(0x5C102A)
            )
        case .green:
            Colors(
                low: Self.rgb(0x0DAB62), mid: Self.rgb(0x35E78B), high: Self.rgb(0xC5FFC1),
                trace: Self.rgb(0x63FFA5), peak: Self.rgb(0xE2FFE9),
                dimCell: Self.rgb(0x082319), history: Self.rgb(0x075634)
            )
        case .amber:
            Colors(
                low: Self.rgb(0xCB6713), mid: Self.rgb(0xF6B642), high: Self.rgb(0xFFE5A0),
                trace: Self.rgb(0xFFD46F), peak: Self.rgb(0xFFF1CF),
                dimCell: Self.rgb(0x281B08), history: Self.rgb(0x59300A)
            )
        }
    }

    private static func rgb(_ hex: UInt32) -> SIMD4<Float> {
        SIMD4(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255, 1)
    }
}

// swiftformat:enable redundantRawValues
// swiftlint:enable redundant_string_enum_value
