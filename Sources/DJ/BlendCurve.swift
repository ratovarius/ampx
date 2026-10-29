import Foundation

/// A transition's envelopes as functions of the outgoing track's file time (DJ mode spec Revision 2 § Transitions):
/// ramps follow audio time, so they freeze whenever the outgoing deck's clock does. Pure.
struct BlendCurve: Equatable, Sendable {
    let plan: MixPlan

    func progress(atOutgoingTime time: Double) -> Double {
        guard self.plan.length > 0 else { return 1 }
        return min(max((time - self.plan.outgoingStart) / self.plan.length, 0), 1)
    }

    /// Equal-power: the two squares always sum to 1, so loudness holds through the blend.
    func gains(at progress: Double) -> (outgoing: Float, incoming: Float) {
        let angle = min(max(progress, 0), 1) * .pi / 2
        return (Float(cos(angle)), Float(sin(angle)))
    }

    /// Bass Swap's low cut: on B until the switch bar, then on A. Never for a crossfade.
    func lowCut(atOutgoingTime time: Double) -> (outgoing: Bool, incoming: Bool) {
        guard case .beatmatched(_, .bassSwap) = self.plan.kind else { return (false, false) }
        let switched = self.isPastSwitch(atOutgoingTime: time)
        return (switched, !switched)
    }

    func isPastSwitch(atOutgoingTime time: Double) -> Bool {
        time >= self.plan.switchTime
    }
}
