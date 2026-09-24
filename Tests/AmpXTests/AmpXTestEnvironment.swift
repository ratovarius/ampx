import AppKit
import XCTest

/// Guards for tests that depend on hardware a GitHub macOS runner lacks.
enum AmpXTestEnvironment {
    /// Set by the CI workflow via `TEST_RUNNER_CI` (xcodebuild strips the prefix for the test process).
    static var isCI: Bool {
        ProcessInfo.processInfo.environment["CI"] == "true"
    }

    /// Runners have no audio output device and a virtual GPU, so real-time playback and frame
    /// pacing are unreliable there.
    static func skipOnCI(_ reason: String) throws {
        if self.isCI {
            throw XCTSkip("Skipped on CI: \(reason)")
        }
    }

    /// Pixel-exact reference captures assume a 2x (Retina) backing store.
    @MainActor
    static func skipUnlessRetina() throws {
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        if scale < 2 {
            throw XCTSkip("Reference captures assume a 2x display; this one is \(scale)x")
        }
    }
}
