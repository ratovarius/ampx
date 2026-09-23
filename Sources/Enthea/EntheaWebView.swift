import AppKit
import SwiftUI
import WebKit

/// Timing for macOS 26 + Swift 6: a `WKWebView` created during the first SwiftUI
/// CATransaction at process start SIGSEGVs in `swift_task_isCurrentExecutor`
/// when WebKit applies its remote layer tree (~1s later). Spawn from a real
/// `@MainActor` task after this delay instead.
enum EntheaWebViewLaunch {
    static let webKitSpawnDelayNanoseconds: UInt64 = 300_000_000

    /// XCTest injects into the app process; spawning WKWebView during clone bootstrap
    /// SIGSEGVs the same WebKit executor check. Keep the host black in tests.
    static var isRunningUnderTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}

/// Hosts a `WKWebView` that always fills its AppKit bounds, mirroring `MilkdropMTKHostView`.
/// Needed because panel `NSHostingController`s use `sizingOptions = []`, which often leaves
/// a bare web view at 0×0 inside SwiftUI layout.
final class EntheaWKHostView: NSView, WKNavigationDelegate {
    /// Created lazily after the host is windowed — never during `init` / `makeNSView`.
    private(set) var webView: WKWebView?
    private var jsEvaluator: EntheaWKJavaScriptEvaluator?
    private let audioBridge: EntheaAudioBridge
    private let trackBridge: EntheaTrackBridge
    private var pushTimer: Timer?
    private var didLoadEnthea = false
    /// Classic strip / prefs owner — attached from SwiftUI representable.
    weak var panelController: EntheaPanelController?
    private var lastTrackURL: URL?
    private var lastArtworkTrackURL: URL?
    private var artworkTask: Task<Void, Never>?
    private var lastRenderPaused: Bool?
    private var occlusionObserver: NSObjectProtocol?
    private var isPlaying = false
    private var isTheater = false
    private var lastSeconds: TimeInterval = 0
    private var pendingContentSize: CGSize = .zero
    /// Panel wants audio/timeline IPC; actual `audioBridge.isActive` also requires visible window.
    private var wantsAudioBridge = false
    /// SwiftUI asked for a live page. WKWebView spawn is deferred until we are in a window
    /// and a real `@MainActor` task has slept past the first process-start CATransaction.
    private var desiredActive = false
    private var spawnTask: Task<Void, Never>?

    override init(frame frameRect: NSRect) {
        self.audioBridge = EntheaAudioBridge(featureBus: .shared, evaluator: nil)
        self.trackBridge = EntheaTrackBridge(evaluator: nil)
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.black.cgColor
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        self.webView?.frame = self.bounds
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.clearOcclusionObserver()
        guard let window else {
            self.artworkTask?.cancel()
            return
        }
        self.occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyRenderAndPushPolicy()
            }
        }
        self.applyRenderAndPushPolicy()
        self.scheduleContentLoadIfNeeded()
    }

    private func clearOcclusionObserver() {
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
    }

    @discardableResult
    private func ensureWebView() -> WKWebView {
        if let webView {
            return webView
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.suppressesIncrementalRendering = true
        let webView = WKWebView(frame: self.bounds, configuration: configuration)
        webView.underPageBackgroundColor = .black
        webView.navigationDelegate = self
        self.addSubview(webView)
        self.webView = webView
        let evaluator = EntheaWKJavaScriptEvaluator(webView: webView)
        self.jsEvaluator = evaluator
        self.audioBridge.attach(evaluator: evaluator)
        self.trackBridge.attach(evaluator: evaluator)
        return webView
    }

    private func evaluatePageJavaScript(_ javaScript: String) {
        self.jsEvaluator?.evaluateJavaScript(javaScript, completionHandler: nil)
    }

    /// Load vendored ENTHEA from the folder-reference bundle, or a tiny placeholder if missing.
    func loadEnthea() {
        let webView = self.ensureWebView()
        if let index = EntheaBundleLoader.indexHTMLURL(),
           let directory = EntheaBundleLoader.directoryURL()
        {
            self.didLoadEnthea = true
            webView.loadFileURL(index, allowingReadAccessTo: directory)
            return
        }
        self.didLoadEnthea = true
        self.loadPlaceholder()
    }

    func setDesiredActive(_ active: Bool, contentSize: CGSize) {
        self.desiredActive = active
        self.pendingContentSize = contentSize
        if active {
            self.applyBackingScale(for: contentSize)
            self.scheduleContentLoadIfNeeded()
        } else {
            self.teardown()
        }
    }

    private func scheduleContentLoadIfNeeded() {
        guard self.desiredActive, self.window != nil else { return }
        if self.didLoadEnthea {
            self.setAudioBridgeActive(true)
            return
        }
        guard self.spawnTask == nil else { return }
        self.spawnTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: EntheaWebViewLaunch.webKitSpawnDelayNanoseconds)
            guard let self, !Task.isCancelled else { return }
            self.spawnTask = nil
            guard self.desiredActive, self.window != nil, !self.didLoadEnthea else { return }
            self.ensureWebView()
            self.loadEnthea()
            self.applyBackingScale(for: self.pendingContentSize)
            self.setAudioBridgeActive(true)
            self.trackBridge.tickPosition(seconds: self.lastSeconds, paused: !self.isPlaying)
            self.applyRenderAndPushPolicy()
        }
    }

    func loadPlaceholder() {
        let html = """
        <!doctype html><meta charset=utf-8>
        <body style="margin:0;background:#000;color:#0f0;font:12px monospace;display:flex;align-items:center;justify-content:center;height:100vh">
        ENTHEA
        </body>
        """
        self.ensureWebView().loadHTMLString(html, baseURL: nil)
    }

    func applyBackingScale(for size: CGSize) {
        let screenScale = self.window?.screen?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        let scale = EntheaBackingScale.scale(forSize: size, screenScale: screenScale)
        let js = "window.winampEnthea && window.winampEnthea.setBackingScale(\(scale));"
        self.evaluatePageJavaScript(js)
    }

    func setAudioBridgeActive(_ active: Bool) {
        self.wantsAudioBridge = active
        self.applyRenderAndPushPolicy()
    }

    /// Push playlist playhead + kick analysis / cover art when the current track URL changes.
    func updatePlayback(trackURL: URL?, seconds: TimeInterval, isPlaying: Bool, isTheater: Bool) {
        self.isPlaying = isPlaying
        self.isTheater = isTheater
        self.lastSeconds = seconds
        if trackURL != self.lastTrackURL {
            self.lastTrackURL = trackURL
            self.trackBridge.trackDidChange(url: trackURL)
            self.loadCoverArt(for: trackURL)
        }
        self.trackBridge.tickPosition(seconds: seconds, paused: !isPlaying)
        self.applyRenderAndPushPolicy()
    }

    /// Blanking the page does NOT stop the WebContent process — only releasing the
    /// `WKWebView` does. `AmpXPanelWindowManager.hidePanel` nils `contentViewController`
    /// for `.visualizer`, which deallocates this view; this just stops work in the window
    /// between that and dealloc.
    func teardown() {
        self.spawnTask?.cancel()
        self.spawnTask = nil
        self.clearOcclusionObserver()
        self.setAudioBridgeActive(false)
        self.trackBridge.clearTimeline()
        self.lastTrackURL = nil
        self.lastArtworkTrackURL = nil
        self.artworkTask?.cancel()
        self.artworkTask = nil
        self.lastRenderPaused = nil
        let controller = self.panelController
        Task { @MainActor in
            controller?.hostDidTeardown()
        }
        self.didLoadEnthea = false
        self.desiredActive = false
        if let webView {
            webView.stopLoading()
            webView.load(URLRequest(url: URL(string: "about:blank")!))
        }
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        self.applyBackingScale(for: self.bounds.size)
        self.evaluatePageJavaScript(
            "window.winampEnthea && window.winampEnthea.hideChrome();"
        )
        self.applyRenderAndPushPolicy()
        // Re-push cover art after a reload so Image Warp survives WebContent restarts.
        if let url = self.lastTrackURL {
            self.lastArtworkTrackURL = nil
            self.loadCoverArt(for: url)
        }
        guard self.didLoadEnthea, let controller = self.panelController, let evaluator = self.jsEvaluator else { return }
        Task { @MainActor in
            controller.attach(evaluator: evaluator)
            controller.hostDidFinishLoad()
        }
        self.trackBridge.hostDidBecomeReady()
    }

    private func applyRenderAndPushPolicy() {
        let size = self.bounds.size
        self.audioBridge.maxPushHz = EntheaPushRatePolicy.pushHz(
            forContentSize: size,
            isTheater: self.isTheater
        )

        let occluded: Bool = if let window {
            !window.occlusionState.contains(.visible)
        } else {
            true
        }

        let audioOn = self.wantsAudioBridge && !occluded
        self.audioBridge.isActive = audioOn
        self.trackBridge.isActive = audioOn
        if audioOn {
            self.startPushTimerIfNeeded()
        } else {
            self.stopPushTimer()
        }

        let paused = !self.wantsAudioBridge || !self.isPlaying || occluded
        guard self.lastRenderPaused != paused else { return }
        self.lastRenderPaused = paused
        let js = "window.winampEnthea&&window.winampEnthea.setRenderPaused(\(paused ? "true" : "false"));"
        self.evaluatePageJavaScript(js)
    }

    private func loadCoverArt(for trackURL: URL?) {
        self.artworkTask?.cancel()
        guard let trackURL else {
            self.lastArtworkTrackURL = nil
            return
        }
        guard trackURL != self.lastArtworkTrackURL else { return }
        self.artworkTask = Task { [weak self] in
            let data = await TrackArtworkLoader.loadImageData(from: trackURL)
            guard !Task.isCancelled, let self, let data else { return }
            let dataURL = "data:image/jpeg;base64,\(data.base64EncodedString())"
            guard let encoded = try? String(
                data: JSONSerialization.data(withJSONObject: dataURL),
                encoding: .utf8
            ) else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.lastArtworkTrackURL = trackURL
                let js = "window.winampEnthea&&window.winampEnthea.setCoverArt(\(encoded));"
                self.evaluatePageJavaScript(js)
            }
        }
    }

    private func startPushTimerIfNeeded() {
        guard self.pushTimer == nil else { return }
        let audioBridge = self.audioBridge
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
            audioBridge.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.pushTimer = timer
    }

    private func stopPushTimer() {
        self.pushTimer?.invalidate()
        self.pushTimer = nil
    }
}

struct EntheaWebView: NSViewRepresentable {
    var isActive: Bool
    var size: CGSize
    var isTheater: Bool
    var trackURL: URL?
    var currentTime: TimeInterval
    var isPlaying: Bool
    @ObservedObject var controller: EntheaPanelController

    func makeNSView(context _: Context) -> EntheaWKHostView {
        let host = EntheaWKHostView(frame: CGRect(origin: .zero, size: self.size))
        host.panelController = self.controller
        host.updatePlayback(
            trackURL: self.trackURL,
            seconds: self.currentTime,
            isPlaying: self.isPlaying,
            isTheater: self.isTheater
        )
        host.setDesiredActive(self.isActive, contentSize: self.size)
        return host
    }

    func updateNSView(_ host: EntheaWKHostView, context _: Context) {
        host.panelController = self.controller
        host.frame.size = self.size
        host.updatePlayback(
            trackURL: self.trackURL,
            seconds: self.currentTime,
            isPlaying: self.isPlaying,
            isTheater: self.isTheater
        )
        host.setDesiredActive(self.isActive, contentSize: self.size)
    }

    func sizeThatFits(_: ProposedViewSize, nsView _: EntheaWKHostView, context _: Context) -> CGSize? {
        self.size
    }
}
