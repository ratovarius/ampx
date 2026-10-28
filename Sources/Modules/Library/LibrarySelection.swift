import Foundation

/// Table selection (Library Module spec § Behaviour): click, ⇧-click range from the anchor, ⌘-click toggle,
/// and keyboard focus movement. `order` is the displayed row order.
struct LibrarySelection: Equatable, Sendable {
    private(set) var ids: Set<UUID> = []
    private(set) var anchor: UUID?
    private(set) var focused: UUID?

    mutating func click(_ id: UUID, order _: [UUID]) {
        self.ids = [id]
        self.anchor = id
        self.focused = id
    }

    mutating func shiftClick(_ id: UUID, order: [UUID]) {
        guard let anchor = self.anchor else {
            self.click(id, order: order)
            return
        }
        self.ids = self.range(from: anchor, to: id, order: order)
        self.focused = id
    }

    mutating func commandClick(_ id: UUID) {
        if self.ids.contains(id) {
            self.ids.remove(id)
        } else {
            self.ids.insert(id)
        }
        self.anchor = id
        self.focused = id
    }

    /// ↑↓ and Page Up/Down. With no focus, a forward move focuses the first row and a backward one the last.
    mutating func moveFocus(by delta: Int, extend: Bool, order: [UUID]) {
        guard !order.isEmpty else { return }
        let target: Int = if let focused = self.focused, let index = order.firstIndex(of: focused) {
            min(max(index + delta, 0), order.count - 1)
        } else {
            delta >= 0 ? 0 : order.count - 1
        }
        self.focus(order[target], extend: extend, order: order)
    }

    mutating func moveFocusToEdge(end: Bool, extend: Bool, order: [UUID]) {
        guard let id = end ? order.last : order.first else { return }
        self.focus(id, extend: extend, order: order)
    }

    mutating func selectAll(order: [UUID]) {
        guard !order.isEmpty else { return }
        self.ids = Set(order)
        self.anchor = self.anchor ?? order.first
        self.focused = self.focused ?? order.first
    }

    /// After a refresh: ids no longer displayed are dropped (L1 rule), as are a vanished anchor and focus.
    mutating func retain(present order: [UUID]) {
        let present = Set(order)
        self.ids.formIntersection(present)
        if let anchor = self.anchor, !present.contains(anchor) {
            self.anchor = nil
        }
        if let focused = self.focused, !present.contains(focused) {
            self.focused = nil
        }
    }

    private mutating func focus(_ id: UUID, extend: Bool, order: [UUID]) {
        if extend, let anchor = self.anchor {
            self.ids = self.range(from: anchor, to: id, order: order)
        } else {
            self.ids = [id]
            self.anchor = id
        }
        self.focused = id
    }

    private func range(from anchor: UUID, to id: UUID, order: [UUID]) -> Set<UUID> {
        guard let start = order.firstIndex(of: anchor), let end = order.firstIndex(of: id) else { return [id] }
        return Set(order[min(start, end) ... max(start, end)])
    }
}
