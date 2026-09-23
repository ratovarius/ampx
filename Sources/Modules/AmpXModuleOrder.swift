struct AmpXModuleOrder: Equatable {
    var order: [AmpXModuleID] = [.player, .equalizer, .playlist, .enthea]
    var collapsed: Set<AmpXModuleID> = []
    var detached: Set<AmpXModuleID> = []
    var closed: Set<AmpXModuleID> = [.enthea]

    mutating func move(_ id: AmpXModuleID, to index: Int) {
        guard let currentIndex = self.order.firstIndex(of: id) else { return }
        self.order.remove(at: currentIndex)
        let clampedIndex = max(0, min(index, self.order.count))
        self.order.insert(id, at: clampedIndex)
    }

    mutating func setCollapsed(_ id: AmpXModuleID, _ value: Bool) {
        if value {
            self.collapsed.insert(id)
        } else {
            self.collapsed.remove(id)
        }
    }

    mutating func detach(_ id: AmpXModuleID) {
        guard id != .player else { return }
        self.detached.insert(id)
    }

    mutating func redock(_ id: AmpXModuleID, at index: Int) {
        self.detached.remove(id)
        self.closed.remove(id)
        self.move(id, to: index)
    }

    mutating func close(_ id: AmpXModuleID) {
        guard id != .player else { return }
        self.closed.insert(id)
    }

    mutating func reopen(_ id: AmpXModuleID) {
        self.closed.remove(id)
    }
}
