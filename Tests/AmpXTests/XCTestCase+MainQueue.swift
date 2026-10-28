@testable import AmpX
import XCTest

/// Mutable container for values written from `@Sendable` async callbacks in tests.
final class SendableBox<T>: @unchecked Sendable {
    var value: T

    init(_ value: T) {
        self.value = value
    }
}

extension XCTestCase {
    /// Yields the main actor so nested `Task { @MainActor }` callbacks can finish.
    func waitForMainQueue(timeout: TimeInterval = 2.0, file _: StaticString = #filePath, line _: UInt = #line) {
        let expectation = expectation(description: "main actor drain")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
    }

    /// Waits for a delayed main-actor callback (e.g. auto-play after import).
    func waitForMainQueue(after delay: TimeInterval, timeout: TimeInterval = 2.0, file _: StaticString = #filePath, line _: UInt = #line) {
        let expectation = expectation(description: "main actor yield after delay")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout + delay)
    }

    @MainActor
    func waitForTrackCount(
        _ expected: Int,
        on manager: PlaylistManager,
        timeout: TimeInterval = 10.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if manager.tracks.count == expected {
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for \(expected) tracks, got \(manager.tracks.count)", file: file, line: line)
    }

    /// Spins the main run loop until `condition` holds, or `timeout` passes. Unlike a fixed delay, a slow
    /// machine (a cold CI runner) only costs time, not a false failure.
    func waitForMainQueue(until condition: () -> Bool, timeout: TimeInterval = 10) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    /// Runs `operation` on the main actor and fails, naming `step`, if it has not finished within `seconds`,
    /// so a hang reports where it is instead of exhausting the test's time allowance.
    @MainActor
    func awaitStep(
        _ step: String,
        within seconds: Double = 30,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: @escaping @MainActor () async -> Void
    ) async -> Bool {
        let once = OnceFlag()
        let finished = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            Task { @MainActor in
                await operation()
                if once.claim() {
                    continuation.resume(returning: true)
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                if once.claim() {
                    continuation.resume(returning: false)
                }
            }
        }
        if !finished {
            XCTFail("\(step) did not finish within \(Int(seconds)) s", file: file, line: line)
        }
        return finished
    }
}

/// Lets exactly one of several racing callers win.
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        self.lock.withLock {
            defer { self.claimed = true }
            return !self.claimed
        }
    }
}
