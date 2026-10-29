import Foundation

/// The incoming deck starts at a host time, shared by both decks, so output latency cancels out (DJ mode spec
/// Revision 2 § Audio graph: beat alignment). Pure.
enum DeckSync {
    /// The host time at which the outgoing deck reaches `outgoingTarget` (file seconds), playing at `outgoingRate`.
    /// A target already passed starts at once.
    static func startHostTime(
        nowHostTime: UInt64,
        outgoingNow: Double,
        outgoingTarget: Double,
        outgoingRate: Double,
        ticksPerSecond: Double
    ) -> UInt64 {
        let seconds = max(0, outgoingTarget - outgoingNow) / max(outgoingRate, 0.000_1)
        return nowHostTime + UInt64((seconds * ticksPerSecond).rounded())
    }
}
