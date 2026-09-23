import AppKit

enum AmpXMenuBuilder {
    @MainActor
    static func makeMainMenu(application: AmpXApplicationController) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(self.makeAppMenu(application: application))
        mainMenu.addItem(self.makeFileMenu(application: application))
        mainMenu.addItem(self.makeEditMenu())
        mainMenu.addItem(self.makePlaybackMenu(application: application))
        mainMenu.addItem(self.makeViewMenu(application: application))
        mainMenu.addItem(self.makeWindowMenu(application: application))
        return mainMenu
    }

    @MainActor
    static func makePlayerMenu(application: AmpXApplicationController) -> NSMenu {
        let menu = NSMenu()
        self.appendFileItems(to: menu, application: application)
        menu.addItem(.separator())
        self.appendPlaybackItems(to: menu, application: application, includeToggles: false)
        menu.addItem(.separator())
        menu.addItem(
            titled: "Quit AmpX",
            action: #selector(NSApplication.terminate(_:)),
            target: NSApp,
            keyEquivalent: "q",
            modifiers: .command
        )
        return menu
    }

    @MainActor
    private static func makeAppMenu(application _: AmpXApplicationController) -> NSMenuItem {
        let appMenu = NSMenu()
        appMenu.addItem(
            titled: "About AmpX",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            target: NSApp
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            titled: "Hide AmpX",
            action: #selector(NSApplication.hide(_:)),
            target: NSApp,
            keyEquivalent: "h",
            modifiers: .command
        )
        appMenu.addItem(
            titled: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            target: NSApp,
            keyEquivalent: "h",
            modifiers: [.command, .option]
        )
        appMenu.addItem(
            titled: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            target: NSApp
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            titled: "Quit AmpX",
            action: #selector(NSApplication.terminate(_:)),
            target: NSApp,
            keyEquivalent: "q",
            modifiers: .command
        )

        let item = NSMenuItem(title: ProcessInfo.processInfo.processName, action: nil, keyEquivalent: "")
        item.submenu = appMenu
        return item
    }

    @MainActor
    private static func makeFileMenu(application: AmpXApplicationController) -> NSMenuItem {
        let menu = NSMenu(title: "File")
        self.appendFileItems(to: menu, application: application)
        return self.titled("File", submenu: menu)
    }

    @MainActor
    private static func appendFileItems(to menu: NSMenu, application: AmpXApplicationController) {
        menu.addItem(
            titled: AmpXMenuCatalog.FileItem.addFiles.rawValue,
            action: #selector(AmpXApplicationController.addFiles(_:)),
            target: application,
            keyEquivalent: AmpXMenuCatalog.FileShortcut.addFilesKey,
            modifiers: self.fileModifiers(
                command: AmpXMenuCatalog.FileShortcut.addFilesUsesCommand,
                shift: AmpXMenuCatalog.FileShortcut.addFilesUsesShift
            )
        )
        menu.addItem(
            titled: AmpXMenuCatalog.FileItem.addFolder.rawValue,
            action: #selector(AmpXApplicationController.addFolder(_:)),
            target: application,
            keyEquivalent: AmpXMenuCatalog.FileShortcut.addFilesKey,
            modifiers: self.fileModifiers(
                command: AmpXMenuCatalog.FileShortcut.addFolderUsesCommand,
                shift: AmpXMenuCatalog.FileShortcut.addFolderUsesShift
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            titled: AmpXMenuCatalog.FileItem.loadPlaylist.rawValue,
            action: #selector(AmpXApplicationController.loadPlaylist(_:)),
            target: application,
            keyEquivalent: "o",
            modifiers: .command
        )
        menu.addItem(
            titled: AmpXMenuCatalog.FileItem.savePlaylist.rawValue,
            action: #selector(AmpXApplicationController.savePlaylist(_:)),
            target: application,
            keyEquivalent: "s",
            modifiers: .command
        )
    }

    @MainActor
    private static func makeEditMenu() -> NSMenuItem {
        let menu = NSMenu(title: "Edit")
        return self.titled("Edit", submenu: menu)
    }

    @MainActor
    private static func makePlaybackMenu(application: AmpXApplicationController) -> NSMenuItem {
        let menu = NSMenu(title: "Playback")
        self.appendPlaybackItems(to: menu, application: application, includeToggles: true)
        return self.titled("Playback", submenu: menu)
    }

    @MainActor
    private static func appendPlaybackItems(
        to menu: NSMenu,
        application: AmpXApplicationController,
        includeToggles: Bool
    ) {
        menu.addItem(
            titled: AmpXMenuCatalog.PlaybackItem.play.rawValue,
            action: #selector(AmpXApplicationController.play(_:)),
            target: application,
            keyEquivalent: "x"
        )
        menu.addItem(
            titled: AmpXMenuCatalog.PlaybackItem.pause.rawValue,
            action: #selector(AmpXApplicationController.pause(_:)),
            target: application,
            keyEquivalent: "c"
        )
        menu.addItem(
            titled: AmpXMenuCatalog.PlaybackItem.stop.rawValue,
            action: #selector(AmpXApplicationController.stopPlayback(_:)),
            target: application,
            keyEquivalent: "v"
        )
        menu.addItem(
            titled: AmpXMenuCatalog.PlaybackItem.previous.rawValue,
            action: #selector(AmpXApplicationController.previousTrack(_:)),
            target: application,
            keyEquivalent: "z"
        )
        menu.addItem(
            titled: AmpXMenuCatalog.PlaybackItem.next.rawValue,
            action: #selector(AmpXApplicationController.nextTrack(_:)),
            target: application,
            keyEquivalent: "b"
        )
        guard includeToggles else { return }
        menu.addItem(.separator())
        menu.addItem(
            toggle: AmpXMenuCatalog.PlaybackItem.shuffle.rawValue,
            action: #selector(AmpXApplicationController.toggleShuffle(_:)),
            target: application
        )
        menu.addItem(
            toggle: AmpXMenuCatalog.PlaybackItem.repeat.rawValue,
            action: #selector(AmpXApplicationController.toggleRepeat(_:)),
            target: application
        )
    }

    @MainActor
    private static func makeViewMenu(application: AmpXApplicationController) -> NSMenuItem {
        let menu = NSMenu(title: "View")
        menu.addItem(
            toggle: AmpXMenuCatalog.ViewPanel.equalizer.rawValue,
            action: #selector(AmpXApplicationController.toggleEqualizer(_:)),
            target: application
        )
        menu.addItem(
            toggle: AmpXMenuCatalog.ViewPanel.playlist.rawValue,
            action: #selector(AmpXApplicationController.togglePlaylist(_:)),
            target: application
        )
        if application.hosts.isEntheaEnabled {
            menu.addItem(
                toggle: AmpXMenuCatalog.ViewPanel.visualizer.rawValue,
                action: #selector(AmpXApplicationController.toggleVisualizer(_:)),
                target: application
            )
        }
        return self.titled("View", submenu: menu)
    }

    @MainActor
    private static func makeWindowMenu(application: AmpXApplicationController) -> NSMenuItem {
        let menu = NSMenu(title: "Window")
        menu.addItem(
            titled: "AmpX",
            action: #selector(AmpXApplicationController.showAmpX(_:)),
            target: application
        )
        menu.addItem(.separator())
        menu.addItem(
            titled: "Move Module Up",
            action: #selector(AmpXApplicationController.moveModuleUp(_:)),
            target: application,
            keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!),
            modifiers: [.command, .option]
        )
        menu.addItem(
            titled: "Move Module Down",
            action: #selector(AmpXApplicationController.moveModuleDown(_:)),
            target: application,
            keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!),
            modifiers: [.command, .option]
        )
        menu.addItem(
            titled: "Detach/Re-dock Module",
            action: #selector(AmpXApplicationController.toggleDetachModule(_:)),
            target: application,
            keyEquivalent: "d",
            modifiers: [.command, .option]
        )
        menu.addItem(
            titled: "Collapse/Expand Module",
            action: #selector(AmpXApplicationController.toggleCollapseModule(_:)),
            target: application,
            keyEquivalent: "c",
            modifiers: [.command, .option]
        )
        menu.addItem(.separator())
        menu.addItem(
            titled: "Close Stack",
            action: #selector(AmpXApplicationController.closeStack(_:)),
            target: application,
            keyEquivalent: "w",
            modifiers: .command
        )
        menu.addItem(.separator())
        menu.addItem(
            titled: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            target: NSApp
        )
        NSApp.windowsMenu = menu
        return self.titled("Window", submenu: menu)
    }

    private static func fileModifiers(command: Bool, shift: Bool) -> NSEvent.ModifierFlags {
        var modifiers: NSEvent.ModifierFlags = []
        if command {
            modifiers.insert(.command)
        }
        if shift {
            modifiers.insert(.shift)
        }
        return modifiers
    }

    private static func titled(_ title: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }
}

private extension NSMenu {
    @MainActor
    func addItem(
        titled title: String,
        action: Selector?,
        target: AnyObject?,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        item.keyEquivalentModifierMask = modifiers
        self.addItem(item)
    }

    @MainActor
    func addItem(
        toggle title: String,
        action: Selector?,
        target: AnyObject?
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        self.addItem(item)
    }
}
