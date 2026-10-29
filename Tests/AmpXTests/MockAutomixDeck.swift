@testable import AmpX
import Foundation

/// The Automix surface of `AudioPlayer`, recorded.
@MainActor
final class MockAutomixDeck: AutomixDeckControlling {
    var currentTrack: Track?
    var duration: TimeInterval = 375
    var isPlaying = true
    var isBlending = false
    var onAutomixTrackChanged: (@MainActor @Sendable (Track) -> Void)?
    var onTransitionCancelled: (@MainActor @Sendable () -> Void)?

    var fileTime: Double = 0
    var rate: Double = 1
    var prepareSucceeds = true
    /// Like the real player: the prepare completion arrives on a later MainActor turn.
    var completesAsynchronously = false
    private(set) var prepared: [PreparedTransition] = []
    private(set) var armed: [UUID] = []
    private(set) var cancelCount = 0
    private(set) var rates: [Double] = []
    private(set) var completeNowCount = 0

    func prepareTransition(_ prepared: PreparedTransition, completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        self.prepared.append(prepared)
        let ok = self.prepareSucceeds
        if self.completesAsynchronously {
            Task { @MainActor in completion(ok) }
        } else {
            completion(ok)
        }
    }

    func armTransition(token: UUID) {
        self.armed.append(token)
    }

    func cancelTransition() {
        self.cancelCount += 1
    }

    func completeTransitionNow() -> Bool {
        guard self.isBlending else { return false }
        self.completeNowCount += 1
        return true
    }

    func setLiveRate(_ rate: Double) {
        self.rate = rate
        self.rates.append(rate)
    }

    func liveEffectiveState() -> (fileTime: Double, rate: Double)? {
        self.currentTrack == nil ? nil : (self.fileTime, self.rate)
    }
}

/// Library data keyed by file URL.
final class MockAutomixLibrary: AutomixLibrary, @unchecked Sendable {
    var tracks: [URL: (row: LibraryRow?, track: AutomixTrack)] = [:]
    var poolRows: [LibraryRow] = []
    private(set) var poolRequests: [(PickPool, LibraryQuery?)] = []

    func track(url: URL, duration: Double) async -> (row: LibraryRow?, track: AutomixTrack) {
        self.tracks[url] ?? (nil, .unknown(duration: duration))
    }

    func pool(_ pickFrom: PickPool, filter: LibraryQuery?) async -> [LibraryRow] {
        self.poolRequests.append((pickFrom, filter))
        return self.poolRows
    }
}
