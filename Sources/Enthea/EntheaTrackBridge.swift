import Foundation

/// Pushes natively computed timelines into ENTHEA and drives the `AUDIO.fileEl` playhead shim.
///
/// Analysis runs off the main actor. Position updates are coalesced (~8 Hz) so they do not
/// compete with the 60 Hz audio-bin push.
final class EntheaTrackBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.ampx.enthea.track")
    private weak var evaluator: EntheaJavaScriptEvaluating?
    private var analysisGeneration = 0
    private var analyzedURL: URL?
    private var lastPositionPush: CFAbsoluteTime = 0
    private var lastSeconds: TimeInterval = -1
    private var lastPaused: Bool?
    private var positionInFlight = false
    private var _isActive = false

    var isActive: Bool {
        get { self.queue.sync { self._isActive } }
        set { self.queue.sync { self._isActive = newValue } }
    }

    /// Minimum interval between `setPosition` IPC calls.
    private let positionInterval: CFAbsoluteTime = 1.0 / 8.0

    init(evaluator: EntheaJavaScriptEvaluating? = nil) {
        self.evaluator = evaluator
    }

    func attach(evaluator: EntheaJavaScriptEvaluating?) {
        self.queue.sync { self.evaluator = evaluator }
    }

    /// Cancel in-flight analysis and clear the JS timeline.
    func clearTimeline() {
        let evaluator: EntheaJavaScriptEvaluating? = self.queue.sync {
            self.analysisGeneration += 1
            self.analyzedURL = nil
            return self.evaluator
        }
        evaluator?.evaluateJavaScript(
            "window.winampAudio&&window.winampAudio.setTimeline(null);",
            completionHandler: nil
        )
    }

    /// After the WebView reloads, re-push the last analyzed timeline (page state was wiped).
    func hostDidBecomeReady() {
        let url: URL? = self.queue.sync {
            let url = self.analyzedURL
            self.analyzedURL = nil
            return url
        }
        self.trackDidChange(url: url)
    }

    /// Re-analyze when the playlist track URL changes. No-ops if `url` matches the last analysis.
    func trackDidChange(url: URL?) {
        guard let url else {
            self.clearTimeline()
            return
        }

        let start: (generation: Int, evaluator: EntheaJavaScriptEvaluating?)? = self.queue.sync {
            if self.analyzedURL == url {
                return nil
            }
            self.analyzedURL = url
            self.analysisGeneration += 1
            return (self.analysisGeneration, self.evaluator)
        }
        guard let start else { return }

        start.evaluator?.evaluateJavaScript(
            "window.winampAudio&&window.winampAudio.setTimeline(null);",
            completionHandler: nil
        )

        let generation = start.generation
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let timeline: EntheaTimeline
            do {
                timeline = try EntheaTrackAnalyzer.analyze(url: url)
            } catch {
                return
            }
            guard let self else { return }
            let push: (EntheaJavaScriptEvaluating, String)? = self.queue.sync {
                guard self.analysisGeneration == generation, self.analyzedURL == url,
                      let evaluator = self.evaluator,
                      let json = try? timeline.jsonObjectString()
                else { return nil }
                return (evaluator, json)
            }
            guard let push else { return }
            push.0.evaluateJavaScript(
                "window.winampAudio&&window.winampAudio.setTimeline(\(push.1));",
                completionHandler: nil
            )
        }
    }

    /// Drive `AUDIO.fileEl` clock. Call from the host display timer; internally rate-limits.
    func tickPosition(seconds: TimeInterval, paused: Bool) {
        let work: (EntheaJavaScriptEvaluating, String)? = self.queue.sync {
            let inFlight = self.positionInFlight
            let now = CFAbsoluteTimeGetCurrent()
            let due = (now - self.lastPositionPush) >= self.positionInterval
                || self.lastPaused != paused
                || abs(seconds - self.lastSeconds) > 0.5
            guard self._isActive, let evaluator = self.evaluator, !inFlight, due else {
                return nil
            }
            self.lastPositionPush = now
            self.lastSeconds = seconds
            self.lastPaused = paused
            self.positionInFlight = true
            let js = "window.winampAudio&&window.winampAudio.setPosition(\(seconds),\(paused ? "true" : "false"));"
            return (evaluator, js)
        }
        guard let work else { return }
        work.0.evaluateJavaScript(work.1) { [weak self] _, _ in
            self?.queue.sync { self?.positionInFlight = false }
        }
    }
}
