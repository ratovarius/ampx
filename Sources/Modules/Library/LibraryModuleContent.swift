import AppKit
import Combine

/// Folder panels and alerts, injectable so tests never open AppKit UI.
@MainActor
protocol LibraryPanelPresenting: AnyObject {
    func chooseFolder(title: String) async -> URL?
    func confirmRemove(message: String, info: String) async -> Bool
    func showError(_ message: String)
}

@MainActor
final class AppKitLibraryPanels: LibraryPanelPresenting {
    func chooseFolder(title: String) async -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }

    func confirmRemove(message: String, info: String) async -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

/// The Library window's body (Library Module spec): toolbar, GENRE/ARTIST lists, track table, MIXES WELL
/// sidebar and footer over one `LibraryBrowserModel`. Shows an empty state without roots and an error state
/// when the engine cannot open. Closing the window stops only the browser model.
final class LibraryModuleContent: AmpXModuleContent {
    static let overlapMessage = "That folder overlaps a folder already in the library."
    static let emptyMessage = "No library folders yet"

    let toolbar: LibraryToolbarView
    let genreList: LibraryFacetListView
    let artistList: LibraryFacetListView
    let table: LibraryTrackTableView
    let sidebar: LibraryMixesSidebarView
    let footer: LibraryFooterView
    let resizeHandle: PlaylistResizeHandleView
    private let emptyButton: AmpXButton

    private(set) var filter = LibraryFilterState()
    private(set) var model: LibraryBrowserModel?
    private(set) var errorMessage: String?
    private var preferences: LibraryModulePreferences
    private var rootsLoaded = false

    private let controller: LibraryController?
    private let playlist: PlaylistManager?
    private let audioPlayer: AudioPlayer?
    private let panels: LibraryPanelPresenting
    private let defaults: UserDefaults
    private var controllerObservation: AnyCancellable?
    private var modelObservations: Set<AnyCancellable> = []
    private var playerObservation: AnyCancellable?

    var onResizeViewport: ((PlaylistResizeHandleView.Phase) -> Void)? {
        get { self.resizeHandle.onResize }
        set { self.resizeHandle.onResize = newValue }
    }

    init(
        skin: any AmpXSkin,
        controller: LibraryController?,
        playlist: PlaylistManager?,
        audioPlayer: AudioPlayer?,
        panels: LibraryPanelPresenting = AppKitLibraryPanels(),
        defaults: UserDefaults = .standard
    ) {
        self.toolbar = LibraryToolbarView(skin: skin)
        self.genreList = LibraryFacetListView(skin: skin, title: "GENRE")
        self.artistList = LibraryFacetListView(skin: skin, title: "ARTIST")
        self.table = LibraryTrackTableView(skin: skin)
        self.sidebar = LibraryMixesSidebarView(skin: skin)
        self.footer = LibraryFooterView(skin: skin)
        self.resizeHandle = PlaylistResizeHandleView(skin: skin)
        self.emptyButton = AmpXButton(skin: skin)
        self.controller = controller
        self.playlist = playlist
        self.audioPlayer = audioPlayer
        self.panels = panels
        self.defaults = defaults
        self.preferences = LibraryModulePreferences.load(defaults)
        super.init(skin: skin)

        for view in [
            self.toolbar,
            self.genreList,
            self.artistList,
            self.table,
            self.sidebar,
            self.footer,
            self.emptyButton,
            self.resizeHandle,
        ] as [NSView] {
            addSubview(view)
        }
        self.emptyButton.label = "ADD FOLDER…"
        self.emptyButton.applyKeyLabelStyle()
        self.emptyButton.isHidden = true
        self.emptyButton.action = { [weak self] in self?.startTask { await $0.addFolder() } }

        self.table.columns = self.preferences.columns
        self.filter.restoreSort(self.preferences.sort, ascending: self.preferences.ascending)
        self.filter.columnsChanged(self.preferences.columns)
        self.sidebar.followsSelection = self.preferences.mixesFollowsSelection
        self.wireViews()
        self.applyFilter()

        self.controllerObservation = controller?.$state.sink { [weak self] state in
            DispatchQueue.main.async { self?.controllerStateChanged(state) }
        }
        self.playerObservation = audioPlayer?.$currentTrack.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateSidebarReference() }
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("Library")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - State

    var isShowingEmptyState: Bool {
        guard self.errorMessage == nil else { return false }
        if self.model == nil {
            return self.controller != nil && self.controller?.state != .opening
        }
        return self.controller != nil && self.rootsLoaded && (self.model?.roots.isEmpty ?? true)
    }

    private func controllerStateChanged(_ state: LibraryController.State) {
        switch state {
        case .ready:
            self.errorMessage = nil
            if self.model == nil, let playlist = self.playlist, let model = self.controller?.makeBrowserModel(playlist: playlist) {
                self.attach(model: model)
            }
        case let .failed(message):
            self.errorMessage = message
        case .notConfigured, .opening:
            break
        }
        self.refreshOverlay()
    }

    /// Drives the views from `model` (also the test seam for synthetic rows).
    func attach(model: LibraryBrowserModel) {
        self.model?.stop()
        self.modelObservations.removeAll()
        self.model = model
        self.rootsLoaded = false
        model.$rows.sink { [weak self] rows in
            DispatchQueue.main.async { self?.rowsChanged(rows) }
        }.store(in: &self.modelObservations)
        model.$facets.sink { [weak self] facets in
            DispatchQueue.main.async {
                self?.genreList.counts = facets.genres
                self?.artistList.counts = facets.artists
            }
        }.store(in: &self.modelObservations)
        model.$progress.combineLatest(model.$unavailableTotal).sink { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateFooter() }
        }.store(in: &self.modelObservations)
        model.$roots.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.rootsLoaded = true
                self?.refreshOverlay()
            }
        }.store(in: &self.modelObservations)
        model.setQuery(self.filter.query)
        self.startTask { content in
            await content.model?.reloadRoots()
            content.rootsLoaded = true
            content.refreshOverlay()
        }
        self.refreshOverlay()
    }

    /// Window closed: stop the browser model only; the engine keeps scanning and watching.
    func windowDidClose() {
        self.model?.stop()
        self.model = nil
        self.modelObservations.removeAll()
    }

    private func rowsChanged(_ rows: [LibraryRow]) {
        var selection = self.table.selection
        selection.retain(present: rows.map(\.id))
        self.table.rows = rows
        self.table.selection = selection
        self.syncSelectionToModel(selection)
        self.updateFooter()
        self.updateSidebarReference()
    }

    private func updateFooter() {
        let rows = self.table.rows
        self.footer.update(
            trackCount: rows.count,
            totalDuration: rows.reduce(0) { $0 + $1.duration },
            progress: self.model?.progress.flatMap { $0.phase == .parsing && $0.done == $0.total ? nil : $0 },
            missing: self.model?.unavailableTotal ?? 0,
            showingMissing: self.filter.showMissing
        )
    }

    private func updateSidebarReference() {
        let row: LibraryRow? = if self.sidebar.followsSelection {
            self.table.selection.focused.flatMap { id in self.table.rows.first { $0.id == id } }
        } else {
            self.audioPlayer?.currentTrack?.url.flatMap { url in self.table.rows.first { $0.url == url } }
        }
        self.sidebar.updateReference(row)
    }

    private func refreshOverlay() {
        self.emptyButton.isHidden = !self.isShowingEmptyState
        self.table.placeholderIsError = self.errorMessage != nil
        self.table.placeholder = self.errorMessage ?? (self.isShowingEmptyState ? Self.emptyMessage : nil)
    }

    // MARK: - Wiring

    private func wireViews() {
        self.toolbar.onSearch = { [weak self] text in
            self?.filter.search = text
            self?.applyFilter()
        }
        self.toolbar.onBpm = { [weak self] low, high in
            self?.filter.bpmMin = low
            self?.filter.bpmMax = high
            self?.applyFilter()
        }
        self.toolbar.onClear = { [weak self] in
            self?.filter.clear()
            self?.applyFilter()
        }
        self.genreList.onClick = { [weak self] value, command in
            self?.filter.facetClick(value, facet: \.genres, command: command)
            self?.applyFilter()
        }
        self.artistList.onClick = { [weak self] value, command in
            self?.filter.facetClick(value, facet: \.artists, command: command)
            self?.applyFilter()
        }
        self.footer.onToggleMissing = { [weak self] in
            guard let self else { return }
            self.filter.showMissing.toggle()
            self.applyFilter()
        }
        self.footer.onEnqueue = { [weak self] in self?.startTask { await $0.enqueueSelection(append: true) } }
        self.footer.rootsButton.action = { [weak self] in
            guard let self else { return }
            let button = self.footer.rootsButton
            self.rootsMenu().popUp(positioning: nil, at: CGPoint(x: 0, y: button.bounds.maxY + 2), in: button)
        }
        self.table.onSortClick = { [weak self] column in
            guard let self else { return }
            self.filter.sortBy(column)
            self.savePreferences()
            self.applyFilter()
        }
        self.table.onColumnsChange = { [weak self] columns in
            guard let self else { return }
            self.preferences.columns = columns
            self.table.columns = columns
            self.filter.columnsChanged(columns)
            self.savePreferences()
            self.applyFilter()
        }
        self.table.onSelectionChange = { [weak self] selection in
            self?.syncSelectionToModel(selection)
            self?.updateSidebarReference()
        }
        self.table.onActivate = { [weak self] id in
            self?.startTask { await $0.model?.enqueue(append: false, clickedID: id) }
        }
        self.table.onDragBegan = { [weak self] rows in self?.registerRoots(of: rows) }
        self.sidebar.onModeChange = { [weak self] followsSelection in
            guard let self else { return }
            self.preferences.mixesFollowsSelection = followsSelection
            self.savePreferences()
            self.updateSidebarReference()
        }
    }

    private func applyFilter() {
        self.toolbar.apply(self.filter)
        self.genreList.selected = self.filter.genres
        self.artistList.selected = self.filter.artists
        let query = self.filter.query
        self.table.sort = (query.sort, query.ascending)
        self.model?.setQuery(query)
        self.updateFooter()
    }

    private func savePreferences() {
        let query = self.filter.query
        self.preferences.sort = query.sort
        self.preferences.ascending = query.ascending
        self.preferences.save(self.defaults)
    }

    private func syncSelectionToModel(_ selection: LibrarySelection) {
        self.model?.selection = selection.ids
        self.model?.focusedID = selection.focused
    }

    private func registerRoots(of rows: [LibraryRow]) {
        let rootIDs = Set(rows.map(\.rootID))
        let store = self.controller?.bookmarkStore ?? .shared
        for root in self.model?.roots ?? [] where rootIDs.contains(root.id) {
            store.saveBookmark(for: root.url)
        }
    }

    private func startTask(_ work: @escaping @MainActor (LibraryModuleContent) async -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await work(self)
        }
    }

    // MARK: - Actions

    func selectAllRows() {
        var selection = self.table.selection
        selection.selectAll(order: self.table.rows.map(\.id))
        self.table.selection = selection
        self.syncSelectionToModel(selection)
    }

    func enqueueSelection(append: Bool) async {
        await self.model?.enqueue(append: append, clickedID: nil)
    }

    func focusSearch() {
        window?.makeFirstResponder(self.toolbar.search)
    }

    /// Keys `AmpXKeyRouter` routes here (`.library`): ↑↓ Home End PageUp PageDown (± ⇧) move the table's
    /// focus, ↩ replaces and plays, ⌘↩ appends, ⌘A selects all and ⌘F focuses search.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let extend = flags.contains(.shift)
        let order = self.table.rows.map(\.id)
        var selection = self.table.selection
        switch event.keyCode {
        case 125, 126:
            selection.moveFocus(by: event.keyCode == 125 ? 1 : -1, extend: extend, order: order)
        case 116, 121:
            let page = self.table.visibleRowCount
            selection.moveFocus(by: event.keyCode == 121 ? page : -page, extend: extend, order: order)
        case 115, 119:
            selection.moveFocusToEdge(end: event.keyCode == 119, extend: extend, order: order)
        case 36, 76:
            let append = flags.contains(.command)
            self.startTask { await $0.enqueueSelection(append: append) }
            return true
        case 0:
            self.selectAllRows()
            return true
        case 3:
            self.focusSearch()
            return true
        default:
            return false
        }
        self.table.selection = selection
        self.table.scrollToFocused()
        self.syncSelectionToModel(selection)
        return true
    }

    func rootsMenu() -> NSMenu {
        LibraryRootsMenu.make(
            roots: self.model?.roots ?? [],
            actions: .init(
                add: { [weak self] in self?.startTask { await $0.addFolder() } },
                relocate: { [weak self] id in self?.startTask { await $0.relocateRoot(id) } },
                remove: { [weak self] id in self?.startTask { await $0.removeRoot(id) } }
            )
        )
    }

    func addFolder() async {
        guard let controller = self.controller, let url = await self.panels.chooseFolder(title: "Add Library Folder") else { return }
        do {
            let engine = try await controller.ensureEngine()
            _ = try await engine.addRoot(url: url)
            await self.model?.reloadRoots()
        } catch {
            self.panels.showError(Self.message(for: error))
        }
    }

    func relocateRoot(_ id: UUID) async {
        guard let engine = self.controller?.engine,
              let url = await self.panels.chooseFolder(title: "Relocate Library Folder")
        else { return }
        do {
            try await engine.relocateRoot(id: id, to: url)
            await self.model?.reloadRoots()
        } catch {
            self.panels.showError(Self.message(for: error))
        }
    }

    func removeRoot(_ id: UUID) async {
        guard let engine = self.controller?.engine else { return }
        do {
            guard let root = try await engine.roots().first(where: { $0.id == id }) else { return }
            let count = try await engine.index.query(LibraryQuery(), generation: 0).rows.filter { $0.rootID == id }.count
            let text = LibraryRootsMenu.removeConfirmation(rootName: root.url.lastPathComponent, trackCount: count)
            guard await self.panels.confirmRemove(message: text.message, info: text.info) else { return }
            try await engine.removeRoot(id: id)
            await self.model?.reloadRoots()
        } catch {
            self.panels.showError(Self.message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        if case LibraryStoreError.overlappingRoot = error {
            return self.overlapMessage
        }
        return LibraryController.message(for: error)
    }

    // MARK: - Layout and drawing

    override func layout() {
        super.layout()
        let frames = LibraryModuleLayout.frames(size: bounds.size)
        self.toolbar.frame = frames.toolbar
        self.genreList.frame = frames.genre
        self.artistList.frame = frames.artist
        self.table.frame = frames.table
        self.sidebar.frame = frames.sidebar
        self.footer.frame = frames.footer
        self.emptyButton.frame = CGRect(x: frames.table.midX - 70, y: frames.table.midY + 8, width: 140, height: 28)
        self.resizeHandle.frame = bounds
    }

    override func setEffectivelyVisible(_ visible: Bool) {
        super.setEffectivelyVisible(visible)
        if visible {
            self.controllerStateChanged(self.controller?.state ?? .notConfigured)
        }
    }
}
