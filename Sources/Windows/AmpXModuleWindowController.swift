import AppKit

/// One borderless window per module (Winamp 2.x). The controller owns layout of the module view
/// inside its window; where the window sits, and which windows move with it, is the coordinator's.
@MainActor
final class AmpXModuleWindowController: NSWindowController, NSWindowDelegate {
    let moduleID: AmpXModuleID

    weak var coordinator: AmpXHostCoordinator?
    private let containerView = NSView()
    private var moveSaveWorkItem: DispatchWorkItem?

    init(moduleID: AmpXModuleID, coordinator: AmpXHostCoordinator, skin: any AmpXSkin, frame: CGRect) {
        self.moduleID = moduleID
        self.coordinator = coordinator

        let window = AmpXHostWindow(
            contentRect: frame,
            styleMask: [.borderless, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = self.containerView
        window.backgroundColor = skin.background
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.delegate = self
        AmpXWindowChrome.apply(to: window, minimumHeaderHeight: AmpXMetrics.headerHeight)
        window.setFrame(frame, display: false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var moduleView: AmpXModuleView? {
        self.containerView.subviews.compactMap { $0 as? AmpXModuleView }.first
    }

    /// Hosts `view` and lays it out at `size` without moving the window.
    func install(_ view: AmpXModuleView, size: CGSize, playlistViewportHeight: CGFloat) {
        if view.superview !== self.containerView {
            view.removeFromSuperview()
            self.containerView.addSubview(view)
        }
        view.isHidden = false
        self.layoutModuleView(size: size, playlistViewportHeight: playlistViewportHeight)
    }

    /// Lays the hosted view out at `size`, e.g. after a windowshade toggle or Playlist resize.
    func layoutModuleView(size: CGSize, playlistViewportHeight: CGFloat) {
        guard let view = self.moduleView else { return }
        view.applyLayout(frame: CGRect(origin: .zero, size: size))
        if !view.isContentCollapsed, let playlist = view.content as? PlaylistModuleContent {
            playlist.setRowViewportHeight(playlistViewportHeight)
        }
        self.containerView.frame = CGRect(origin: .zero, size: size)
        self.updateResizeConstraints(contentSize: size)
    }

    func applyFrame(_ frame: CGRect) {
        guard let window, AmpXLayoutStore.isValidFrame(frame), window.frame != frame else { return }
        window.setFrame(frame, display: true)
        self.containerView.frame = CGRect(origin: .zero, size: frame.size)
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_: NSWindow) -> Bool {
        self.coordinator?.closeModule(self.moduleID)
        return false
    }

    func windowDidMove(_: Notification) {
        guard let window, !window.inLiveResize else { return }
        self.moveSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let window = self.window else { return }
            self.coordinator?.moduleWindowDidMove(self.moduleID, frame: window.frame)
        }
        self.moveSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    /// Cancels a pending debounced save and reports the live frame immediately (quit path).
    func flushPendingFramePersistence() {
        self.moveSaveWorkItem?.cancel()
        self.moveSaveWorkItem = nil
        guard let window, window.isVisible else { return }
        self.coordinator?.moduleWindowDidMove(self.moduleID, frame: window.frame)
    }

    func windowWillStartLiveResize(_: Notification) {
        self.coordinator?.moduleWindowWillStartLiveResize(self.moduleID)
    }

    func windowDidResize(_: Notification) {
        guard let window, window.inLiveResize else { return }
        self.coordinator?.moduleWindowDidLiveResize(self.moduleID, frame: window.frame)
    }

    func windowDidEndLiveResize(_: Notification) {
        guard let window else { return }
        self.coordinator?.moduleWindowDidEndLiveResize(self.moduleID, frame: window.frame)
    }

    func windowDidMiniaturize(_: Notification) {
        self.coordinator?.moduleWindowDidMiniaturize(self.moduleID)
    }

    func windowDidDeminiaturize(_: Notification) {
        self.coordinator?.moduleWindowDidDeminiaturize(self.moduleID)
    }

    func windowDidChangeOcclusionState(_: Notification) {
        self.coordinator?.refreshEffectiveVisibility()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(
            width: min(max(frameSize.width, sender.contentMinSize.width), sender.contentMaxSize.width),
            height: min(max(frameSize.height, sender.contentMinSize.height), sender.contentMaxSize.height)
        )
    }

    /// Only an expanded Playlist resizes, in both axes (spec Revision 9).
    private func updateResizeConstraints(contentSize: CGSize) {
        guard let window else { return }
        let canResize = self.moduleID == .playlist && self.coordinator?.state.collapsed.contains(.playlist) == false
        window.contentMinSize = NSSize(
            width: canResize ? AmpXMetrics.minimumPlaylistWidth : contentSize.width,
            height: canResize
                ? AmpXMetrics.headerHeight + AmpXMetrics.playlistNonRowChrome + AmpXMetrics.minimumPlaylistViewportHeight
                : contentSize.height
        )
        window.contentMaxSize = NSSize(
            width: canResize ? .greatestFiniteMagnitude : contentSize.width,
            height: canResize ? .greatestFiniteMagnitude : contentSize.height
        )
    }
}
