import AppKit

class AmpXControlView: AmpXDrawingView {
    func cancelInteraction() {}
    var confinesHitTestingToBounds = false
    var focusRingInset: CGFloat = -2
    var isEnabled = true {
        didSet { needsDisplay = true }
    }

    var showsFocusRing = false {
        didSet { needsDisplay = true }
    }

    /// Keyboard navigation can focus a control, but a click cannot, so global shortcuts keep working
    /// after mouse use. AppKit's current event is what identifies the click.
    static func acceptsFocus(isEnabled: Bool, currentEventType: NSEvent.EventType?) -> Bool {
        guard isEnabled else { return false }
        switch currentEventType {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return false
        default:
            return true
        }
    }

    override var acceptsFirstResponder: Bool {
        Self.acceptsFocus(isEnabled: self.isEnabled, currentEventType: NSApp.currentEvent?.type)
    }

    /// `point` is in the superview's coordinate system; the expanded hit area is tested in local coordinates.
    /// Where expanded areas of neighboring controls overlap, the control whose frame is nearest wins, so a
    /// dense row of keys never lets one key steal a click that landed closer to its neighbor.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard self.isEnabled, !isHidden else { return nil }
        let localPoint = superview.map { convert(point, from: $0) } ?? point
        guard self.hitArea(for: bounds).contains(localPoint) else { return nil }
        guard !bounds.contains(localPoint), let superview else { return self }

        let distance = AmpXControlMath.distance(from: point, to: frame)
        for case let sibling as AmpXControlView in superview.subviews where sibling !== self {
            guard sibling.isEnabled, !sibling.isHidden else { continue }
            if sibling.frame.contains(point) {
                return nil
            }
            if AmpXControlMath.distance(from: point, to: sibling.frame) < distance,
               sibling.hitArea(for: sibling.frame).contains(point)
            {
                return nil
            }
        }
        return self
    }

    private func hitArea(for rect: CGRect) -> CGRect {
        self.confinesHitTestingToBounds ? rect : AmpXControlMath.expandedHitRect(for: rect)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            self.showsFocusRing = true
            self.noteFocusedModuleIfNeeded()
        }
        return became
    }

    private func noteFocusedModuleIfNeeded() {
        var ancestor: NSView? = superview
        while let view = ancestor {
            if let moduleView = view as? AmpXModuleView,
               let coordinator = findCoordinator(in: window)
            {
                coordinator.noteFocusedModule(moduleView.moduleID)
                return
            }
            ancestor = view.superview
        }
    }

    private func findCoordinator(in window: NSWindow?) -> AmpXHostCoordinator? {
        guard let window else { return nil }
        return (window.windowController as? AmpXModuleWindowController)?.coordinator
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            self.showsFocusRing = false
        }
        return resigned
    }

    func drawFocusRing(in context: CGContext, backingScale: CGFloat) {
        guard self.showsFocusRing else { return }
        let ring = bounds.insetBy(dx: self.focusRingInset, dy: self.focusRingInset)
        let aligned = AmpXPixelGrid.strokeRect(ring, lineWidth: 1, backingScale: backingScale)
        context.setStrokeColor(skin.green.cgColor)
        context.setLineWidth(1 / backingScale)
        context.stroke(aligned)
    }
}
