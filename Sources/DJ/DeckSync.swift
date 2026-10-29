import Foundation

/// When and from where the incoming deck starts, so its mix-in downbeat is heard with A's mix-out downbeat
/// (DJ mode spec Revision 2 § Audio graph: beat alignment). Pure.
enum DeckSync {
    /// The shortest wait before B starts; an arm later than this starts B mid-blend instead.
    static let minimumLead = 0.05

    struct Start: Equatable {
        /// The delay to request from `play(at:)`, in host seconds from now.
        let requestedDelay: Double
        /// B's file time to schedule from.
        let incomingStart: Double
    }

    /// `play(at:)` on a player in front of an active time-pitch unit waits `requestedDelay / incomingRate` of real
    /// time (measured: the player's clock runs at its playback rate), so the request is scaled by B's rate. When A
    /// is already past its mix-out, or too close to it, B starts after `minimumLead` from the point it would have
    /// reached by then.
    static func start(
        outgoingNow: Double,
        outgoingTarget: Double,
        outgoingRate: Double,
        incomingRate: Double,
        incomingStart: Double
    ) -> Start {
        let rateA = max(outgoingRate, 0.000_1)
        let rateB = max(incomingRate, 0.000_1)
        let delay = (outgoingTarget - outgoingNow) / rateA
        guard delay < self.minimumLead else {
            return Start(requestedDelay: delay * rateB, incomingStart: incomingStart)
        }
        let late = self.minimumLead - delay
        return Start(requestedDelay: self.minimumLead * rateB, incomingStart: incomingStart + late * rateB)
    }
}
