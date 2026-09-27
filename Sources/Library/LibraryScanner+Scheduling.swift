import Foundation
import os

private let schedulingLogger = Logger(subsystem: "com.ampx.macos", category: "LibraryScanner")

/// Spec: "Scan scheduling". At most one scan across all roots; a FIFO with at most one pending entry per root;
/// any number of requests during a run collapse into one follow-up.
extension LibraryScanner {
    func requestScan(rootID: UUID) {
        if self.runningRoot == rootID {
            self.rescanRequested.insert(rootID)
        } else if self.queued.insert(rootID).inserted {
            self.queue.append(rootID)
        }
        self.startDrainIfIdle()
    }

    /// Revokes in the store first, so a save already suspended is rejected whenever it arrives; then drops the
    /// queued entry and follow-up, and cancels the running task. The run keeps its slot until it returns.
    func cancelScans(rootID: UUID) async {
        await self.store.revokeScan(rootID: rootID)
        if self.queued.remove(rootID) != nil {
            self.queue.removeAll { $0 == rootID }
        }
        self.rescanRequested.remove(rootID)
        if self.runningRoot == rootID {
            self.runningTask?.cancel()
        }
    }

    /// Cancels queued and running work and waits for the drain to finish.
    func stop() async {
        for rootID in self.queue {
            await self.store.revokeScan(rootID: rootID)
        }
        self.queue.removeAll()
        self.queued.removeAll()
        self.rescanRequested.removeAll()
        if let running = self.runningRoot {
            await self.cancelScans(rootID: running)
        }
        await self.drainTask?.value
    }

    /// Test and teardown hook: returns once no run is queued or in progress.
    func waitUntilIdle() async {
        while let drain = self.drainTask {
            await drain.value
        }
    }

    // MARK: - Drain

    /// The check-and-set is synchronous on the actor, so reentrancy cannot start a second drain.
    private func startDrainIfIdle() {
        guard self.drainTask == nil, !self.queue.isEmpty else { return }
        self.drainTask = Task(priority: .utility) { await self.drain() }
    }

    private func drain() async {
        while !self.queue.isEmpty {
            let rootID = self.queue.removeFirst()
            self.queued.remove(rootID)
            self.runningRoot = rootID
            self.concurrentRuns += 1
            self.maxConcurrentRuns = max(self.maxConcurrentRuns, self.concurrentRuns)

            let run = Task(priority: .utility) {
                do {
                    let outcome = try await self.scanOnce(rootID: rootID)
                    if outcome.needsFollowUp {
                        self.rescanRequested.insert(rootID)
                    }
                } catch is CancellationError {
                } catch {
                    schedulingLogger.error("Scan of \(rootID, privacy: .public) ended: \(String(describing: error), privacy: .public)")
                }
            }
            self.runningTask = run
            await run.value

            self.runningTask = nil
            self.runningRoot = nil
            self.concurrentRuns -= 1
            if self.rescanRequested.remove(rootID) != nil, self.queued.insert(rootID).inserted {
                self.queue.append(rootID)
            }
        }
        self.drainTask = nil
    }
}
