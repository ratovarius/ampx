import AppKit

/// Hosts the module stack. The stack never scrolls: the window follows the composition height and the
/// expanded Playlist absorbs any shortage of screen height (see `AmpXLayout`).
final class AmpXStackViewport: NSView {
    let stackView = AmpXModuleStackView()

    private var contentHeight: CGFloat = 0

    /// The whole composition is always visible.
    var visibleContentRect: CGRect {
        CGRect(x: 0, y: 0, width: bounds.width, height: self.contentHeight)
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(self.stackView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// `nonisolated`: AppKit reads this from its layer-display path with no Swift task, and on
    /// macOS 26 an isolated getter crashes in `swift_task_isCurrentExecutor` (see commit 5562af8).
    override nonisolated var isFlipped: Bool {
        true
    }

    func applyLayout(_ result: AmpXLayoutResult, state: AmpXModuleOrder) {
        self.contentHeight = result.contentHeight
        self.stackView.applyLayout(result, state: state, playlistViewportHeight: result.playlistViewportHeight)
        self.stackView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: self.contentHeight)
    }

    func viewportPoint(fromScreenPoint screenPoint: NSPoint) -> NSPoint {
        guard let stackWindow = window else { return .zero }
        let windowPoint = stackWindow.convertPoint(fromScreen: screenPoint)
        return convert(windowPoint, from: nil)
    }

    func contains(screenPoint: NSPoint) -> Bool {
        bounds.contains(self.viewportPoint(fromScreenPoint: screenPoint))
    }

    /// Stack content coordinates equal viewport coordinates because the stack never scrolls.
    func stackContentPoint(fromScreenPoint screenPoint: NSPoint) -> CGPoint {
        self.viewportPoint(fromScreenPoint: screenPoint)
    }

    override func scrollWheel(with event: NSEvent) {
        if let playlistView = stackView.moduleView(for: .playlist),
           playlistView.superview === self.stackView,
           !playlistView.isContentCollapsed, !playlistView.isHiddenOrHasHiddenAncestor,
           let playlist = playlistView.content as? PlaylistModuleContent,
           playlist.canScrollVertically
        {
            playlist.scrollWheel(with: event)
            return
        }
        nextResponder?.scrollWheel(with: event)
    }
}
