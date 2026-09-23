import AppKit
import Combine

private final class EntheaPlaybackTickView: AmpXContinuousView {
    weak var hostView: EntheaWKHostView?
    weak var audioPlayer: AudioPlayer?
    var isTheater: () -> Bool = { false }

    override func tick(at _: TimeInterval) {
        guard let hostView, let audioPlayer else { return }
        hostView.updatePlayback(
            trackURL: audioPlayer.currentTrack?.url,
            seconds: audioPlayer.playbackClock.currentTime,
            isPlaying: audioPlayer.isPlaying,
            isTheater: self.isTheater()
        )
    }
}

@MainActor
final class EntheaModuleContent: AmpXModuleContent {
    private static let controlStripHeight: CGFloat = 18

    private let audioPlayer: AudioPlayer
    private let isTheater: () -> Bool
    private let onToggleTheater: () -> Void
    private let panelController = EntheaPanelController()
    private let playbackTickView: EntheaPlaybackTickView
    private let previousButton: AmpXButton
    private let titleButton: AmpXButton
    private let looksButton: AmpXButton
    private let dropButton: AmpXButton
    private let theaterButton: AmpXButton
    private let nextButton: AmpXButton

    private var lifecycle: EntheaHostLifecycle?
    private var hostView: EntheaWKHostView?
    private var hostGeneration = 0
    private var isModuleClosed = true
    private var isEffectivelyVisibleFlag = false
    private var cancellables = Set<AnyCancellable>()
    private var lastTitle = ""

    var hostViewForTesting: EntheaWKHostView? {
        self.hostView
    }

    var lifecycleForTesting: EntheaHostLifecycle? {
        self.lifecycle
    }

    init(
        skin: any AmpXSkin,
        audioPlayer: AudioPlayer,
        isTheater: @escaping () -> Bool,
        onToggleTheater: @escaping () -> Void
    ) {
        self.audioPlayer = audioPlayer
        self.isTheater = isTheater
        self.onToggleTheater = onToggleTheater
        self.playbackTickView = EntheaPlaybackTickView(skin: skin)
        self.previousButton = AmpXButton(skin: skin)
        self.titleButton = AmpXButton(skin: skin)
        self.looksButton = AmpXButton(skin: skin)
        self.dropButton = AmpXButton(skin: skin)
        self.theaterButton = AmpXButton(skin: skin)
        self.nextButton = AmpXButton(skin: skin)
        super.init(skin: skin)
        self.configureControls()
        self.bindModels()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reopenHost() {
        self.isModuleClosed = false
        self.ensureHostLoaded()
        if self.isEffectivelyVisibleFlag {
            self.lifecycle?.setVisible(true)
            self.syncPlaybackToHost()
        }
    }

    func closeHost() {
        self.hostGeneration += 1
        self.lifecycle?.close()
        self.lifecycle = nil
        self.hostView?.removeFromSuperview()
        self.hostView = nil
        self.isModuleClosed = true
        self.playbackTickView.hostView = nil
    }

    override func setEffectivelyVisible(_ visible: Bool) {
        guard !self.isModuleClosed else { return }
        self.playbackTickView.setEffectivelyVisible(visible)
        guard visible != self.isEffectivelyVisibleFlag else { return }
        self.isEffectivelyVisibleFlag = visible
        self.ensureHostLoaded()
        self.lifecycle?.setVisible(visible)
        if visible {
            self.syncPlaybackToHost()
            self.applyBackingScaleIfNeeded()
        }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        self.layoutControls()
        self.applyBackingScaleIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.applyBackingScaleIfNeeded()
        self.lifecycle?.setVisible(self.isEffectivelyVisibleFlag && !self.isModuleClosed)
    }

    func refreshTheaterPresentation() {
        self.refreshTheaterButton()
        self.layoutControls()
        self.syncPlaybackToHost()
        self.applyBackingScaleIfNeeded()
    }

    func scheduleDeferredLayoutForTesting() {
        let generation = self.hostGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self, self.hostGeneration == generation, self.hostView != nil else { return }
            self.applyBackingScaleIfNeeded()
        }
    }

    private func configureControls() {
        self.playbackTickView.audioPlayer = self.audioPlayer
        self.playbackTickView.isTheater = { [weak self] in self?.isTheater() ?? false }

        self.previousButton.label = "◀"
        self.previousButton.accessibilityTitle = "Previous ENTHEA mode"
        self.previousButton.action = { [weak self] in
            guard let self else { return }
            if NSEvent.modifierFlags.contains(.shift) {
                self.panelController.nudgeDose(-0.05)
            } else {
                self.panelController.previousMode()
            }
            self.refreshTitleButton()
        }

        self.titleButton.accessibilityTitle = "ENTHEA mode title"
        self.titleButton.action = { [weak self] in
            self?.panelController.toggleAutopilot()
            self?.refreshTitleButton()
        }

        self.looksButton.label = "LOOKS"
        self.looksButton.style = .menu
        self.looksButton.accessibilityTitle = "ENTHEA looks"
        self.looksButton.action = { [weak self] in
            self?.showLooksMenu()
        }

        self.dropButton.label = "DROP"
        self.dropButton.accessibilityTitle = "Force drop effect"
        self.dropButton.action = { [weak self] in
            self?.panelController.fireDrop()
        }

        self.theaterButton.label = "⛶"
        self.theaterButton.accessibilityTitle = "Theater mode"
        self.theaterButton.action = { [weak self] in
            self?.onToggleTheater()
            self?.syncPlaybackToHost()
            self?.refreshTheaterButton()
        }

        self.nextButton.label = "▶"
        self.nextButton.accessibilityTitle = "Next ENTHEA mode"
        self.nextButton.action = { [weak self] in
            guard let self else { return }
            if NSEvent.modifierFlags.contains(.shift) {
                self.panelController.nudgeDose(0.05)
            } else {
                self.panelController.nextMode()
            }
            self.refreshTitleButton()
        }

        for control in [
            self.previousButton, self.titleButton, self.looksButton, self.dropButton, self.theaterButton, self.nextButton,
            self.playbackTickView,
        ] {
            addSubview(control)
        }
        self.refreshTitleButton()
        self.refreshTheaterButton()
        self.layoutControls()
    }

    private func bindModels() {
        self.audioPlayer.$currentTrack
            .combineLatest(self.audioPlayer.$isPlaying)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.syncPlaybackToHost()
            }
            .store(in: &self.cancellables)

        self.panelController.$modeName
            .combineLatest(self.panelController.$autopilot)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.refreshTitleButton()
            }
            .store(in: &self.cancellables)
    }

    private func ensureHostLoaded() {
        guard self.hostView == nil, !self.isModuleClosed else { return }
        let host = EntheaWKHostView(frame: hostBodyFrame)
        host.panelController = self.panelController
        self.hostView = host
        self.lifecycle = EntheaHostLifecycle(host: host)
        self.playbackTickView.hostView = host
        addSubview(host)
        // Deferred spawn (ported from develop 5562af8): creating the WKWebView during launch layout
        // crashes WebKit's executor check on macOS 26. The host spawns it once windowed.
        host.setDesiredActive(true, contentSize: self.hostBodyFrame.size)
        self.layoutControls()
    }

    private func syncPlaybackToHost() {
        guard let hostView else { return }
        hostView.updatePlayback(
            trackURL: self.audioPlayer.currentTrack?.url,
            seconds: self.audioPlayer.playbackClock.currentTime,
            isPlaying: self.audioPlayer.isPlaying,
            isTheater: self.isTheater()
        )
    }

    private func applyBackingScaleIfNeeded() {
        guard let hostView, isEffectivelyVisibleFlag, !isModuleClosed else { return }
        let size = self.isTheater() ? bounds.size : self.hostBodyFrame.size
        hostView.applyBackingScale(for: size)
    }

    private func refreshTitleButton() {
        let title = self.panelController.stripTitle
        guard title != self.lastTitle else { return }
        self.lastTitle = title
        self.titleButton.label = title
    }

    private func refreshTheaterButton() {
        self.theaterButton.label = self.isTheater() ? "▣" : "⛶"
    }

    private func showLooksMenu() {
        let menu = NSMenu()
        for preset in EntheaLookPreset.all {
            let item = NSMenuItem(title: preset.title, action: #selector(self.applyLookPreset(_:)), keyEquivalent: "")
            item.representedObject = preset
            item.target = self
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: self.looksButton.bounds.height), in: self.looksButton)
    }

    @objc private func applyLookPreset(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? EntheaLookPreset else { return }
        self.panelController.applyLook(preset)
        self.refreshTitleButton()
    }

    private var hostBodyFrame: CGRect {
        CGRect(
            x: 0,
            y: Self.controlStripHeight,
            width: bounds.width,
            height: max(0, bounds.height - Self.controlStripHeight)
        )
    }

    private func layoutControls() {
        let inTheater = self.isTheater()
        let controlsHidden = inTheater
        for control in [
            self.previousButton, self.titleButton, self.looksButton, self.dropButton, self.theaterButton, self.nextButton,
        ] {
            control.isHidden = controlsHidden
        }

        if inTheater {
            self.hostView?.frame = bounds
            self.playbackTickView.frame = .zero
            return
        }

        let stripY = bounds.minY
        let buttonWidth: CGFloat = 28
        let titleWidth = max(120, bounds.width - buttonWidth * 5 - 16)
        var x = bounds.minX + 4
        self.previousButton.frame = CGRect(x: x, y: stripY + 1, width: buttonWidth, height: Self.controlStripHeight - 2)
        x += buttonWidth + 2
        self.titleButton.frame = CGRect(x: x, y: stripY + 1, width: titleWidth, height: Self.controlStripHeight - 2)
        x += titleWidth + 2
        self.looksButton.frame = CGRect(x: x, y: stripY + 1, width: 44, height: Self.controlStripHeight - 2)
        x += 46
        self.dropButton.frame = CGRect(x: x, y: stripY + 1, width: 40, height: Self.controlStripHeight - 2)
        x += 42
        self.theaterButton.frame = CGRect(x: x, y: stripY + 1, width: buttonWidth, height: Self.controlStripHeight - 2)
        x += buttonWidth + 2
        self.nextButton.frame = CGRect(x: x, y: stripY + 1, width: buttonWidth, height: Self.controlStripHeight - 2)
        self.hostView?.frame = self.hostBodyFrame
        self.playbackTickView.frame = .zero
    }

    override func draw(_: NSRect) {
        guard !self.isTheater() else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let backingScale = window?.backingScaleFactor ?? 1
        let strip = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: Self.controlStripHeight)
        skin.displayWell(strip, in: context, backingScale: backingScale)
    }
}
