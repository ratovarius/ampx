/// Which modules are windowshaded (collapsed) and which are closed. Window positions live in
/// `AmpXSavedLayout.frames`; docking is derived from those frames, never stored here.
struct AmpXModuleState: Equatable {
    var collapsed: Set<AmpXModuleID> = []
    var closed: Set<AmpXModuleID> = [.enthea]

    mutating func setCollapsed(_ id: AmpXModuleID, _ value: Bool) {
        if value {
            self.collapsed.insert(id)
        } else {
            self.collapsed.remove(id)
        }
    }

    /// The Player can't be closed as a module; closing its window quits AmpX instead.
    mutating func close(_ id: AmpXModuleID) {
        guard id != .player else { return }
        self.closed.insert(id)
    }

    mutating func reopen(_ id: AmpXModuleID) {
        self.closed.remove(id)
    }
}
