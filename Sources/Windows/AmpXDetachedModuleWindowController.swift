import AppKit

@MainActor
final class AmpXDetachedModuleWindowController: NSWindowController, NSWindowDelegate {
    let moduleID: AmpXModuleID

    weak var coordinator: AmpXHostCoordinator?
    private let skin: any AmpXSkin
    private let containerView = NSView()
    private var moveSaveWorkItem: DispatchWorkItem?

    init(
        moduleID: AmpXModuleID,
        coordinator: AmpXHostCoordinator,
        skin: any AmpXSkin,
        inheritedWidth: CGFloat,
        frame: CGRect
    ) {
        self.moduleID = moduleID
        self.coordinator = coordinator
        self.skin = skin

        let window = AmpXHostWindow(
            contentRect: frame,
            styleMask: [.borderless, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = self.containerView
        window.backgroundColor = skin.background

        super.init(window: window)

        window.delegate = self
        AmpXWindowChrome.apply(to: window, minimumHeaderHeight: AmpXMetrics.headerHeight)
        self.resizeToInheritedWidth(inheritedWidth)
        window.setFrame(frame, display: false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attachModuleView(_ view: AmpXModuleView, layout: AmpXLayoutResult) {
        view.removeFromSuperview()
        view.isHidden = false
        self.containerView.addSubview(view)
        if let frame = layout.frames[moduleID] {
            // AppKit rounds borderless native window sizes to whole points, even on Retina.
            // Round the logical compact height before backing-pixel alignment to avoid
            // double rounding (27.36 -> 27.5 -> 28) and keep content flush with its host.
            let height = view.isContentCollapsed && view.compactContent != nil ? frame.height.rounded() : frame.height
            view.applyLayout(frame: CGRect(x: 0, y: 0, width: frame.width, height: height))
        }
        if !view.isContentCollapsed, let playlist = view.content as? PlaylistModuleContent {
            playlist.setRowViewportHeight(layout.playlistViewportHeight)
        }
        self.containerView.frame = self.containerView.superview?.bounds ?? .zero
        self.updateResizeConstraints(contentSize: view.frame.size)
        self.resizeWindow(toContentSize: view.frame.size)
        self.coordinator?.refreshEffectiveVisibility()
    }

    func detachModuleView() -> AmpXModuleView? {
        self.containerView.subviews.compactMap { $0 as? AmpXModuleView }.first
    }

    func applyFrame(_ frame: CGRect) {
        guard let window, AmpXLayoutStore.isValidFrame(frame) else { return }
        var target = frame
        if let view = self.detachModuleView(), view.isContentCollapsed, view.compactContent != nil {
            // Placement must not reapply an unsnapped saved height after attachModuleView sized
            // the content. AppKit encloses fractional window origins, otherwise adding a row.
            target.size = view.frame.size
            target.origin = CGPoint(x: frame.minX.rounded(), y: frame.maxY.rounded() - target.height)
        }
        window.setFrame(target, display: true)
    }

    func windowDidMove(_: Notification) {
        guard let window, !window.inLiveResize else { return }
        guard self.coordinator?.isInTheater != true || self.moduleID != .enthea else { return }

        self.moveSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let window = self.window else { return }
            self.coordinator?.updateDetachedFrame(self.moduleID, frame: window.frame)
        }
        self.moveSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    /// Cancels a pending debounced save and writes the live frame immediately (quit path).
    func flushPendingFramePersistence() {
        self.moveSaveWorkItem?.cancel()
        self.moveSaveWorkItem = nil
        guard let window, !window.inLiveResize else { return }
        guard self.coordinator?.isInTheater != true || self.moduleID != .enthea else { return }
        self.coordinator?.updateDetachedFrame(self.moduleID, frame: window.frame)
    }

    func windowDidResize(_: Notification) {
        guard let window, window.inLiveResize, moduleID == .playlist else { return }
        self.coordinator?.handleDetachedResize(self.moduleID, frame: window.frame)
    }

    func windowDidEndLiveResize(_: Notification) {
        guard self.coordinator?.isInTheater != true || self.moduleID != .enthea else { return }
        guard let window else { return }
        self.coordinator?.handleDetachedResize(self.moduleID, frame: window.frame)
    }

    func windowDidMiniaturize(_: Notification) {
        self.coordinator?.refreshEffectiveVisibility()
    }

    func windowDidDeminiaturize(_: Notification) {
        self.coordinator?.refreshEffectiveVisibility()
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

    /// Only an expanded detached Playlist resizes, in both axes (spec Revision 9).
    private func updateResizeConstraints(contentSize: CGSize) {
        guard let window else { return }
        let canResizePlaylist = self.moduleID == .playlist && self.coordinator?.state.collapsed.contains(.playlist) == false
        window.contentMinSize = NSSize(
            width: canResizePlaylist ? AmpXMetrics.minimumPlaylistWidth : contentSize.width,
            height: canResizePlaylist
                ? AmpXMetrics.headerHeight + AmpXMetrics.playlistNonRowChrome + AmpXMetrics.minimumPlaylistViewportHeight
                : contentSize.height
        )
        window.contentMaxSize = NSSize(
            width: canResizePlaylist ? .greatestFiniteMagnitude : contentSize.width,
            height: canResizePlaylist ? .greatestFiniteMagnitude : contentSize.height
        )
    }

    private func resizeToInheritedWidth(_ inheritedWidth: CGFloat) {
        guard let window else { return }
        var frame = window.frame
        frame.size.width = inheritedWidth
        window.setFrame(frame, display: false)
    }

    private func resizeWindow(toContentSize contentSize: CGSize) {
        guard let window else { return }

        let topY = window.frame.maxY
        window.setContentSize(NSSize(width: contentSize.width, height: contentSize.height))
        var frame = window.frame
        frame.origin.y = topY - frame.height
        window.setFrame(frame, display: false)
    }
}
