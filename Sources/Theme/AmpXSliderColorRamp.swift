import CoreGraphics

/// 8-bit RGB components used by track drawing models.
struct AmpXRGB: Equatable {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat
}

/// Winamp's value-driven volume/balance track color (spec Revision 8): green → yellow → red.
enum AmpXSliderColorRamp {
    static let green = AmpXRGB(r: 14, g: 236, b: 2)
    static let yellow = AmpXRGB(r: 247, g: 210, b: 3)
    static let red = AmpXRGB(r: 240, g: 32, b: 8)

    /// Volume intensity is its fraction; balance intensity is its distance from center.
    static func intensity(for fill: AmpXTrackFill, fraction: Double) -> Double {
        let clamped = min(max(fraction, 0), 1)
        return switch fill {
        case .volume: clamped
        case .balance: abs(clamped - 0.5) * 2
        }
    }

    static func color(for fill: AmpXTrackFill, fraction: Double) -> AmpXRGB {
        self.color(atIntensity: self.intensity(for: fill, fraction: fraction))
    }

    static func color(atIntensity intensity: Double) -> AmpXRGB {
        let t = CGFloat(min(max(intensity, 0), 1))
        return t <= 0.5
            ? self.interpolate(self.green, self.yellow, t * 2)
            : self.interpolate(self.yellow, self.red, (t - 0.5) * 2)
    }

    private static func interpolate(_ from: AmpXRGB, _ to: AmpXRGB, _ t: CGFloat) -> AmpXRGB {
        AmpXRGB(
            r: from.r + (to.r - from.r) * t,
            g: from.g + (to.g - from.g) * t,
            b: from.b + (to.b - from.b) * t
        )
    }
}
