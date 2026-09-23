import AppKit

class AmpXDrawingView: NSView {
    let skin: any AmpXSkin

    private(set) var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(skin: any AmpXSkin) {
        self.skin = skin
        super.init(frame: .zero)
        wantsLayer = true
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

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with _: NSEvent) {
        self.isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with _: NSEvent) {
        self.isHovered = false
        needsDisplay = true
    }

    override func mouseMoved(with _: NSEvent) {
        needsDisplay = true
    }
}
