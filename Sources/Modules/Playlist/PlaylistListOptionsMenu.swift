import AppKit

@MainActor
final class PlaylistListOptionsMenu: NSObject {
    private let manager: PlaylistManager
    private let keyboardAdapter: PlaylistKeyboardAdapter

    init(manager: PlaylistManager, keyboardAdapter: PlaylistKeyboardAdapter) {
        self.manager = manager
        self.keyboardAdapter = keyboardAdapter
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        for (title, action) in [
            ("New List", #selector(self.newList)),
            ("Save List…", #selector(self.saveList)),
            ("Load List…", #selector(self.loadList)),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if title == "Save List…" {
                item.isEnabled = !self.manager.tracks.isEmpty
            }
            menu.addItem(item)
        }
        return menu
    }

    func show(relativeTo button: AmpXButton) {
        self.makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    @objc private func newList() {
        PlaylistChromeActions.clearList(manager: self.manager, selection: &self.keyboardAdapter.selection)
        self.keyboardAdapter.onSelectionChanged?()
    }

    @objc private func saveList() {
        self.manager.saveM3UPlaylist()
    }

    @objc private func loadList() {
        self.manager.showLoadM3UPicker()
    }
}
