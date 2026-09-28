import Foundation
import os

private let schedulingLogger = Logger(subsystem: "com.ampx.macos", category: "LibraryScanner")

/// One FIFO entry: a root scan, or an exclusive job such as a rekordbox check (rekordbox sync spec
/// § Turn-taking with scans). Neither ever runs alongside the other.
enum LibraryScanJob: Hashable, Sendable {
    case root(UUID)
    case exclusive(UUID)
}

struct LibraryExclusiveJob: Sendable {
    let work: @Sendable () async -> Void
    let finish: @Sendable () -> Void
}

/// Spec: "Scan scheduling". At most one scan across all roots; a FIFO with at most one pending entry per root;
/// any number of requests during a run collapse into one follow-up.
extension LibraryScanner {
    func requestScan(rootID: UUID) {
        if self.runningRoot == rootID {
            self.rescanRequested.insert(rootID)
        } else if self.queued.insert(rootID).inserted {
            self.queue.append(.root(rootID))
        }
        self.startDrainIfIdle()
    }

    /// Queues `work` behind any scan in progress and returns once it has run, or once `stop()` dropped it.
    func performExclusive(_ work: @escaping @Sendable () async -> Void) async {
        let id = UUID()
        let (done, continuation) = AsyncStream.makeStream(of: Void.self)
        self.exclusiveJobs[id] = LibraryExclusiveJob(work: work, finish: { continuation.finish() })
        self.queue.append(.exclusive(id))
        self.startDrainIfIdle()
        for await _ in done {}
    }

    /// Revokes in the store first, so a save already suspended is rejected whenever it arrives; then drops the
    /// queued entry and follow-up, and cancels the running task. The run keeps its slot until it returns.
    func cancelScans(rootID: UUID) async {
        await self.store.revokeScan(rootID: rootID)
        if self.queued.remove(rootID) != nil {
            self.queue.removeAll { $0 == .root(rootID) }
        }
        self.rescanRequested.remove(rootID)
        if self.runningRoot == rootID {
            self.runningTask?.cancel()
        }
    }

    /// Cancels queued and running work and waits for the drain to finish.
    func stop() async {
        for case let .root(rootID) in self.queue {
            await self.store.revokeScan(rootID: rootID)
        }
        for case let .exclusive(id) in self.queue {
            self.exclusiveJobs.removeValue(forKey: id)?.finish()
        }
        self.queue.removeAll()
        self.queued.removeAll()
        self.rescanRequested.removeAll()
        if let running = self.runningRoot {
            await self.cancelScans(rootID: running)
        } else {
            self.runningTask?.cancel() // an exclusive job
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
            switch self.queue.removeFirst() {
            case let .root(rootID):
                await self.runScan(rootID)
            case let .exclusive(id):
                await self.runExclusive(id)
            }
        }
        self.drainTask = nil
    }

    private func runScan(_ rootID: UUID) async {
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
            self.queue.append(.root(rootID))
        }
    }

    private func runExclusive(_ id: UUID) async {
        guard let job = self.exclusiveJobs.removeValue(forKey: id) else { return }
        self.concurrentRuns += 1
        self.maxConcurrentRuns = max(self.maxConcurrentRuns, self.concurrentRuns)
        let run = Task(priority: .utility) { await job.work() }
        self.runningTask = run
        await run.value
        self.runningTask = nil
        self.concurrentRuns -= 1
        job.finish()
    }
}
