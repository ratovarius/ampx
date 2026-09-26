import AppKit
import SwiftUI

/// Manages separate floating NSWindows for the equalizer, playlist, and visualizer.
///
/// Drag behavior matches [Webamp's
/// `WindowManager`](https://github.com/captbaritone/webamp/blob/master/packages/webamp/js/components/WindowManager.tsx):
/// a custom mouse-drag loop moves all graph-connected windows together when dragging
/// the main player; dragging any other window moves it alone, which is how it is undocked.
@MainActor
final class AmpXPanelWindowManager {
    static let shared = AmpXPanelWindowManager()

    private struct ActiveDrag {
        let lead: NSWindow
        let moving: [NSWindow]
        let startOrigins: [ObjectIdentifier: NSPoint]
        let mouseStart: NSPoint
    }

    private var windows: [AmpXPanelID: NSWindow] = [:]
    private var hostingControllers: [AmpXPanelID: NSHostingController<AnyView>] = [:]
    private weak var mainWindow: NSWindow?
    private var layoutState: AmpXPanelLayoutState?
    private var audioPlayer: AudioPlayer?
    private var playlistManager: PlaylistManager?
    private var uiScale: AmpXUIScale?

    private var moveObservers: [NSObjectProtocol] = []
    private var dragEventMonitor: Any?
    private var activeDrag: ActiveDrag?
    /// Frame before theater enter — origin used with `visualizerSize` on exit.
    private var visualizerPreTheaterFrame: CGRect?
    private var presentationOptionsBeforeTheater: NSApplication.PresentationOptions?

    /// The set of panels the manager can host. Built once; each descriptor reads live layout state
    /// through `self`, so a new panel is added by appending a descriptor here rather than editing
    /// per-kind branches throughout the manager.
    private lazy var registry: [AmpXPanelDescriptor] = self.makeRegistry()

    /// Persisted per-panel offset from the main window. In the geometry-primary docking model the
    /// window positions are the source of truth; this is what survives relaunch.
    private let positionStore = AmpXPanelPositionStore()

    private var panelIDs: [AmpXPanelID] {
        self.registry.map(\.id)
    }

    private func descriptor(for id: AmpXPanelID) -> AmpXPanelDescriptor? {
        self.registry.first { $0.id == id }
    }

    /// Derive the dock parent of every visible panel from current window geometry (the 2D spanning
    /// tree rooted at the main window). Panels absent from the result are floating.
    private func currentDockParents() -> [AmpXPanelID: AmpXDockNode] {
        let frames = self.layoutFrames()
        guard frames[.main] != nil else { return [:] }
        return AmpXDockGraph.parents(frames: frames, order: self.panelIDs)
    }

    private func makeRegistry() -> [AmpXPanelDescriptor] {
        [
            AmpXPanelDescriptor(
                id: .equalizer,
                isVisible: { [weak self] in self?.layoutState?.isEqualizerDocked ?? false },
                makeRoot: { [weak self] in
                    guard let layoutState = self?.layoutState else { return AnyView(EmptyView()) }
                    return AnyView(EqualizerPanelRoot(layoutState: layoutState))
                },
                sizing: .explicit { [weak self] in
                    guard let layoutState = self?.layoutState else { return .zero }
                    let scale = self?.uiScale?.scale ?? 1
                    let width = ClassicSkinMetrics.scaled(ClassicSkinMetrics.windowWidth, by: scale)
                    let height = ClassicSkinMetrics.scaled(
                        layoutState.equalizerMinimized
                            ? ClassicSkinMetrics.titleBarHeight
                            : ClassicSkinMetrics.windowHeight,
                        by: scale
                    )
                    return CGSize(width: width, height: height)
                }
            ),
            AmpXPanelDescriptor(
                id: .playlist,
                isVisible: { [weak self] in self?.layoutState?.showPlaylist ?? false },
                makeRoot: { [weak self] in
                    guard let layoutState = self?.layoutState else { return AnyView(EmptyView()) }
                    return AnyView(PlaylistPanelRoot(layoutState: layoutState))
                },
                sizing: .explicit { [weak self] in
                    guard let layoutState = self?.layoutState else { return .zero }
                    let scale = self?.uiScale?.scale ?? 1
                    let minimizedHeight = ClassicSkinMetrics.scaled(
                        ClassicSkinMetrics.playlistShadeHeight,
                        by: scale
                    )
                    let height = layoutState.playlistMinimized
                        ? minimizedHeight
                        : layoutState.playlistSize.height.rounded(.toNearestOrAwayFromZero)
                    let width = max(
                        layoutState.playlistSize.width,
                        ClassicSkinMetrics.scaled(ClassicSkinMetrics.windowWidth, by: scale)
                    ).rounded(.toNearestOrAwayFromZero)
                    return CGSize(width: width, height: height)
                }
            ),
            AmpXPanelDescriptor(
                id: .visualizer,
                isVisible: { [weak self] in self?.layoutState?.showVisualizer ?? false },
                makeRoot: { [weak self] in
                    guard let layoutState = self?.layoutState else { return AnyView(EmptyView()) }
                    return AnyView(VisualizerPanelRoot(layoutState: layoutState))
                },
                sizing: .explicit { [weak self] in
                    guard let layoutState = self?.layoutState else { return .zero }
                    if layoutState.visualizerInTheater {
                        let size = layoutState.visualizerTheaterSize
                        if size.width > 0, size.height > 0 { return size }
                    }
                    let scale = self?.uiScale?.scale ?? 1
                    let minimizedHeight = ClassicSkinMetrics.scaled(
                        ClassicSkinMetrics.playlistShadeHeight,
                        by: scale
                    )
                    let minWidth = ClassicSkinMetrics.scaled(ClassicSkinMetrics.windowWidth, by: scale)
                    let width = max(layoutState.visualizerSize.width, minWidth)
                        .rounded(.toNearestOrAwayFromZero)
                    if layoutState.visualizerMinimized {
                        return CGSize(width: width, height: minimizedHeight)
                    }
                    let height = layoutState.visualizerSize.height.rounded(.toNearestOrAwayFromZero)
                    return CGSize(width: width, height: height)
                }
            ),
        ]
    }

    private init() {}

    func configure(
        mainWindow: NSWindow,
        layoutState: AmpXPanelLayoutState,
        audioPlayer: AudioPlayer,
        playlistManager: PlaylistManager,
        uiScale: AmpXUIScale
    ) {
        self.mainWindow = mainWindow
        self.layoutState = layoutState
        self.audioPlayer = audioPlayer
        self.playlistManager = playlistManager
        self.uiScale = uiScale
        AmpXWindowSnap.syncSnapDistance(withScale: uiScale.scale)

        self.installResizeObserversIfNeeded()
        self.syncPanels()
    }

    /// The SwiftUI `WindowGroup` main player — prefer this over `NSApp.keyWindow` for chrome
    /// that must act on the main window even when a docked panel is key.
    var mainPlayerWindow: NSWindow? {
        self.mainWindow
    }

    func isPanelWindow(_ window: NSWindow) -> Bool {
        self.windows.values.contains(where: { $0 === window })
    }

    func isPlaylistWindow(_ window: NSWindow) -> Bool {
        self.windows[.playlist] === window
    }

    func isEqualizerWindow(_ window: NSWindow) -> Bool {
        self.windows[.equalizer] === window
    }

    func isVisualizerWindow(_ window: NSWindow) -> Bool {
        self.windows[.visualizer] === window
    }

    var isVisualizerInTheater: Bool {
        self.layoutState?.visualizerInTheater ?? false
    }

    /// Double-click on a title bar: shade/unshade panels, but when the main window is already
    /// shaded, ignore the click — AmpX restores via the middle (unshade) title-bar icon only.
    func handleTitleBarDoubleClick(for window: NSWindow) {
        guard let layoutState else { return }
        if window === self.mainWindow, layoutState.isShadeMode {
            return
        }
        self.toggleWindowshade(for: window)
    }

    /// Toggle the classic windowshade ("roll up to the title bar") for the given window.
    ///
    /// Matches AmpX's double-click-title behavior for main, playlist, equalizer, and visualizer.
    func toggleWindowshade(for window: NSWindow) {
        guard let layoutState else { return }
        if self.isPlaylistWindow(window) {
            layoutState.playlistMinimized.toggle()
            // The toggle originates from an AppKit mouseDown, outside SwiftUI's transaction, so
            // ContentView's `.onChange(of: playlistMinimized)` is deferred to a later update cycle
            // — the window keeps its old frame until some other event forces a relayout. Resize
            // now so the windowshade tracks the click, matching the SwiftUI chevron path.
            self.resizePlaylistPanel()
        } else if self.isEqualizerWindow(window) {
            layoutState.equalizerMinimized.toggle()
            self.resizeEqualizerPanel()
        } else if self.isVisualizerWindow(window) {
            layoutState.visualizerMinimized.toggle()
            self.resizeVisualizerPanel()
        } else if window === self.mainWindow {
            layoutState.isShadeMode.toggle()
            self.fitMainWindowToContent()
        }
    }

    func syncPanels() {
        guard self.layoutState != nil else { return }

        for descriptor in self.registry {
            self.setPanelVisible(descriptor.isVisible(), descriptor: descriptor)
        }

        self.syncChildWindowLinks()
    }

    /// Resize the playlist panel to match `layoutState` (size handle or windowshade). The top-left
    /// corner stays put and windows attached below or beside it follow its edges.
    func resizePlaylistPanel() {
        self.resizePanelKeepingAttachments(.playlist)
    }

    /// Resize the equalizer panel after a windowshade toggle.
    func resizeEqualizerPanel() {
        self.resizePanelKeepingAttachments(.equalizer)
    }

    /// Expand the visualizer to the full `screen.frame` (covers the menu-bar / notch band).
    /// Not native `toggleFullScreen` — Classic chrome hides via `visualizerInTheater`.
    func toggleVisualizerTheater() {
        guard let layoutState else { return }
        if layoutState.visualizerInTheater {
            self.exitVisualizerTheater()
        } else {
            self.enterVisualizerTheater()
        }
    }

    func enterVisualizerTheater() {
        guard let layoutState,
              let window = self.windows[.visualizer],
              window.isVisible,
              !layoutState.visualizerInTheater
        else { return }

        if layoutState.visualizerMinimized {
            layoutState.visualizerMinimized = false
        }
        self.visualizerPreTheaterFrame = window.frame
        self.persistPositions()
        let screen = window.screen ?? NSScreen.main
        // Full display bounds — `visibleFrame` would leave the webcam / menu-bar strip.
        let theaterFrame = screen?.frame ?? window.frame
        layoutState.visualizerTheaterSize = theaterFrame.size
        layoutState.visualizerInTheater = true
        self.presentationOptionsBeforeTheater = NSApp.presentationOptions
        NSApp.presentationOptions.insert([.autoHideMenuBar, .autoHideDock])
        // Unlink first so AppKit doesn't drag the visualizer's docked neighbours to full screen;
        // the theater visualizer is left out of the dock graph until it exits.
        self.detachAllChildLinks()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            window.setFrame(theaterFrame, display: true)
        }
        self.syncChildWindowLinks()
        window.makeKeyAndOrderFront(nil)
    }

    func exitVisualizerTheater() {
        guard let layoutState, layoutState.visualizerInTheater else { return }
        let preTheater = self.visualizerPreTheaterFrame
        self.visualizerPreTheaterFrame = nil
        layoutState.visualizerInTheater = false
        layoutState.visualizerTheaterSize = .zero
        if let previous = self.presentationOptionsBeforeTheater {
            NSApp.presentationOptions = previous
        } else {
            NSApp.presentationOptions = []
        }
        self.presentationOptionsBeforeTheater = nil

        guard let window = self.windows[.visualizer], window.isVisible,
              let descriptor = self.descriptor(for: .visualizer)
        else { return }

        let contentSize = self.targetContentSize(for: descriptor)
        let frameSize = window.frameRect(forContentRect: CGRect(origin: .zero, size: contentSize)).size
        let topY = preTheater?.maxY ?? window.frame.maxY
        let originX = preTheater?.minX ?? window.frame.minX
        let frame = CGRect(
            x: originX,
            y: topY - frameSize.height,
            width: frameSize.width,
            height: frameSize.height
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            window.setFrame(frame, display: true)
        }
        self.syncChildWindowLinks()
        self.persistPositions()
    }

    /// Resize the visualizer panel (shade / user size), keeping attached windows attached.
    func resizeVisualizerPanel() {
        guard let layoutState = self.layoutState,
              let window = self.windows[.visualizer], window.isVisible else { return }

        if layoutState.visualizerInTheater {
            let screen = window.screen ?? NSScreen.main
            let theaterFrame = screen?.frame ?? window.frame
            layoutState.visualizerTheaterSize = theaterFrame.size
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                window.setFrame(theaterFrame, display: true)
            }
            return
        }
        self.resizePanelKeepingAttachments(.visualizer)
    }

    /// Shrink/expand the main player window to the classic full or shade height, keeping the top
    /// edge fixed. Windows docked beneath follow its bottom edge (Winamp windowshade behavior).
    func fitMainWindowToContent() {
        self.resizeKeepingAttachments {
            self.applyMainContentSize()
        }
    }

    /// Resize every visible window for a Zoom menu change. Each keeps its top-left corner and the
    /// docked cluster re-flows around the main window so nothing overlaps or leaves a gap.
    func applyUIScale() {
        AmpXWindowSnap.syncSnapDistance(withScale: self.uiScale?.scale ?? 1)
        self.resizeKeepingAttachments {
            self.applyMainContentSize()
            for descriptor in self.registry where self.windows[descriptor.id]?.isVisible == true {
                self.applyContentSize(for: descriptor)
            }
        }
    }

    private func resizePanelKeepingAttachments(_ id: AmpXPanelID) {
        guard self.windows[id]?.isVisible == true, let descriptor = self.descriptor(for: id) else { return }
        self.resizeKeepingAttachments {
            self.applyContentSize(for: descriptor)
        }
    }

    /// Run `resize` (which must keep each window's top-left corner fixed), then move every window
    /// that was attached below or to the right of a resized one so the cluster stays connected —
    /// Webamp's `withWindowGraphIntegrity`. Windows that merely sat nearby are left alone.
    private func resizeKeepingAttachments(_ resize: () -> Void) {
        let before = self.layoutFrames()
        // Unlink so AppKit doesn't also move child windows when a parent's origin changes.
        self.detachAllChildLinks()
        resize()
        let after = self.layoutFrames()
        let targets = AmpXDockGraph.reflow(before: before, sizes: after.mapValues(\.size))
        for (node, frame) in targets where frame != after[node] {
            guard let window = self.window(for: node) else { continue }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                window.setFrame(frame, display: true)
            }
        }
        self.syncChildWindowLinks()
        self.persistPositions()
    }

    /// Frames of the main window and every visible panel taking part in docking (the theater
    /// visualizer covers the screen and is left out).
    private func layoutFrames() -> [AmpXDockNode: CGRect] {
        var frames: [AmpXDockNode: CGRect] = [:]
        if let mainWindow { frames[.main] = mainWindow.frame }
        for id in self.panelIDs {
            guard let window = self.windows[id], window.isVisible else { continue }
            if id == .visualizer, self.layoutState?.visualizerInTheater == true { continue }
            frames[.panel(id)] = window.frame
        }
        return frames
    }

    private func window(for node: AmpXDockNode) -> NSWindow? {
        switch node {
        case .main: self.mainWindow
        case let .panel(id): self.windows[id]
        }
    }

    private func applyMainContentSize() {
        guard let mainWindow, let layoutState else { return }
        let scale = self.uiScale?.scale ?? 1
        let height = ClassicSkinMetrics.scaled(
            layoutState.isShadeMode ? ClassicSkinMetrics.shadeHeight : ClassicSkinMetrics.windowHeight,
            by: scale
        )
        let width = ClassicSkinMetrics.scaled(ClassicSkinMetrics.windowWidth, by: scale)
        let contentSize = NSSize(width: width, height: height)
        let frameSize = mainWindow.frameRect(forContentRect: CGRect(origin: .zero, size: contentSize)).size
        let old = mainWindow.frame
        let frame = CGRect(
            x: old.minX,
            y: old.maxY - frameSize.height,
            width: frameSize.width,
            height: frameSize.height
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            mainWindow.setFrame(frame, display: true)
        }
    }

    /// Begin a title-bar drag, following Webamp's window-manager model: detach all docked child
    /// links so AppKit doesn't auto-move windows we reposition manually, then drag the **moving
    /// set**. The main window brings its whole connected cluster; any other window moves alone,
    /// which is how it is undocked. Dock links are rebuilt from the final geometry on mouse-up.
    func startDrag(leading window: NSWindow, event _: NSEvent) {
        self.endDrag()

        self.detachAllChildLinks()
        let moving = self.movingSet(for: window)
        let origins = Dictionary(uniqueKeysWithValues: moving.map { (ObjectIdentifier($0), $0.frame.origin) })
        self.activeDrag = ActiveDrag(
            lead: window,
            moving: moving,
            startOrigins: origins,
            mouseStart: NSEvent.mouseLocation
        )

        self.dragEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let eventType = event.type
            MainActor.assumeIsolated {
                guard let self else { return }
                switch eventType {
                case .leftMouseDragged:
                    self.handleDragMoved()
                case .leftMouseUp:
                    self.endDrag()
                default:
                    break
                }
            }
            return event
        }
    }

    /// Mirror the geometry-derived dock graph onto AppKit parent/child window links. A docked,
    /// visible panel becomes a child window of the window it abuts toward the main player, so the
    /// WindowServer moves the whole cluster with its parent (atomic, lag-free) and dragging a window
    /// carries its sub-tree. Floating or hidden panels are detached.
    ///
    /// Done in two phases — **detach all changing links, then attach** — so two panels swapping
    /// parent/child roles never transiently form a parent↔child cycle (which makes AppKit recurse
    /// the window graph and crash with SIGSEGV).
    private func syncChildWindowLinks() {
        let parents = self.currentDockParents()
        let desired: [(panel: NSWindow, parent: NSWindow?)] = self.panelIDs.compactMap { id in
            guard let panel = self.windows[id] else { return nil }
            let parent = panel.isVisible ? self.dockParentWindow(for: id, parents: parents) : nil
            return (panel, parent)
        }

        for (panel, parent) in desired where panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
        }
        for (panel, parent) in desired {
            guard let parent, parent !== panel, parent.isVisible, panel.parent !== parent else { continue }
            parent.addChildWindow(panel, ordered: .above)
        }
    }

    private func dockParentWindow(for id: AmpXPanelID, parents: [AmpXPanelID: AmpXDockNode]) -> NSWindow? {
        switch parents[id] {
        case .main: self.mainWindow
        case let .panel(parentID): self.windows[parentID]
        case nil: nil
        }
    }

    /// Detach every managed panel from its parent window, flattening the child-window graph. Done
    /// before a drag so AppKit doesn't auto-move docked panels we are repositioning manually, and
    /// rebuilt from geometry on drop.
    private func detachAllChildLinks() {
        for id in self.panelIDs {
            guard let panel = self.windows[id] else { continue }
            for child in panel.childWindows ?? [] {
                panel.removeChildWindow(child)
            }
            panel.parent?.removeChildWindow(panel)
        }
    }

    // MARK: - Drag

    /// Windows that move together when `lead` is dragged. The main window carries its whole
    /// geometry-connected cluster; any other window moves alone (Winamp / Webamp behavior).
    private func movingSet(for lead: NSWindow) -> [NSWindow] {
        guard lead === self.mainWindow else { return [lead] }
        return AmpXWindowSnap.traceConnected(from: lead, among: self.managedWindowsIncludingMain())
    }

    private func handleDragMoved() {
        guard let drag = self.activeDrag else { return }

        let mouse = NSEvent.mouseLocation
        let proposed = CGSize(
            width: mouse.x - drag.mouseStart.x,
            height: mouse.y - drag.mouseStart.y
        )

        // Webamp group-diff snapping: offset every moving window by the cursor delta, then add one
        // small correction (≤ snapDistance) that snaps the group's edges to the stationary windows.
        // Applying the SAME final delta to all moving windows keeps a dragged cluster rigid and
        // perfectly aligned, and the live correction gives magnetic feedback as you approach an edge.
        let movingBoxes = drag.moving.map { window -> AmpXWindowSnap.Box in
            let start = drag.startOrigins[ObjectIdentifier(window)] ?? window.frame.origin
            let origin = NSPoint(x: start.x + proposed.width, y: start.y + proposed.height)
            return AmpXWindowSnap.Box(frame: CGRect(origin: origin, size: window.frame.size))
        }
        let movingSet = Set(drag.moving.map { ObjectIdentifier($0) })
        let stationaryBoxes = self.managedWindowsIncludingMain()
            .filter { !movingSet.contains(ObjectIdentifier($0)) }
            .map { AmpXWindowSnap.Box(window: $0) }

        var correction = AmpXWindowSnap.snapDelta(moving: movingBoxes, stationary: stationaryBoxes)
        // Screen edges are magnetic too, on any axis not already stuck to a window.
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? drag.lead.screen
        if let bounds = screen?.visibleFrame {
            let within = AmpXWindowSnap.snapWithinDelta(moving: movingBoxes, bounds: bounds)
            if correction.width == 0 { correction.width = within.width }
            if correction.height == 0 { correction.height = within.height }
        }
        let final = CGSize(width: proposed.width + correction.width, height: proposed.height + correction.height)

        for window in drag.moving {
            guard let start = drag.startOrigins[ObjectIdentifier(window)] else { continue }
            window.setFrameOrigin(NSPoint(x: start.x + final.width, y: start.y + final.height))
        }
    }

    private func managedWindowsIncludingMain() -> [NSWindow] {
        var result: [NSWindow] = []
        if let mainWindow { result.append(mainWindow) }
        for id in self.panelIDs where self.windows[id]?.isVisible == true {
            if let window = self.windows[id] { result.append(window) }
        }
        return result
    }

    private func endDrag() {
        if let monitor = self.dragEventMonitor {
            NSEvent.removeMonitor(monitor)
            self.dragEventMonitor = nil
        }
        let wasDragging = self.activeDrag != nil
        self.activeDrag = nil

        // Rebuild the dock links from where the windows landed. No re-alignment: a window released
        // within snap range is already flush (the live snap put it there), and one docked but
        // offset along the shared edge stays where the user left it, as in Winamp.
        if wasDragging {
            self.syncChildWindowLinks()
            self.persistPositions()
        }
    }

    /// Save every visible panel's offset from the main window so the arrangement restores on relaunch.
    private func persistPositions() {
        guard let mainOrigin = self.mainWindow?.frame.origin else { return }
        for id in self.panelIDs where self.windows[id]?.isVisible == true {
            // Theater uses the full screen — don't overwrite the docked offset.
            if id == .visualizer, self.layoutState?.visualizerInTheater == true { continue }
            guard let origin = self.windows[id]?.frame.origin else { continue }
            self.positionStore.store(id, panelOrigin: origin, mainOrigin: mainOrigin)
        }
    }

    // MARK: - Private

    private func installResizeObserversIfNeeded() {
        guard self.moveObservers.isEmpty else { return }

        self.observeWindowNotification(NSWindow.didMiniaturizeNotification) { [weak self] window in
            self?.handleMainMiniaturized(window)
        }
        self.observeWindowNotification(NSWindow.didDeminiaturizeNotification) { [weak self] window in
            self?.handleMainDeminiaturized(window)
        }
    }

    private func observeWindowNotification(
        _ name: NSNotification.Name,
        handler: @escaping @MainActor (NSWindow) -> Void
    ) {
        self.moveObservers.append(
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                guard let window = note.object as? NSWindow else { return }
                MainActor.assumeIsolated {
                    handler(window)
                }
            }
        )
    }

    private func setPanelVisible(_ visible: Bool, descriptor: AmpXPanelDescriptor) {
        if visible {
            self.showPanel(descriptor: descriptor)
        } else {
            self.hidePanel(id: descriptor.id)
        }
    }

    private func showPanel(descriptor: AmpXPanelDescriptor) {
        guard let audioPlayer, let playlistManager, let uiScale else { return }

        let id = descriptor.id
        let window: NSWindow
        let isNew: Bool

        if let existing = self.windows[id], self.hostingControllers[id] != nil {
            window = existing
            isNew = false
            // Keep the live view tree — bindings on `layoutState` / `uiScale` propagate changes.
        } else {
            let decoratedView = AnyView(
                descriptor.makeRoot()
                    .environmentObject(audioPlayer)
                    .environmentObject(audioPlayer.playbackClock)
                    .environmentObject(playlistManager)
                    .environmentObject(uiScale)
                    .environment(\.winampUIScale, uiScale.scale)
            )
            let hosting = NSHostingController(rootView: decoratedView)
            hosting.view.wantsLayer = true
            // The manager owns window sizing (see `applyContentSize` / panel resize helpers).
            // Empty sizing options prevent the hosting controller from fighting our frames.
            // MilkDrop uses `MilkdropMTKHostView` so the MTKView fills the panel without
            // intrinsic-content auto-resize.
            hosting.sizingOptions = []

            window = AmpXPanelWindow(
                contentRect: .zero,
                styleMask: [.borderless, .miniaturizable],
                backing: .buffered,
                defer: true
            )
            window.contentViewController = hosting
            window.isReleasedWhenClosed = false
            AmpXWindowConfigurator.apply(to: window, resizable: false)

            self.windows[id] = window
            self.hostingControllers[id] = hosting
            isNew = true
        }

        let wasVisible = !isNew && window.isVisible
        self.applyContentSize(for: descriptor)
        if !wasVisible {
            // Reappear exactly where it was relative to the main window (Winamp leaves the gap
            // open while hidden and never rearranges the other windows).
            self.placePanelInitially(id)
        }
        window.orderFront(nil)
    }

    /// Position a panel being shown: at its persisted offset from the main window if known,
    /// otherwise via `AmpXPanelPlacement` (visualizer → right of main; others → below cluster).
    private func placePanelInitially(_ id: AmpXPanelID) {
        guard let window = self.windows[id], let mainWindow else { return }
        if let origin = self.positionStore.origin(for: id, mainOrigin: mainWindow.frame.origin) {
            self.setFrameOriginWithoutAnimation(window, origin: origin)
            return
        }

        let stackBelow: CGPoint?
        if let bottom = self.lowestVisibleManagedWindow(excluding: id) {
            stackBelow = bottom.frame.origin
        } else {
            stackBelow = nil
        }
        let origin = AmpXPanelPlacement.initialOrigin(
            panelID: id,
            panelSize: window.frame.size,
            mainFrame: mainWindow.frame,
            stackBelowOrigin: stackBelow
        )
        self.setFrameOriginWithoutAnimation(window, origin: origin)
    }

    private func lowestVisibleManagedWindow(excluding: AmpXPanelID) -> NSWindow? {
        self.managedWindowsIncludingMain()
            .filter { $0 !== self.windows[excluding] }
            .min { $0.frame.minY < $1.frame.minY }
    }

    private func hidePanel(id: AmpXPanelID) {
        guard let window = self.windows[id] else { return }
        if window.isVisible {
            // Remember where it sat so re-showing puts it back in the same spot.
            self.persistPositions()
        }
        for child in window.childWindows ?? [] {
            window.removeChildWindow(child)
        }
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
        if id == .visualizer {
            // Drop theater chrome/flags before tearing down the hosting tree.
            if self.layoutState?.visualizerInTheater == true {
                self.layoutState?.visualizerInTheater = false
                self.layoutState?.visualizerTheaterSize = .zero
                self.visualizerPreTheaterFrame = nil
                if let previous = self.presentationOptionsBeforeTheater {
                    NSApp.presentationOptions = previous
                } else {
                    NSApp.presentationOptions = []
                }
                self.presentationOptionsBeforeTheater = nil
            }
            // Drop the hosting tree so the Enthea WKWebView / Metal body stops while hidden.
            window.contentViewController = nil
            self.hostingControllers[id] = nil
        }
        // Windows docked to it stay put (Winamp leaves the gap); they are simply no longer linked.
        self.syncChildWindowLinks()
    }

    private func applyContentSize(for descriptor: AmpXPanelDescriptor) {
        guard let window = self.windows[descriptor.id] else { return }
        let contentSize = self.targetContentSize(for: descriptor)
        let frameSize = window.frameRect(forContentRect: CGRect(origin: .zero, size: contentSize)).size
        let old = window.frame
        // Keep the top edge fixed — `setContentSize` grows upward from the bottom-left origin and
        // drives docked panels into their parents when Zoom increases.
        let frame = CGRect(
            x: old.minX,
            y: old.maxY - frameSize.height,
            width: frameSize.width,
            height: frameSize.height
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            window.setFrame(frame, display: true)
        }
    }

    /// The content size a panel should have, per its sizing policy.
    private func targetContentSize(for descriptor: AmpXPanelDescriptor) -> NSSize {
        let scale = self.uiScale?.scale ?? 1
        let panelWidth = ClassicSkinMetrics.scaled(ClassicSkinMetrics.windowWidth, by: scale)
        switch descriptor.sizing {
        case .fixedToContent:
            guard let hosting = self.hostingControllers[descriptor.id] else {
                return NSSize(width: panelWidth, height: 50)
            }
            hosting.view.layoutSubtreeIfNeeded()
            let fitting = hosting.sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
            return NSSize(width: panelWidth, height: max(fitting.height.rounded(.toNearestOrAwayFromZero), 50))
        case let .explicit(provider):
            let desired = provider()
            return NSSize(
                width: max(desired.width, panelWidth).rounded(.toNearestOrAwayFromZero),
                height: desired.height.rounded(.toNearestOrAwayFromZero)
            )
        }
    }

    private func setFrameOriginWithoutAnimation(_ window: NSWindow, origin: NSPoint) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            window.setFrameOrigin(origin)
        }
    }

    private func handleMainMiniaturized(_ window: NSWindow) {
        guard window === self.mainWindow else { return }
        // Detach before hiding so AppKit's automatic child-window restore on deminiaturize doesn't
        // race our own `syncPanels`; visibility is re-established explicitly there.
        for id in self.panelIDs {
            guard let panel = self.windows[id] else { continue }
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    private func handleMainDeminiaturized(_ window: NSWindow) {
        guard window === self.mainWindow else { return }
        self.syncPanels()
    }
}

/// Observing root for the detached playlist window.
///
/// The panel runs in its own `NSHostingController`, which does not inherit the main window's
/// observation of `layoutState`. Holding it as an `@ObservedObject` here makes the panel re-render
/// its body when `playlistMinimized` / `playlistSize` change — so a windowshade toggle reflows the
/// SwiftUI content immediately instead of waiting for an unrelated relayout to force it.
///
/// `AmpXUIScale` is re-injected into the environment key on every zoom change so sprite geometry
/// tracks the menu Zoom level (the hosting controller keeps a long-lived root view).
private struct PlaylistPanelRoot: View {
    @ObservedObject var layoutState: AmpXPanelLayoutState
    @EnvironmentObject var uiScale: AmpXUIScale

    var body: some View {
        ClassicPlaylistView(
            playlistSize: self.layoutState.playlistSizeBinding,
            isMinimized: self.layoutState.playlistMinimizedBinding,
            showPlaylist: Binding(
                get: { self.layoutState.showPlaylist },
                set: { self.layoutState.showPlaylist = $0 }
            )
        )
        .environment(\.winampUIScale, self.uiScale.scale)
        .fixedSize()
    }
}

/// Observing root for the detached equalizer window.
private struct EqualizerPanelRoot: View {
    @ObservedObject var layoutState: AmpXPanelLayoutState
    @EnvironmentObject var uiScale: AmpXUIScale

    var body: some View {
        ClassicEqualizerView(
            showEqualizer: Binding(
                get: { self.layoutState.showEqualizer },
                set: { self.layoutState.showEqualizer = $0 }
            ),
            isMinimized: Binding(
                get: { self.layoutState.equalizerMinimized },
                set: { self.layoutState.equalizerMinimized = $0 }
            )
        )
        .environment(\.winampUIScale, self.uiScale.scale)
        .fixedSize()
    }
}

/// Observing root for the detached visualizer window (ENTHEA / optional Metal kill switch).
private struct VisualizerPanelRoot: View {
    @ObservedObject var layoutState: AmpXPanelLayoutState
    @EnvironmentObject var uiScale: AmpXUIScale

    var body: some View {
        ClassicVisualizerPanelView(
            visualizerSize: self.layoutState.visualizerSizeBinding,
            isMinimized: self.layoutState.visualizerMinimizedBinding,
            showVisualizer: Binding(
                get: { self.layoutState.showVisualizer },
                set: { self.layoutState.showVisualizer = $0 }
            ),
            isTheater: self.layoutState.visualizerInTheaterBinding,
            displaySize: self.layoutState.visualizerDisplaySize
        )
        .environment(\.winampUIScale, self.uiScale.scale)
    }
}
