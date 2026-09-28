import AppKit

/// The footer's ROOTS ▾ menu (Library Module spec § Behaviour): Add Folder…, then one submenu per root with
/// its path, status, Relocate… and Remove….
enum LibraryRootsMenu {
    struct Actions {
        var add: () -> Void
        var relocate: (UUID) -> Void
        var remove: (UUID) -> Void
    }

    static func make(roots: [LibraryRootSnapshot], actions: Actions) -> NSMenu {
        let menu = NSMenu(title: "Roots")
        menu.autoenablesItems = false
        menu.addItem(ClosureMenuItem(title: "Add Folder…", action: actions.add))
        guard !roots.isEmpty else { return menu }
        menu.addItem(.separator())
        for root in roots {
            let item = NSMenuItem(title: root.url.lastPathComponent, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: item.title)
            submenu.autoenablesItems = false
            let path = NSMenuItem(title: root.displayPath, action: nil, keyEquivalent: "")
            path.isEnabled = false
            submenu.addItem(path)
            let status = NSMenuItem(title: self.status(of: root), action: nil, keyEquivalent: "")
            status.isEnabled = false
            submenu.addItem(status)
            submenu.addItem(.separator())
            submenu.addItem(ClosureMenuItem(title: "Relocate…") { actions.relocate(root.id) })
            submenu.addItem(ClosureMenuItem(title: "Remove…") { actions.remove(root.id) })
            item.submenu = submenu
            menu.addItem(item)
        }
        return menu
    }

    static func status(of root: LibraryRootSnapshot) -> String {
        if !root.isAvailable {
            return "Unavailable"
        }
        switch root.unreadableFolderCount {
        case 0: return "Available"
        case 1: return "1 folder unreadable"
        case let count: return "\(count) folders unreadable"
        }
    }

    static func removeConfirmation(rootName: String, trackCount: Int) -> (message: String, info: String) {
        let info = trackCount == 1
            ? "Its 1 track and its rating and play count will be removed. The file is not deleted."
            : "Its \(LibraryFormatting.grouped(trackCount)) tracks and their ratings and play counts will be removed. The files are not deleted."
        return ("Remove \"\(rootName)\" from the library?", info)
    }
}

/// A menu item that runs a closure; it is its own target, so the menu keeps the action alive.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(self.fire), keyEquivalent: "")
        self.target = self
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func fire() {
        self.handler()
    }
}

enum LibraryFormatting {
    private static let groupedFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        return formatter
    }()

    static func grouped(_ value: Int) -> String {
        self.groupedFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// h:mm:ss with unbounded hours.
    static func longDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
}
