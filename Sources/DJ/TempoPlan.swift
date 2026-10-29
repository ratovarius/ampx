import Foundation

/// Tempo matching and the glide back (DJ mode spec Revision 2 § Tempo). Pure.
enum TempoPlan {
    /// Beyond this rate change, a transition is a plain crossfade.
    static let clamp = 0.06

    /// The factor in {½, 1, 2} that brings `incoming` nearest `outgoing`: a half- or double-tempo track's beats line
    /// up one for two.
    static func octaveFactor(incoming: Double, outgoing: Double) -> Double {
        [1.0, 2.0, 0.5].min { abs(incoming * $0 - outgoing) < abs(incoming * $1 - outgoing) } ?? 1
    }

    /// The incoming deck's rate, or nil when it falls outside the clamp.
    static func matchRate(outgoingEffectiveBPM: Double, incomingLocalBPM: Double) -> Double? {
        guard outgoingEffectiveBPM > 0, incomingLocalBPM > 0 else { return nil }
        let normalised = incomingLocalBPM * self.octaveFactor(incoming: incomingLocalBPM, outgoing: outgoingEffectiveBPM)
        let rate = outgoingEffectiveBPM / normalised
        return abs(rate - 1) <= self.clamp + 1e-12 ? rate : nil
    }

    /// The live track's BPM after one bar of glide.
    static func glideStep(currentBPM: Double, originalBPM _: Double, nextBPM _: Double?, speedPer4Bars _: Double) -> Double {
        currentBPM
    }
}
