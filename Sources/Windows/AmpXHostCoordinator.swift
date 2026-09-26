import AppKit

/// Hosts every module in its own window and applies Winamp 2.x docking rules to them
/// (spec `2026-09-26-winamp-docking-design.md`). Docking is derived from window frames through
/// `AmpXSnapGeometry`; the frames themselves are the only persisted geometry.
@MainActor
final class AmpXHostCoordinator: AmpXEntheaTheaterHandling {
    private(set) var state: AmpXModuleState
    let isEntheaEnabled: Bool
    private let suspendedEntheaWasClosed: Bool?
    private let skin: any AmpXSkin
    private let layoutStore: AmpXLayoutStore
    private let screen: NSScreen
    /// A screen passed in explicitly (tests) pins geometry to it instead of the windows' live screen.
    let pinnedScreen: NSScreen?
    private let audioPlayer: AudioPlayer
    private let playlistManager: PlaylistManager
    private let playerPresentationState = AmpXPlayerPresentationState()
    /// Closing the Player quits AmpX, as in Winamp. Injectable so tests can observe it.
    private let terminate: () -> Void

    private var moduleViews: [AmpXModuleID: AmpXModuleView] = [:]
    private var windowControllers: [AmpXModuleID: AmpXModuleWindowController] = [:]
    /// Last known frame of every module, closed ones included, so reopening restores its spot.
    private var frames: [AmpXModuleID: CGRect]
    private var playlistViewportHeight: CGFloat
    private var playlistWidth: CGFloat
    private var playlistResizeStart: (width: CGFloat, height: CGFloat)?
    /// Open frames when a live window resize began; attached windows reflow from this snapshot.
    private var liveResizeSnapshot: [AmpXModuleID: CGRect]?
    /// Modules hidden because the Player was minimized; restored when it comes back.
    private var hiddenWithPlayer: [AmpXModuleID] = []

    private(set) var focusedModuleID: AmpXModuleID = .player
    /// Title-bar drags; screen-edge magnetism uses the visible frame of the screen under the
    /// cursor (or the pinned screen in tests).
    private(set) lazy var dragSession = AmpXWindowDragSession(coordinator: self) { [weak self] point in
        if let pinned = self?.pinnedScreen {
            return pinned.visibleFrame
        }
        return NSScreen.screens.first { $0.frame.contains(point) }?.visibleFrame
    }

    private(set) lazy var theaterController: AmpXTheaterController = .init(
        hosts: self,
        screenFrame: { [weak self] in self?.screen.frame ?? .zero },
        getPresentation: { NSApp.presentationOptions },
        setPresentation: { NSApp.presentationOptions = $0 }
    )

    init(
        state: AmpXModuleState,
        skin: any AmpXSkin,
        layoutStore: AmpXLayoutStore? = nil,
        screen: NSScreen? = nil,
        audioPlayer: AudioPlayer = .shared,
        playlistManager: PlaylistManager = .shared,
        entheaEnabled: Bool = AmpXFeatures.entheaEnabled,
        terminate: @escaping () -> Void = { NSApp.terminate(nil) }
    ) {
        let resolvedScreen = screen ?? NSScreen.main ?? NSScreen.screens.first!
        self.state = state
        self.isEntheaEnabled = entheaEnabled
        self.suspendedEntheaWasClosed = entheaEnabled ? nil : state.closed.contains(.enthea)
        if !entheaEnabled {
            self.state.closed.insert(.enthea)
        }
        self.skin = skin
        self.screen = resolvedScreen
        self.pinnedScreen = screen
        self.audioPlayer = audioPlayer
        self.playlistManager = playlistManager
        self.terminate = terminate
        self.layoutStore = layoutStore ?? AmpXLayoutStore(defaults: .standard, screen: resolvedScreen)

        let saved = self.layoutStore.load(screen: resolvedScreen)
        self.frames = saved.frames
        self.playlistViewportHeight = saved.playlistViewportHeight
        self.playlistWidth = saved.playlistWidth

        self.createModuleViews()
    }

    // MARK: - Windows

    /// Shows every open module window at its saved frame (launch and Dock reopen).
    func showAll() {
        for id in AmpXModuleID.allCases where self.isOpen(id) {
            self.showWindow(for: id)
        }
        self.windowControllers[.player]?.window?.makeKey()
        self.refreshEffectiveVisibility()
    }

    func window(for id: AmpXModuleID) -> NSWindow? {
        self.windowControllers[id]?.window
    }

    func frame(for id: AmpXModuleID) -> CGRect? {
        self.window(for: id)?.frame ?? self.frames[id]
    }

    func moduleView(for id: AmpXModuleID) -> AmpXModuleView? {
        self.moduleViews[id]
    }

    /// Frames of the windows taking part in docking: visible, not minimized, not in theater.
    func openFrames() -> [AmpXModuleID: CGRect] {
        var result: [AmpXModuleID: CGRect] = [:]
        for (id, controller) in self.windowControllers {
            guard let window = controller.window, window.isVisible, !window.isMiniaturized else { continue }
            if id == .enthea, self.isInTheater {
                continue
            }
            result[id] = window.frame
        }
        return result
    }

    /// Moves windows to `newFrames` without animation and saves the arrangement.
    func applyFrames(_ newFrames: [AmpXModuleID: CGRect]) {
        for (id, frame) in newFrames {
            self.frames[id] = frame
            self.windowControllers[id]?.applyFrame(frame)
        }
        self.persistLayout()
    }

    // MARK: - Modules

    /// Closing the Player quits AmpX (Winamp). Other modules hide and leave their gap.
    func closeModule(_ id: AmpXModuleID) {
        guard id != .player else {
            self.flushLayoutPersistence()
            self.terminate()
            return
        }
        let nextFocus = self.nextOpenModule(after: id)
        self.dragSession.cancel()
        if id == .enthea, self.theaterController.isActive {
            self.theaterController.exit()
        }
        if let window = self.window(for: id) {
            self.frames[id] = window.frame
            window.orderOut(nil)
        }
        if id == .enthea {
            (self.moduleViews[id]?.content as? EntheaModuleContent)?.closeHost()
        }
        self.state.close(id)
        self.focusModule(nextFocus)
        self.refreshEffectiveVisibility()
        self.persistLayout()
    }

    /// Shows a closed module at its last frame; no other window moves.
    func reopenModule(_ id: AmpXModuleID) {
        guard id != .enthea || self.isEntheaEnabled else { return }
        self.state.reopen(id)
        self.showWindow(for: id)
        if id == .enthea {
            (self.moduleViews[id]?.content as? EntheaModuleContent)?.reopenHost()
        }
        self.refreshEffectiveVisibility()
        self.persistLayout()
    }

    /// Windowshade: the window keeps its top-left corner; windows attached below or to the right
    /// follow its edges.
    func setCollapsed(_ id: AmpXModuleID, _ value: Bool) {
        self.dragSession.cancel()
        self.state.setCollapsed(id, value)
        self.moduleViews[id]?.setContentCollapsed(value)
        self.resizeKeepingAttachments([id])
        self.refreshEffectiveVisibility()
        self.persistLayout()
    }

    func noteFocusedModule(_ id: AmpXModuleID) {
        self.focusedModuleID = id
    }

    func performModuleCommand(_ command: AmpXModuleCommand) {
        switch command {
        case .toggleCollapse:
            self.setCollapsed(self.focusedModuleID, !self.state.collapsed.contains(self.focusedModuleID))
        }
    }

    func performPlayerCommand(_ command: AmpXPlayerCommand) {
        switch command {
        case .toggleTimeMode:
            self.playerPresentationState.toggleTimeMode()
        }
    }

    /// ⌘W: closes the key module window (the Player's quits). The theater window exits theater;
    /// any other key window just closes, so ⌘W there never falls through to quitting.
    func closeKeyModule() {
        guard let keyWindow = NSApp.keyWindow else { return }
        if let id = AmpXModuleID.allCases.first(where: { self.window(for: $0) === keyWindow }) {
            self.closeModule(id)
        } else if keyWindow === self.theaterController.window {
            self.theaterController.exit()
        } else {
            keyWindow.performClose(nil)
        }
    }

    // MARK: - Playlist size

    /// Playlist resize-handle drags; saves once when the drag ends.
    func handlePlaylistResize(_ phase: PlaylistResizeHandleView.Phase) {
        switch phase {
        case .began:
            self.playlistResizeStart = (self.playlistWidth, self.playlistViewportHeight)
        case let .changed(delta):
            guard let start = self.playlistResizeStart else { return }
            self.applyPlaylistSize(width: start.width + delta.width, viewportHeight: start.height + delta.height)
        case .ended:
            guard self.playlistResizeStart != nil else { return }
            self.playlistResizeStart = nil
            self.persistLayout()
        }
    }

    /// Sets the preferred Playlist width (spec Revision 9) and saves it.
    func setPlaylistWidth(_ width: CGFloat) {
        self.applyPlaylistSize(width: width, viewportHeight: self.playlistViewportHeight)
        self.persistLayout()
    }

    private func applyPlaylistSize(width: CGFloat, viewportHeight: CGFloat) {
        self.playlistWidth = max(AmpXMetrics.minimumPlaylistWidth, width)
        self.playlistViewportHeight = self.fittingViewportHeight(viewportHeight)
        self.resizeKeepingAttachments([.playlist])
    }

    /// Keeps the Playlist window no taller than the screen's visible frame.
    private func fittingViewportHeight(_ preferred: CGFloat) -> CGFloat {
        let visibleHeight = (self.pinnedScreen ?? self.window(for: .playlist)?.screen ?? self.screen).visibleFrame.height
        let maximum = visibleHeight - AmpXMetrics.headerHeight - AmpXMetrics.playlistNonRowChrome
        return max(AmpXMetrics.minimumPlaylistViewportHeight, min(preferred, maximum))
    }

    // MARK: - Theater

    func toggleTheater() {
        guard self.isEntheaEnabled else { return }
        if self.theaterController.isActive {
            self.theaterController.exit()
        } else {
            self.theaterController.enter()
        }
    }

    func exitTheater() {
        guard self.isEntheaEnabled else { return }
        self.theaterController.exit()
    }

    var isInTheater: Bool {
        self.isEntheaEnabled && self.theaterController.isActive
    }

    func captureTheaterSnapshot(for moduleID: AmpXModuleID) -> AmpXTheaterSnapshot {
        AmpXTheaterSnapshot(
            originalHostID: moduleID,
            frame: self.frame(for: moduleID) ?? .zero,
            presentationOptions: []
        )
    }

    func extractModuleViewForTheater(_ moduleID: AmpXModuleID) {
        if let frame = self.window(for: moduleID)?.frame {
            self.frames[moduleID] = frame
        }
        self.moduleViews[moduleID]?.removeFromSuperview()
        self.window(for: moduleID)?.orderOut(nil)
    }

    func reinstallModuleViewFromTheater(_ moduleID: AmpXModuleID, snapshot: AmpXTheaterSnapshot) {
        guard let view = self.moduleViews[moduleID] else { return }
        view.exitTheaterPresentation(restoreFrame: .zero)
        self.frames[moduleID] = snapshot.frame
        self.showWindow(for: moduleID)
        (view.content as? EntheaModuleContent)?.refreshTheaterPresentation()
        self.refreshEffectiveVisibility()
    }

    // MARK: - Window events

    func moduleWindowDidMove(_ id: AmpXModuleID, frame: CGRect) {
        guard AmpXLayoutStore.isValidFrame(frame), !(id == .enthea && self.isInTheater) else { return }
        self.frames[id] = frame
        self.persistLayout()
    }

    func moduleWindowWillStartLiveResize(_: AmpXModuleID) {
        self.liveResizeSnapshot = self.openFrames()
    }

    /// Live edge-resize of the Playlist window: size follows the window and attached windows
    /// follow the edge they touch.
    func moduleWindowDidLiveResize(_ id: AmpXModuleID, frame: CGRect) {
        guard id == .playlist, let snapshot = self.liveResizeSnapshot else { return }
        if !self.state.collapsed.contains(.playlist) {
            self.playlistWidth = max(AmpXMetrics.minimumPlaylistWidth, frame.width)
            self.playlistViewportHeight = max(
                AmpXMetrics.minimumPlaylistViewportHeight,
                frame.height - AmpXMetrics.headerHeight - AmpXMetrics.playlistNonRowChrome
            )
        }
        self.windowControllers[id]?.layoutModuleView(size: frame.size, playlistViewportHeight: self.playlistViewportHeight)
        var targets = AmpXSnapGeometry.reflow(before: snapshot, resized: [id: frame])
        targets[id] = nil
        for (other, target) in targets {
            self.windowControllers[other]?.applyFrame(target)
        }
    }

    func moduleWindowDidEndLiveResize(_ id: AmpXModuleID, frame _: CGRect) {
        self.liveResizeSnapshot = nil
        for (other, frame) in self.openFrames() {
            self.frames[other] = frame
        }
        if id == .playlist {
            self.resizeKeepingAttachments([.playlist])
        }
        self.persistLayout()
    }

    /// Minimizing the Player hides the other windows; restoring it brings them back (Winamp).
    func moduleWindowDidMiniaturize(_ id: AmpXModuleID) {
        if id == .player {
            self.hiddenWithPlayer = AmpXModuleID.allCases.filter { other in
                other != .player && self.window(for: other)?.isVisible == true
            }
            for other in self.hiddenWithPlayer {
                self.window(for: other)?.orderOut(nil)
            }
        }
        self.refreshEffectiveVisibility()
    }

    func moduleWindowDidDeminiaturize(_ id: AmpXModuleID) {
        if id == .player {
            for other in self.hiddenWithPlayer where self.isOpen(other) {
                self.window(for: other)?.orderFront(nil)
            }
            self.hiddenWithPlayer = []
        }
        self.refreshEffectiveVisibility()
    }

    /// Synchronously captures live frames so a quit during the move debounce cannot lose layout.
    func flushLayoutPersistence() {
        for controller in self.windowControllers.values {
            controller.flushPendingFramePersistence()
        }
        self.persistLayout()
    }

    // MARK: - Header actions

    func handlePlayerHeaderClose() {
        self.closeModule(.player)
    }

    func handleModuleHeaderClose(_ id: AmpXModuleID) {
        self.closeModule(id)
    }

    func handleModuleHeaderCollapse(_ id: AmpXModuleID) {
        self.setCollapsed(id, !self.state.collapsed.contains(id))
    }

    func handlePlayerHeaderMinimize() {
        self.window(for: .player)?.miniaturize(nil)
    }

    // MARK: - Visibility

    func refreshEffectiveVisibility() {
        for moduleID in AmpXModuleID.allCases {
            guard let moduleView = self.moduleViews[moduleID] else { continue }
            let collapsed = self.state.collapsed.contains(moduleID)
            let closed = self.state.closed.contains(moduleID)
            let inputs = moduleID == .enthea && self.theaterController.isActive
                ? AmpXEffectiveVisibility.theaterInputs(collapsed: collapsed, closed: closed, window: self.theaterController.window)
                : AmpXEffectiveVisibility.windowInputs(collapsed: collapsed, closed: closed, window: self.window(for: moduleID))
            moduleView.applyPresentationVisibility(inputs.presentationVisibility(hasCompactPresentation: moduleView.compactContent != nil))
        }
        if let playerContent = self.moduleViews[.player]?.content as? PlayerModuleContent {
            playerContent.updateModuleToggleStates(
                eqOpen: !self.state.closed.contains(.equalizer),
                plOpen: !self.state.closed.contains(.playlist)
            )
        }
    }

    // MARK: - Private

    private func isOpen(_ id: AmpXModuleID) -> Bool {
        !self.state.closed.contains(id) && (id != .enthea || self.isEntheaEnabled)
    }

    private func windowSize(for id: AmpXModuleID) -> CGSize {
        AmpXLayout.moduleSize(id, state: self.state, playlistViewportHeight: self.playlistViewportHeight, playlistWidth: self.playlistWidth)
    }

    /// Creates the module's window on first use and shows it at its saved frame, sized for the
    /// current state with the top-left corner kept.
    private func showWindow(for id: AmpXModuleID) {
        guard let view = self.moduleViews[id] else { return }
        let size = self.windowSize(for: id)
        let saved = self.frames[id] ?? .zero
        let frame = CGRect(x: saved.minX, y: saved.maxY - size.height, width: size.width, height: size.height)

        let controller = self.windowControllers[id]
            ?? AmpXModuleWindowController(moduleID: id, coordinator: self, skin: self.skin, frame: frame)
        self.windowControllers[id] = controller
        controller.install(view, size: size, playlistViewportHeight: self.playlistViewportHeight)
        controller.applyFrame(frame)
        self.frames[id] = frame
        controller.showWindow(nil)
    }

    /// Resizes `ids` to their current window sizes, keeping each top-left corner, and moves the
    /// windows attached to them so the cluster stays connected (Webamp `withWindowGraphIntegrity`).
    private func resizeKeepingAttachments(_ ids: [AmpXModuleID]) {
        let before = self.openFrames()
        var sizes = before.mapValues(\.size)
        for id in ids {
            let size = self.windowSize(for: id)
            if before[id] != nil {
                sizes[id] = size
            } else if let saved = self.frames[id] {
                // Hidden windows just remember the new size for when they reopen.
                self.frames[id] = CGRect(x: saved.minX, y: saved.maxY - size.height, width: size.width, height: size.height)
            }
            self.windowControllers[id]?.layoutModuleView(size: size, playlistViewportHeight: self.playlistViewportHeight)
        }
        self.applyFrames(AmpXSnapGeometry.reflow(before: before, sizes: sizes))
    }

    private func focusModule(_ id: AmpXModuleID) {
        self.focusedModuleID = id
        guard let view = self.moduleViews[id], let window = self.window(for: id) else { return }
        window.makeKey()
        window.makeFirstResponder(view.preferredFocusView)
    }

    private func nextOpenModule(after id: AmpXModuleID) -> AmpXModuleID {
        let open = AmpXModuleID.allCases.filter { self.isOpen($0) && $0 != id }
        let later = AmpXModuleID.allCases.drop(while: { $0 != id }).dropFirst()
        return later.first(where: open.contains) ?? .player
    }

    private func createModuleViews() {
        for moduleID in AmpXModuleID.allCases where moduleID != .enthea || self.isEntheaEnabled {
            let content = self.makeModuleContent(for: moduleID)
            let compact: AmpXCompactModuleView? = switch moduleID {
            case .player:
                PlayerCompactContent(
                    skin: self.skin, audioPlayer: self.audioPlayer, playlistManager: self.playlistManager,
                    presentationState: self.playerPresentationState, onToggleModule: { [weak self] in self?.toggleModuleVisibility($0) }
                )
            case .equalizer:
                EqualizerCompactContent(skin: self.skin, audioPlayer: self.audioPlayer)
            case .playlist:
                if let playlist = content as? PlaylistModuleContent {
                    PlaylistCompactContent(
                        skin: self.skin,
                        manager: self.playlistManager,
                        audioPlayer: self.audioPlayer,
                        listOptionsMenu: playlist.listOptionsMenu
                    )
                } else {
                    nil
                }
            default:
                nil
            }
            let view = AmpXModuleView(moduleID: moduleID, content: content, skin: skin, compactContent: compact)
            view.setContentCollapsed(self.state.collapsed.contains(moduleID))
            self.wireHeader(for: view)
            self.moduleViews[moduleID] = view
        }
        if !self.state.closed.contains(.enthea) {
            (self.moduleViews[.enthea]?.content as? EntheaModuleContent)?.reopenHost()
        }
    }

    private func makeModuleContent(for moduleID: AmpXModuleID) -> AmpXModuleContent {
        switch moduleID {
        case .player:
            PlayerModuleContent(
                skin: self.skin,
                audioPlayer: self.audioPlayer,
                playlistManager: self.playlistManager,
                onToggleModule: { [weak self] id in
                    self?.toggleModuleVisibility(id)
                },
                presentationState: self.playerPresentationState
            )
        case .equalizer:
            EqualizerModuleContent(skin: self.skin, audioPlayer: self.audioPlayer)
        case .playlist:
            self.makePlaylistContent()
        case .enthea:
            EntheaModuleContent(
                skin: self.skin,
                audioPlayer: self.audioPlayer,
                isTheater: { [weak self] in self?.theaterController.isActive ?? false },
                onToggleTheater: { [weak self] in self?.toggleTheater() }
            )
        }
    }

    private func makePlaylistContent() -> PlaylistModuleContent {
        let content = PlaylistModuleContent(
            skin: self.skin,
            manager: self.playlistManager,
            audioPlayer: self.audioPlayer
        )
        content.onResizeViewport = { [weak self] phase in
            self?.handlePlaylistResize(phase)
        }
        return content
    }

    private func toggleModuleVisibility(_ id: AmpXModuleID) {
        if self.state.closed.contains(id) {
            self.reopenModule(id)
        } else {
            self.closeModule(id)
        }
    }

    private func wireHeader(for view: AmpXModuleView) {
        let moduleID = view.moduleID

        view.header.onCollapse = { [weak self] in
            self?.handleModuleHeaderCollapse(moduleID)
        }
        view.header.onClose = { [weak self] in
            self?.closeModule(moduleID)
        }
        view.header.onMinimize = { [weak self] in
            guard moduleID == .player else { return }
            self?.handlePlayerHeaderMinimize()
        }
        view.header.onTitleDragBegan = { [weak self] point in
            self?.dragSession.begin(moduleID, at: point)
        }
        view.header.onTitleDragChanged = { [weak self] point in
            self?.dragSession.move(to: point)
        }
        view.header.onTitleDragEnded = { [weak self] point in
            self?.dragSession.end(at: point)
        }
        view.compactContent?.onExpand = view.header.onCollapse
        view.compactContent?.onClose = view.header.onClose
        view.compactContent?.onMinimize = view.header.onMinimize
        view.compactContent?.onTitleDragBegan = view.header.onTitleDragBegan
        view.compactContent?.onTitleDragChanged = view.header.onTitleDragChanged
        view.compactContent?.onTitleDragEnded = view.header.onTitleDragEnded
    }

    private func persistLayout() {
        var persistedState = self.state
        // Runtime availability must not erase the open state needed when ENTHEA returns.
        if let wasClosed = self.suspendedEntheaWasClosed {
            if wasClosed {
                persistedState.closed.insert(.enthea)
            } else {
                persistedState.closed.remove(.enthea)
            }
        }
        self.layoutStore.save(AmpXSavedLayout(
            state: persistedState,
            frames: self.frames,
            playlistViewportHeight: self.playlistViewportHeight,
            playlistWidth: self.playlistWidth
        ))
    }
}
