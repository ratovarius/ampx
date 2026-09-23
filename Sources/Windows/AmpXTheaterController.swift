import AppKit

struct AmpXTheaterSnapshot {
    let originalHostID: AmpXModuleID?
    let modulePosition: Int
    let frame: CGRect
    let scale: CGFloat
    let presentationOptions: NSApplication.PresentationOptions
}

enum AmpXHostPresentation {
    case normal
    case theater
}

@MainActor
final class AmpXTheaterController: NSObject, NSWindowDelegate {
    private weak var hosts: AmpXHostCoordinator?
    private let screenFrame: () -> CGRect
    private let getPresentation: () -> NSApplication.PresentationOptions
    private let setPresentation: (NSApplication.PresentationOptions) -> Void

    private var snapshot: AmpXTheaterSnapshot?
    private var theaterWindow: NSWindow?
    private let containerView = NSView()

    private(set) var isActive = false

    init(
        hosts: AmpXHostCoordinator,
        screenFrame: @escaping () -> CGRect,
        getPresentation: @escaping () -> NSApplication.PresentationOptions,
        setPresentation: @escaping (NSApplication.PresentationOptions) -> Void
    ) {
        self.hosts = hosts
        self.screenFrame = screenFrame
        self.getPresentation = getPresentation
        self.setPresentation = setPresentation
        super.init()
    }

    var window: NSWindow? {
        self.theaterWindow
    }

    func enter() {
        guard !self.isActive else { return }
        guard let hosts, let view = hosts.moduleView(for: .enthea) else { return }
        guard !hosts.state.closed.contains(.enthea) else { return }

        // Theater presentation needs expanded content; expand before extracting the view.
        if hosts.state.collapsed.contains(.enthea) {
            hosts.setCollapsed(.enthea, false)
        }

        let geometry = hosts.captureTheaterSnapshot(for: .enthea)
        self.snapshot = AmpXTheaterSnapshot(
            originalHostID: geometry.originalHostID,
            modulePosition: geometry.modulePosition,
            frame: geometry.frame,
            scale: geometry.scale,
            presentationOptions: self.getPresentation()
        )
        self.isActive = true

        hosts.extractModuleViewForTheater(.enthea)

        let frame = self.screenFrame()
        self.ensureTheaterWindow(frame: frame)
        self.containerView.frame = self.containerView.superview?.bounds ?? frame
        view.enterTheaterPresentation(containerSize: frame.size)
        self.containerView.addSubview(view)
        self.theaterWindow?.setFrame(frame, display: true)
        self.theaterWindow?.orderFrontRegardless()
        self.theaterWindow?.makeKey()

        var presentation = self.getPresentation()
        presentation.insert([.autoHideMenuBar, .autoHideDock])
        self.setPresentation(presentation)

        (view.content as? EntheaModuleContent)?.refreshTheaterPresentation()
        hosts.refreshEffectiveVisibility()
    }

    func exit() {
        guard self.isActive, let snapshot else { return }

        self.setPresentation(snapshot.presentationOptions)
        self.hosts?.reinstallModuleViewFromTheater(.enthea, snapshot: snapshot)

        self.theaterWindow?.orderOut(nil)
        self.theaterWindow = nil
        self.snapshot = nil
        self.isActive = false
        self.hosts?.refreshEffectiveVisibility()
    }

    func handleApplicationTermination() {
        if self.isActive {
            self.exit()
        }
    }

    func windowWillClose(_: Notification) {
        self.exit()
    }

    func windowDidMiniaturize(_: Notification) {
        self.hosts?.refreshEffectiveVisibility()
    }

    func windowDidDeminiaturize(_: Notification) {
        self.hosts?.refreshEffectiveVisibility()
    }

    func windowDidChangeOcclusionState(_: Notification) {
        self.hosts?.refreshEffectiveVisibility()
    }

    private func ensureTheaterWindow(frame: CGRect) {
        guard self.theaterWindow == nil else { return }

        let window = AmpXHostWindow(
            contentRect: frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = self.containerView
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.containerView.wantsLayer = true
        self.containerView.layer?.backgroundColor = NSColor.black.cgColor
        self.theaterWindow = window
    }
}
