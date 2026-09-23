import AppKit

@MainActor
final class AmpXHostCoordinator: AmpXEntheaTheaterHandling {
    private(set) var state: AmpXModuleOrder
    let isEntheaEnabled: Bool
    private let suspendedEntheaWasClosed: Bool?
    private let skin: any AmpXSkin
    private let layoutStore: AmpXLayoutStore
    private let screen: NSScreen
    private let audioPlayer: AudioPlayer
    private let playlistManager: PlaylistManager
    private let playerPresentationState = AmpXPlayerPresentationState()

    private(set) var stackWindowController: AmpXStackWindowController?
    private var moduleViews: [AmpXModuleID: AmpXModuleView] = [:]
    private var detachedWindowControllers: [AmpXModuleID: AmpXDetachedModuleWindowController] = [:]
    private var stackFrame: CGRect
    private var detachedFrames: [AmpXModuleID: CGRect]
    private var playlistViewportHeight: CGFloat
    private var playlistWidth: CGFloat
    private var playlistResizeStart: (width: CGFloat, height: CGFloat)?

    private(set) var dragController = AmpXModuleDragSession()
    private(set) var focusedModuleID: AmpXModuleID = .player
    private(set) lazy var theaterController: AmpXTheaterController = .init(
        hosts: self,
        screenFrame: { [weak self] in self?.screen.frame ?? .zero },
        getPresentation: { NSApp.presentationOptions },
        setPresentation: { NSApp.presentationOptions = $0 }
    )

    private(set) var isStackVisible = false

    var stackWindow: NSWindow? {
        self.stackWindowController?.window
    }

    var stackWindowFrame: CGRect? {
        self.stackWindow?.frame
    }

    init(
        state: AmpXModuleOrder,
        skin: any AmpXSkin,
        layoutStore: AmpXLayoutStore? = nil,
        screen: NSScreen? = nil,
        audioPlayer: AudioPlayer = .shared,
        playlistManager: PlaylistManager = .shared,
        entheaEnabled: Bool = AmpXFeatures.entheaEnabled
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
        self.audioPlayer = audioPlayer
        self.playlistManager = playlistManager
        self.layoutStore = layoutStore ?? AmpXLayoutStore(defaults: .standard, screen: resolvedScreen)

        let saved = self.layoutStore.load(screen: resolvedScreen)
        self.stackFrame = saved.stackFrame
        self.detachedFrames = saved.detachedFrames
        self.playlistViewportHeight = saved.playlistViewportHeight
        self.playlistWidth = saved.playlistWidth

        self.createModuleViews()
        self.dragController.bind(coordinator: self)
        self.restoreDetachedModules()
    }

    func showStack() {
        if self.stackWindowController == nil {
            self.stackWindowController = AmpXStackWindowController(
                coordinator: self,
                skin: self.skin,
                moduleViews: self.visibleStackModuleViews(),
                playlistViewportHeight: self.playlistViewportHeight,
                playlistWidth: self.playlistWidth
            )
            self.dragController.bind(viewport: self.stackWindowController!.stackViewport)
        }

        self.stackWindowController?.updateLayout()
        self.stackWindowController?.applyStackFrame(self.stackFrame)
        self.stackWindowController?.showWindow(nil)
        self.isStackVisible = true
        self.refreshEffectiveVisibility()
    }

    func closeStack() {
        if let window = stackWindowController?.window {
            self.stackFrame = window.frame
        }
        self.stackWindowController?.window?.orderOut(nil)
        self.isStackVisible = false
        self.refreshEffectiveVisibility()
        self.persistLayout()
    }

    func closeModule(_ id: AmpXModuleID) {
        let nextFocus = self.nextVisibleModule(after: id)
        self.dragController.cancelDragIfDragging(moduleID: id)
        if id == .enthea, self.theaterController.isActive {
            self.theaterController.exit()
        }
        if self.state.detached.contains(id) {
            self.tearDownDetachedWindow(for: id)
        }
        if id == .enthea {
            (self.moduleViews[id]?.content as? EntheaModuleContent)?.closeHost()
        }
        self.state.close(id)
        self.focusModule(nextFocus)
        self.stackWindowController?.updateLayout()
        self.refreshEffectiveVisibility()
        self.persistLayout()
    }

    func reopenModule(_ id: AmpXModuleID) {
        guard id != .enthea || self.isEntheaEnabled else { return }
        self.state.reopen(id)
        if self.state.detached.contains(id) {
            self.restoreDetachedModule(id)
        } else if let view = moduleViews[id] {
            self.transferModuleView(view, to: self.stackWindowController?.stackViewport.stackView)
        }
        if id == .enthea {
            (self.moduleViews[id]?.content as? EntheaModuleContent)?.reopenHost()
        }
        self.stackWindowController?.updateLayout()
        self.refreshEffectiveVisibility()
        self.persistLayout()
    }

    func setCollapsed(_ id: AmpXModuleID, _ value: Bool) {
        self.dragController.cancelDragIfDragging(moduleID: id)
        self.state.setCollapsed(id, value)
        self.moduleViews[id]?.setContentCollapsed(value)
        self.detachedWindowControllers[id]?.window?.contentView?.needsLayout = true
        self.stackWindowController?.updateLayout()
        for controller in self.detachedWindowControllers.values {
            self.relayoutDetachedModule(controller)
        }
        self.refreshEffectiveVisibility()
        self.persistLayout()
    }

    func detach(_ id: AmpXModuleID, at screenPoint: CGPoint, inheritedWidth: CGFloat) {
        guard id != .player, !self.state.detached.contains(id) else { return }
        guard let view = moduleViews[id] else { return }

        self.state.detach(id)

        var frame = self.detachedFrames[id]
            ?? self.defaultDetachedFrame(for: id, at: screenPoint, inheritedWidth: self.detachedModuleWidth(for: id))
        frame.size = CGSize(width: self.detachedModuleWidth(for: id), height: self.detachedModuleHeight(for: id, scale: 1))

        let controller = self.detachedWindowControllers[id]
            ?? AmpXDetachedModuleWindowController(
                moduleID: id,
                coordinator: self,
                skin: self.skin,
                inheritedWidth: inheritedWidth,
                frame: frame
            )

        self.detachedWindowControllers[id] = controller
        self.detachedFrames[id] = frame

        self.transferModuleView(view, to: controller)
        controller.applyFrame(frame)
        controller.showWindow(nil)

        self.stackWindowController?.updateLayout()
        self.refreshEffectiveVisibility()
        self.persistLayout()
    }

    func redock(_ id: AmpXModuleID, at visibleDropIndex: Int) {
        guard let view = moduleViews[id] else { return }

        let fullIndex = AmpXModuleDragController.fullOrderIndex(
            forVisibleDropIndex: visibleDropIndex,
            excluding: id,
            in: self.state
        )

        if let detachedController = detachedWindowControllers[id] {
            _ = detachedController.detachModuleView()
            detachedController.window?.orderOut(nil)
            self.detachedWindowControllers.removeValue(forKey: id)
        }

        self.state.redock(id, at: fullIndex)
        self.transferModuleView(view, to: self.stackWindowController?.stackViewport.stackView)

        if !self.isStackVisible {
            self.showStack()
        } else {
            self.stackWindowController?.updateLayout()
        }
        self.refreshEffectiveVisibility()
        self.persistLayout()
    }

    func menuRedock(_ id: AmpXModuleID, at visibleDropIndex: Int) {
        if !self.isStackVisible {
            self.showStack()
        }
        self.redock(id, at: visibleDropIndex)
    }

    func reorder(_ id: AmpXModuleID, toVisibleDropIndex visibleDropIndex: Int) {
        let fullIndex = AmpXModuleDragController.fullOrderIndex(
            forVisibleDropIndex: visibleDropIndex,
            excluding: id,
            in: self.state
        )
        self.state.move(id, to: fullIndex)
        self.stackWindowController?.updateLayout()
        self.persistLayout()
    }

    func updateDetachedFrame(_ id: AmpXModuleID, frame: CGRect) {
        guard !self.theaterController.isActive || id != .enthea else { return }
        guard AmpXLayoutStore.isValidFrame(frame) else { return }
        var normalized = frame
        normalized.size.width = self.detachedModuleWidth(for: id)
        normalized.size.height = self.detachedModuleHeight(for: id, scale: 1)
        let clamped = AmpXLayoutStore.clampedToVisibleFrame(normalized, screen: self.screen)
        self.detachedFrames[id] = clamped
        self.detachedWindowControllers[id]?.applyFrame(clamped)
        self.persistLayout()
    }

    func handleDetachedResize(_ id: AmpXModuleID, frame: CGRect) {
        if id == .playlist, !self.state.collapsed.contains(id) {
            self.playlistViewportHeight = max(
                AmpXMetrics.minimumPlaylistViewportHeight,
                frame.height - AmpXMetrics.headerHeight - AmpXMetrics.playlistNonRowChrome
            )
            self.playlistWidth = max(AmpXMetrics.minimumPlaylistWidth, frame.width)
            self.stackWindowController?.setPreferredPlaylistViewportHeight(self.playlistViewportHeight)
            self.stackWindowController?.setPreferredPlaylistWidth(self.playlistWidth)
            if let controller = detachedWindowControllers[id] {
                self.relayoutDetachedModule(controller)
            }
        }
        self.updateDetachedFrame(id, frame: frame)
    }

    func detachedWindowFrame(for id: AmpXModuleID) -> CGRect? {
        self.detachedWindowControllers[id]?.window?.frame ?? self.detachedFrames[id]
    }

    func moduleView(for id: AmpXModuleID) -> AmpXModuleView? {
        self.moduleViews[id]
    }

    func makeDropGeometry(excluding draggedID: AmpXModuleID) -> AmpXDropGeometry {
        guard self.stackWindowController != nil else {
            return AmpXDropGeometry(bounds: .zero, orderedFrames: [])
        }

        let width = max(AmpXMetrics.compositionWidth, self.playlistWidth)
        let layout = AmpXLayout.calculate(
            state: self.state,
            width: width,
            playlistViewportHeight: self.playlistViewportHeight,
            availableHeight: AmpXStackWindowController.availableHeight(for: self.stackWindow),
            playlistWidth: self.playlistWidth
        )

        let orderedFrames = self.state.order.compactMap { moduleID -> (AmpXModuleID, CGRect)? in
            guard moduleID != .enthea, moduleID != draggedID,
                  !self.state.closed.contains(moduleID),
                  !self.state.detached.contains(moduleID),
                  let frame = layout.frames[moduleID]
            else { return nil }
            return (moduleID, frame)
        }

        return AmpXDropGeometry(
            bounds: CGRect(x: 0, y: 0, width: width, height: layout.contentHeight),
            orderedFrames: orderedFrames
        )
    }

    func handleStackFrameChanged(_ frame: CGRect) {
        guard AmpXLayoutStore.isValidFrame(frame) else { return }
        self.stackFrame = AmpXLayoutStore.clampedToVisibleFrame(frame, screen: self.screen)
        self.persistLayout()
    }

    /// Synchronously captures live stack/detached frames so a quit during the move debounce cannot lose layout.
    func flushLayoutPersistence() {
        self.stackWindowController?.flushPendingFramePersistence()
        for controller in self.detachedWindowControllers.values {
            controller.flushPendingFramePersistence()
        }
    }

    func handlePlayerHeaderClose() {
        self.closeStack()
    }

    func handleModuleHeaderClose(_ id: AmpXModuleID) {
        self.closeModule(id)
    }

    func handleModuleHeaderCollapse(_ id: AmpXModuleID) {
        let collapsed = self.state.collapsed.contains(id)
        self.setCollapsed(id, !collapsed)
    }

    func handlePlayerHeaderMinimize() {
        self.stackWindowController?.window?.miniaturize(nil)
    }

    func adjustPlaylistViewport(byHeightDelta delta: CGFloat, width: CGFloat) {
        let scale: CGFloat = 1
        let adjusted = AmpXLayout.adjustedPlaylistViewportHeight(
            preferred: self.playlistViewportHeight,
            heightDelta: delta,
            scale: scale
        )
        // A preference taller than the screen allows would only be shrunk back; keep the height that fits.
        self.playlistViewportHeight = AmpXLayout.calculate(
            state: self.state,
            width: width,
            playlistViewportHeight: adjusted,
            availableHeight: AmpXStackWindowController.availableHeight(for: self.stackWindow)
        ).playlistViewportHeight
        self.stackWindowController?.setPreferredPlaylistViewportHeight(self.playlistViewportHeight)
        self.stackWindowController?.updateLayout()
        self.persistLayout()
    }

    /// Playlist resize-handle drags, in docked and detached hosts; saves once when the drag ends.
    func handlePlaylistResize(_ phase: PlaylistResizeHandleView.Phase) {
        switch phase {
        case .began:
            self.playlistResizeStart = (self.playlistWidth, self.playlistViewportHeight)
        case let .changed(delta):
            guard let start = playlistResizeStart else { return }
            self.applyPlaylistSize(width: start.width + delta.width, viewportHeight: start.height + delta.height)
        case .ended:
            guard self.playlistResizeStart != nil else { return }
            self.playlistResizeStart = nil
            if self.state.detached.contains(.playlist),
               let window = detachedWindowControllers[.playlist]?.window
            {
                self.updateDetachedFrame(.playlist, frame: window.frame)
            } else {
                self.persistLayout()
            }
        }
    }

    /// Sets the preferred Playlist width (spec Revision 9) and saves it.
    func setPlaylistWidth(_ width: CGFloat) {
        self.applyPlaylistSize(width: width, viewportHeight: self.playlistViewportHeight)
        self.persistLayout()
    }

    /// Horizontal live resize of the stack host: the Playlist absorbs the width left by the visualizer column.
    func setPlaylistWidth(fromHostWidth hostWidth: CGFloat) {
        self.resizePlaylist(toHostWidth: hostWidth, heightDelta: 0)
    }

    /// Live resize of the stack host. Both axes are applied in one pass so a diagonal drag does not
    /// leave one of them to be snapped back by the next layout.
    func resizePlaylist(toHostWidth hostWidth: CGFloat, heightDelta: CGFloat) {
        let hasDockedVisualizer = self.state.order.contains(.enthea)
            && !self.state.closed.contains(.enthea)
            && !self.state.detached.contains(.enthea)
        let visualizerColumn = hasDockedVisualizer ? AmpXMetrics.compositionWidth + AmpXMetrics.moduleGap : 0
        self.applyPlaylistSize(
            width: hostWidth - visualizerColumn,
            viewportHeight: AmpXLayout.adjustedPlaylistViewportHeight(
                preferred: self.playlistViewportHeight,
                heightDelta: heightDelta,
                scale: 1
            )
        )
    }

    private func applyPlaylistSize(width: CGFloat, viewportHeight: CGFloat) {
        self.playlistWidth = max(AmpXMetrics.minimumPlaylistWidth, width)
        self.stackWindowController?.setPreferredPlaylistWidth(self.playlistWidth)
        let height = max(AmpXMetrics.minimumPlaylistViewportHeight, viewportHeight)
        if self.state.detached.contains(.playlist) {
            self.playlistViewportHeight = height
            self.stackWindowController?.setPreferredPlaylistViewportHeight(height)
            if let controller = detachedWindowControllers[.playlist] {
                self.relayoutDetachedModule(controller)
            }
        } else {
            // A preference taller than the screen allows would only be shrunk back; keep the height that fits.
            self.playlistViewportHeight = AmpXLayout.calculate(
                state: self.state,
                width: AmpXMetrics.compositionWidth,
                playlistViewportHeight: height,
                availableHeight: AmpXStackWindowController.availableHeight(for: self.stackWindow),
                playlistWidth: self.playlistWidth
            ).playlistViewportHeight
            self.stackWindowController?.setPreferredPlaylistViewportHeight(self.playlistViewportHeight)
            self.stackWindowController?.updateLayout()
        }
    }

    func performModuleCommand(_ command: AmpXModuleCommand) {
        switch command {
        case .moveUp:
            self.moveFocusedModule(by: -1)
        case .moveDown:
            self.moveFocusedModule(by: 1)
        case .toggleDetach:
            self.toggleDetachFocusedModule()
        case .toggleCollapse:
            self.toggleCollapseFocusedModule()
        }
    }

    func performPlayerCommand(_ command: AmpXPlayerCommand) {
        switch command {
        case .toggleTimeMode:
            self.playerPresentationState.toggleTimeMode()
        }
    }

    func noteFocusedModule(_ id: AmpXModuleID) {
        self.focusedModuleID = id
    }

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

    private func moveFocusedModule(by offset: Int) {
        guard self.focusedModuleID != .player else { return }

        // Detached modules are absent from `visibleModuleOrder()`; re-dock them into the stack.
        if self.state.detached.contains(self.focusedModuleID) {
            let visible = self.visibleModuleOrder()
            let dropIndex: Int = if offset < 0 {
                visible.first == .player ? min(1, visible.count) : 0
            } else {
                visible.count
            }
            self.menuRedock(self.focusedModuleID, at: dropIndex)
            return
        }

        guard let currentIndex = self.visibleModuleOrder().firstIndex(of: self.focusedModuleID) else { return }
        let targetIndex = currentIndex + offset
        guard targetIndex >= 0, targetIndex < self.visibleModuleOrder().count else { return }
        let targetID = self.visibleModuleOrder()[targetIndex]
        guard targetID != .player else { return }
        self.reorder(self.focusedModuleID, toVisibleDropIndex: targetIndex)
    }

    private func toggleDetachFocusedModule() {
        guard self.focusedModuleID != .player else { return }
        if self.state.detached.contains(self.focusedModuleID) {
            self.menuRedock(self.focusedModuleID, at: self.visibleModuleOrder().count)
        } else if let moduleView = moduleViews[focusedModuleID], let stackWindow {
            let windowPoint = moduleView.convert(
                NSPoint(x: moduleView.bounds.midX, y: moduleView.bounds.maxY),
                to: nil
            )
            let screenPoint = stackWindow.convertPoint(toScreen: windowPoint)
            self.detach(
                self.focusedModuleID,
                at: CGPoint(x: screenPoint.x, y: screenPoint.y),
                inheritedWidth: AmpXMetrics.compositionWidth
            )
        }
    }

    private func toggleCollapseFocusedModule() {
        let collapsed = self.state.collapsed.contains(self.focusedModuleID)
        self.setCollapsed(self.focusedModuleID, !collapsed)
    }

    private func focusModule(_ id: AmpXModuleID) {
        self.focusedModuleID = id
        guard let view = moduleViews[id] else { return }
        self.stackWindow?.makeFirstResponder(view.preferredFocusView)
        self.detachedWindowControllers[id]?.window?.makeFirstResponder(view.preferredFocusView)
    }

    private func nextVisibleModule(after id: AmpXModuleID) -> AmpXModuleID {
        let visible = self.visibleModuleOrder()
        guard let index = visible.firstIndex(of: id) else { return .player }
        if index + 1 < visible.count {
            return visible[index + 1]
        }
        return visible.first ?? .player
    }

    private func visibleModuleOrder() -> [AmpXModuleID] {
        self.state.order.filter { moduleID in
            !self.state.closed.contains(moduleID) && !self.state.detached.contains(moduleID)
        }
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
        default:
            AmpXModuleContent.make(moduleID: moduleID, skin: self.skin)
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
            guard let self else { return }
            if moduleID == .player {
                self.handlePlayerHeaderClose()
            } else {
                self.handleModuleHeaderClose(moduleID)
            }
        }

        view.header.onMinimize = { [weak self] in
            guard moduleID == .player else { return }
            self?.handlePlayerHeaderMinimize()
        }

        view.header.onGripMouseDown = { [weak self] event in
            self?.dragController.beginGripDrag(moduleID: moduleID, event: event)
        }

        view.header.onGripMouseDragged = { [weak self] event in
            self?.dragController.updateDrag(event: event)
        }

        view.header.onGripMouseUp = { [weak self] event in
            self?.dragController.endDrag(event: event)
        }

        view.header.onDetach = { [weak self] in
            guard let self else { return }
            self.noteFocusedModule(moduleID)
            self.toggleDetachFocusedModule()
        }
        view.compactContent?.onExpand = view.header.onCollapse
        view.compactContent?.onClose = view.header.onClose
        view.compactContent?.onMinimize = view.header.onMinimize
        view.compactContent?.onGripMouseDown = view.header.onGripMouseDown
        view.compactContent?.onGripMouseDragged = view.header.onGripMouseDragged
        view.compactContent?.onGripMouseUp = view.header.onGripMouseUp
    }

    private func restoreDetachedModules() {
        for moduleID in self.state.detached where !self.state.closed.contains(moduleID) {
            self.restoreDetachedModule(moduleID)
        }
    }

    private func restoreDetachedModule(_ moduleID: AmpXModuleID) {
        guard moduleID != .player, let view = moduleViews[moduleID] else { return }
        if let existing = detachedWindowControllers[moduleID] {
            existing.showWindow(nil)
            return
        }
        var frame = self.detachedFrames[moduleID]
            ?? self.defaultDetachedFrame(
                for: moduleID,
                at: CGPoint(x: self.screen.visibleFrame.midX, y: self.screen.visibleFrame.midY),
                inheritedWidth: self.detachedModuleWidth(for: moduleID)
            )
        frame.size = CGSize(
            width: self.detachedModuleWidth(for: moduleID),
            height: self.detachedModuleHeight(for: moduleID, scale: 1)
        )
        let controller = AmpXDetachedModuleWindowController(
            moduleID: moduleID, coordinator: self, skin: skin,
            inheritedWidth: frame.width, frame: frame
        )
        self.detachedWindowControllers[moduleID] = controller
        self.transferModuleView(view, to: controller)
        controller.showWindow(nil)
    }

    private func defaultDetachedFrame(
        for id: AmpXModuleID,
        at screenPoint: CGPoint,
        inheritedWidth _: CGFloat
    ) -> CGRect {
        let scale: CGFloat = 1
        let height = self.detachedModuleHeight(for: id, scale: scale)
        let width = self.detachedModuleWidth(for: id)
        return AmpXLayoutStore.clampedToVisibleFrame(
            CGRect(
                x: screenPoint.x - width / 2,
                y: screenPoint.y + AmpXMetrics.headerHeight / 2 - height,
                width: width,
                height: height
            ),
            screen: self.screen
        )
    }

    /// Only the Playlist has a variable detached width (spec Revision 9).
    private func detachedModuleWidth(for id: AmpXModuleID) -> CGFloat {
        AmpXLayout.moduleWidth(id, playlistWidth: self.playlistWidth)
    }

    private func detachedModuleHeight(for id: AmpXModuleID, scale: CGFloat) -> CGFloat {
        var moduleState = self.state
        moduleState.detached.remove(id)
        let layout = AmpXLayout.calculate(
            state: moduleState,
            width: AmpXMetrics.compositionWidth * scale,
            playlistViewportHeight: self.playlistViewportHeight,
            availableHeight: 10000,
            playlistWidth: self.playlistWidth
        )
        return layout.frames[id]?.height ?? AmpXMetrics.headerHeight * scale
    }

    private func visibleStackModuleViews() -> [AmpXModuleID: AmpXModuleView] {
        self.moduleViews.filter { moduleID, _ in
            !self.state.detached.contains(moduleID) && !self.state.closed.contains(moduleID)
        }
    }

    private func transferModuleView(_ view: AmpXModuleView, to stackView: AmpXModuleStackView?) {
        view.removeFromSuperview()
        view.isHidden = false
        stackView?.addModuleView(view)
    }

    private func transferModuleView(_ view: AmpXModuleView, to controller: AmpXDetachedModuleWindowController) {
        let width = controller.window?.frame.width ?? AmpXMetrics.compositionWidth
        var moduleState = self.state
        moduleState.detached.remove(view.moduleID)
        let layout = AmpXLayout.calculate(
            state: moduleState,
            width: width,
            playlistViewportHeight: self.playlistViewportHeight,
            availableHeight: 10000,
            playlistWidth: self.playlistWidth
        )
        controller.attachModuleView(view, layout: layout)
    }

    private func relayoutDetachedModule(_ controller: AmpXDetachedModuleWindowController) {
        guard let view = controller.detachModuleView() else { return }
        self.transferModuleView(view, to: controller)
    }

    private func tearDownDetachedWindow(for id: AmpXModuleID) {
        if let window = detachedWindowControllers[id]?.window {
            self.detachedFrames[id] = window.frame
            window.orderOut(nil)
        }
        self.detachedWindowControllers.removeValue(forKey: id)
        // Retain the detached placement so reopening restores the same host position.
    }

    private func persistLayout() {
        var persistedState = self.state
        // Runtime availability must not erase the placement/open state needed when ENTHEA returns.
        if let wasClosed = self.suspendedEntheaWasClosed {
            if wasClosed {
                persistedState.closed.insert(.enthea)
            } else {
                persistedState.closed.remove(.enthea)
            }
        }
        let layout = AmpXSavedLayout(
            state: persistedState,
            stackFrame: stackFrame,
            detachedFrames: detachedFrames,
            playlistViewportHeight: playlistViewportHeight,
            playlistWidth: playlistWidth
        )
        self.layoutStore.save(layout)
    }

    func refreshEffectiveVisibility() {
        for moduleID in AmpXModuleID.allCases {
            guard let moduleView = moduleViews[moduleID] else { continue }
            let inputs = self.visibilityInputs(for: moduleID)
            moduleView.applyPresentationVisibility(inputs.presentationVisibility(hasCompactPresentation: moduleView.compactContent != nil))
        }
        if let playerContent = moduleViews[.player]?.content as? PlayerModuleContent {
            playerContent.updateModuleToggleStates(
                eqOpen: !self.state.closed.contains(.equalizer),
                plOpen: !self.state.closed.contains(.playlist)
            )
        }
    }

    private func visibilityInputs(for moduleID: AmpXModuleID) -> AmpXVisibilityInputs {
        // Theater wins over detached: enter() orders the detached window out but leaves
        // `state.detached` set while the theater window is active.
        if moduleID == .enthea, self.theaterController.isActive {
            return AmpXEffectiveVisibility.theaterInputs(
                collapsed: self.state.collapsed.contains(moduleID),
                closed: self.state.closed.contains(moduleID),
                window: self.theaterController.window
            )
        }

        if self.state.detached.contains(moduleID) {
            return AmpXEffectiveVisibility.detachedInputs(
                collapsed: self.state.collapsed.contains(moduleID),
                closed: self.state.closed.contains(moduleID),
                window: self.detachedWindowControllers[moduleID]?.window
            )
        }

        let moduleFrame = self.moduleFrameInStackContent(for: moduleID)
        let visibleContentRect = self.stackWindowController?.stackViewport.visibleContentRect ?? .zero
        let stackWindowVisible = self.isStackVisible && (self.stackWindow?.isVisible ?? false)

        var inputs = AmpXEffectiveVisibility.stackInputs(
            collapsed: self.state.collapsed.contains(moduleID),
            closed: self.state.closed.contains(moduleID),
            window: self.stackWindow,
            moduleFrame: moduleFrame,
            visibleContentRect: visibleContentRect
        )
        if !stackWindowVisible {
            inputs.windowVisible = false
        }
        return inputs
    }

    private func refreshEntheaPresentation() {
        (self.moduleViews[.enthea]?.content as? EntheaModuleContent)?.refreshTheaterPresentation()
    }

    func captureTheaterSnapshot(for moduleID: AmpXModuleID) -> AmpXTheaterSnapshot {
        let view = self.moduleViews[moduleID]
        let originalHostID = self.state.detached.contains(moduleID) ? moduleID : nil
        let position = self.state.order.firstIndex(of: moduleID) ?? 0
        let frame: CGRect = if self.state.detached.contains(moduleID) {
            self.detachedWindowFrame(for: moduleID) ?? view?.frame ?? .zero
        } else {
            view?.frame ?? .zero
        }
        let scale = self.moduleScale(for: moduleID)
        return AmpXTheaterSnapshot(
            originalHostID: originalHostID,
            modulePosition: position,
            frame: frame,
            scale: scale,
            presentationOptions: []
        )
    }

    func extractModuleViewForTheater(_ moduleID: AmpXModuleID) {
        guard let view = moduleViews[moduleID] else { return }
        view.removeFromSuperview()
        if self.state.detached.contains(moduleID) {
            self.detachedWindowControllers[moduleID]?.window?.orderOut(nil)
        }
        self.stackWindowController?.updateLayout()
    }

    func reinstallModuleViewFromTheater(_ moduleID: AmpXModuleID, snapshot: AmpXTheaterSnapshot) {
        guard let view = moduleViews[moduleID] else { return }

        if snapshot.originalHostID != nil {
            view.exitTheaterPresentation(restoreFrame: .zero)
        } else {
            view.exitTheaterPresentation(restoreFrame: snapshot.frame)
        }

        if snapshot.originalHostID != nil {
            guard let controller = detachedWindowControllers[moduleID] else { return }
            let restoredFrame = AmpXLayoutStore.clampedToVisibleFrame(snapshot.frame, screen: self.screen)
            self.transferModuleView(view, to: controller)
            controller.applyFrame(restoredFrame)
            controller.showWindow(nil)
        } else {
            self.transferModuleView(view, to: self.stackWindowController?.stackViewport.stackView)
            self.stackWindowController?.updateLayout()
        }

        self.refreshEntheaPresentation()
        self.refreshEffectiveVisibility()
    }

    func moduleScale(for moduleID: AmpXModuleID) -> CGFloat {
        // The Playlist stretches instead of scaling, at any width.
        if AmpXModuleView.stretchesHorizontally(moduleID) {
            return 1
        }
        if self.state.detached.contains(moduleID) {
            let width = self.detachedWindowControllers[moduleID]?.window?.frame.width ?? AmpXMetrics.compositionWidth
            return AmpXLayout.scale(width: width)
        }
        let width = AmpXMetrics.compositionWidth
        return AmpXLayout.scale(width: width)
    }

    private func moduleFrameInStackContent(for moduleID: AmpXModuleID) -> CGRect {
        guard let moduleView = moduleViews[moduleID],
              let stackView = stackWindowController?.stackViewport.stackView,
              moduleView.superview === stackView
        else { return .zero }
        return moduleView.frame
    }
}
