import AppKit

@MainActor
final class AmpXStackWindowController: NSWindowController, NSWindowDelegate {
    weak var coordinator: AmpXHostCoordinator?
    private let skin: any AmpXSkin
    private let viewport: AmpXStackViewport
    private var preferredPlaylistViewportHeight: CGFloat
    /// Preferred Playlist width (spec Revision 9); the host width follows the widest left module.
    private var preferredPlaylistWidth: CGFloat
    /// Host width for the current composition, used when horizontal resizing is not allowed.
    private var fixedContentWidth: CGFloat = AmpXMetrics.compositionWidth
    private var isHandlingClose = false
    private var moveSaveWorkItem: DispatchWorkItem?
    private var lastLiveResizeContentSize: NSSize = .zero
    private var isLiveResizing = false
    /// `updateLayout` resizes the window, which re-enters `windowDidResize` synchronously. Without
    /// this guard the nested pass recomputes deltas against a half-applied layout and the host
    /// oscillates between sizes.
    private var isApplyingLayout = false

    init(
        coordinator: AmpXHostCoordinator,
        skin: any AmpXSkin,
        moduleViews: [AmpXModuleID: AmpXModuleView],
        playlistViewportHeight: CGFloat,
        playlistWidth: CGFloat = AmpXMetrics.defaultPlaylistWidth
    ) {
        self.coordinator = coordinator
        self.skin = skin
        self.preferredPlaylistViewportHeight = playlistViewportHeight
        self.preferredPlaylistWidth = playlistWidth
        self.viewport = AmpXStackViewport()

        let window = AmpXHostWindow(
            contentRect: NSRect(x: 0, y: 0, width: AmpXMetrics.compositionWidth, height: AmpXMetrics.playerHeight),
            styleMask: [.borderless, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = self.viewport

        super.init(window: window)

        window.delegate = self
        self.viewport.stackView.setModuleViews(moduleViews)
        self.applyChrome()
        self.updateLayout()
        self.refreshEffectiveVisibility()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var stackViewport: AmpXStackViewport {
        self.viewport
    }

    /// Height the stack may occupy: the visible frame of the window's screen, not the window's own height.
    static func availableHeight(for window: NSWindow?) -> CGFloat {
        let screen = window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        return max(screen?.visibleFrame.height ?? .greatestFiniteMagnitude, 1)
    }

    func setPreferredPlaylistViewportHeight(_ height: CGFloat) {
        self.preferredPlaylistViewportHeight = height
    }

    func setPreferredPlaylistWidth(_ width: CGFloat) {
        self.preferredPlaylistWidth = max(AmpXMetrics.minimumPlaylistWidth, width)
    }

    /// Width is draggable only while an expanded Playlist is docked (spec Revision 9).
    private var canResizeWidth: Bool {
        self.coordinator.map { Self.hasExpandedDockedPlaylist($0.state) } == true
    }

    /// Restores a saved frame by its top edge and width; the height always follows the composition.
    func applyStackFrame(_ frame: CGRect) {
        guard let window, AmpXLayoutStore.isValidFrame(frame) else { return }

        var adjusted = window.frame
        adjusted.origin.x = frame.minX
        // Saved widths from scalable layouts are intentionally ignored.
        adjusted.origin.y = frame.maxY - adjusted.height
        window.setFrame(self.constrainedToVisibleFrame(adjusted), display: false)
        self.updateLayout()
    }

    func updateLayout() {
        guard let window, let coordinator else { return }
        self.isApplyingLayout = true
        defer { self.isApplyingLayout = false }

        let width = max(AmpXMetrics.compositionWidth, self.preferredPlaylistWidth)
        let layout = AmpXLayout.calculate(
            state: coordinator.state,
            width: width,
            playlistViewportHeight: self.preferredPlaylistViewportHeight,
            availableHeight: Self.availableHeight(for: window),
            playlistWidth: self.preferredPlaylistWidth
        )
        let minimumContentWidth = AmpXLayout.calculate(
            state: coordinator.state,
            width: AmpXMetrics.compositionWidth,
            playlistViewportHeight: self.preferredPlaylistViewportHeight,
            availableHeight: Self.availableHeight(for: window),
            playlistWidth: AmpXMetrics.minimumPlaylistWidth
        ).contentWidth
        self.fixedContentWidth = layout.contentWidth
        window.contentMinSize.width = self.canResizeWidth ? minimumContentWidth : layout.contentWidth
        window.contentMaxSize.width = self.canResizeWidth ? .greatestFiniteMagnitude : layout.contentWidth
        self.resizeWindowPreservingTop(width: layout.contentWidth, contentHeight: layout.contentHeight)
        self.viewport.applyLayout(layout, state: coordinator.state)
        self.refreshEffectiveVisibility()
    }

    func clampedFrameSize(for window: NSWindow, to frameSize: NSSize) -> NSSize {
        self.windowWillResize(window, to: frameSize)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(
            width: self.canResizeWidth
                ? max(frameSize.width, sender.contentMinSize.width)
                : self.fixedContentWidth,
            height: self.coordinator.map { Self.hasExpandedDockedPlaylist($0.state) } == true
                ? max(frameSize.height, sender.contentMinSize.height)
                : sender.frame.height
        )
    }

    func windowWillStartLiveResize(_: Notification) {
        self.isLiveResizing = true
        self.lastLiveResizeContentSize = self.viewport.bounds.size
    }

    func windowDidEndLiveResize(_: Notification) {
        self.isLiveResizing = false
        self.lastLiveResizeContentSize = .zero
        guard let window else { return }
        self.coordinator?.handleStackFrameChanged(window.frame)
    }

    func windowDidResize(_: Notification) {
        guard self.isLiveResizing, !self.isApplyingLayout, let coordinator else { return }

        let newSize = self.viewport.bounds.size
        guard self.lastLiveResizeContentSize != .zero else {
            self.lastLiveResizeContentSize = newSize
            return
        }

        let widthDelta = newSize.width - self.lastLiveResizeContentSize.width
        let heightDelta = newSize.height - self.lastLiveResizeContentSize.height
        guard abs(widthDelta) > 0.5 || abs(heightDelta) > 0.5 else { return }

        // A diagonal drag moves both axes in one event: absorb both, or the axis left out is snapped
        // back by the layout pass and the host flickers between two sizes.
        let canResizeHeight = Self.hasExpandedDockedPlaylist(coordinator.state)
        if self.canResizeWidth || canResizeHeight {
            coordinator.resizePlaylist(
                toHostWidth: self.canResizeWidth ? newSize.width : self.fixedContentWidth,
                heightDelta: canResizeHeight ? heightDelta : 0
            )
        } else {
            // Nothing absorbs the drag; snap the composition back.
            self.updateLayout()
        }

        self.lastLiveResizeContentSize = self.viewport.bounds.size
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        guard !self.isHandlingClose else { return true }
        self.isHandlingClose = true
        self.coordinator?.closeStack()
        self.isHandlingClose = false
        return false
    }

    func windowDidMove(_: Notification) {
        guard let window, !window.inLiveResize else { return }

        self.moveSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let window = self.window else { return }
            self.coordinator?.handleStackFrameChanged(window.frame)
        }
        self.moveSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    /// Cancels a pending debounced save and writes the live frame immediately (quit path).
    func flushPendingFramePersistence() {
        self.moveSaveWorkItem?.cancel()
        self.moveSaveWorkItem = nil
        guard let window, !window.inLiveResize else { return }
        self.coordinator?.handleStackFrameChanged(window.frame)
    }

    func windowDidMiniaturize(_: Notification) {
        self.refreshEffectiveVisibility()
    }

    func windowDidDeminiaturize(_: Notification) {
        self.refreshEffectiveVisibility()
    }

    func windowDidChangeOcclusionState(_: Notification) {
        self.refreshEffectiveVisibility()
    }

    private func refreshEffectiveVisibility() {
        self.coordinator?.refreshEffectiveVisibility()
    }

    private func applyChrome() {
        guard let window else { return }
        AmpXWindowChrome.apply(to: window, minimumHeaderHeight: AmpXMetrics.headerHeight)
        // The stack is ragged on the right: a Playlist wider than the Player/Equalizer leaves the
        // column beside them uncovered. An opaque host would paint that gap as a black rectangle,
        // so only the module views draw and the rest of the host stays clear.
        window.isOpaque = false
        window.backgroundColor = .clear
    }

    private static func hasExpandedDockedPlaylist(_ state: AmpXModuleOrder) -> Bool {
        !state.closed.contains(.playlist)
            && !state.detached.contains(.playlist)
            && !state.collapsed.contains(.playlist)
    }

    private func resizeWindowPreservingTop(width: CGFloat, contentHeight: CGFloat) {
        guard let window else { return }

        // One `setFrame`, not `setContentSize` followed by a correction: the intermediate frame of
        // the two-step version is visible mid-drag.
        let content = CGRect(origin: .zero, size: NSSize(width: width, height: contentHeight))
        var frame = window.frame
        frame.size = window.frameRect(forContentRect: content).size
        frame.origin.y = window.frame.maxY - frame.height
        frame = self.constrainedToVisibleFrame(frame)
        guard frame != window.frame else { return }
        window.setFrame(frame, display: false)
        // The host is ragged on the right, so the shadow has to be recomputed from the new shape.
        window.invalidateShadow()
    }

    /// Keeps the window's vertical extent inside the visible frame when it fits; a taller stack stays top-aligned.
    private func constrainedToVisibleFrame(_ frame: CGRect) -> CGRect {
        guard let visible = (window?.screen ?? NSScreen.main)?.visibleFrame else { return frame }
        var result = frame
        if result.width <= visible.width {
            result.origin.x = min(max(result.minX, visible.minX), visible.maxX - result.width)
        } else {
            result.origin.x = visible.minX
        }
        if result.height <= visible.height {
            result.origin.y = min(max(result.minY, visible.minY), visible.maxY - result.height)
        } else {
            result.origin.y = visible.maxY - result.height
        }
        return result
    }
}
