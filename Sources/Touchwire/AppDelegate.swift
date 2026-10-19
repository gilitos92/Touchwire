import AppKit

/// Menu bar item showing Touchwire's state, with manual controls.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var touchwire: Touchwire!
    private var statusItem: NSStatusItem!
    private var settings: SettingsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        if LoginAgent.handOverIfNeeded() {
            NSApp.terminate(nil)
            return
        }
        _ = Updater.shared
        touchwire = Touchwire(config: Config.load())
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        settings = SettingsWindowController(touchwire: touchwire)
        touchwire.onStateChange = { [weak self] in self?.refreshIcon() }
        touchwire.start()
        refreshIcon()
    }

    private func refreshIcon() {
        let symbol: String
        switch touchwire.state {
        case .armed: symbol = touchwire.config.watchOnly ? "eye" : "lock.shield"
        case .tripped: symbol = "exclamationmark.shield"
        case .disarmed: symbol = "shield.slash"
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Touchwire \(touchwire.state.rawValue)")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let mode = touchwire.config.watchOnly ? "watch-only" : "locking"
        let since = DateFormatter.localizedString(from: touchwire.stateSince, dateStyle: .none, timeStyle: .short)
        menu.addItem(disabled("\(touchwire.state.rawValue.capitalized) since \(since) (\(mode))"))
        if let trip = touchwire.lastTrip { menu.addItem(disabled("Last trigger: \(trip)")) }
        if !touchwire.inputMonitoringActive { menu.addItem(disabled("Input Monitoring not granted")) }
        if let saved = touchwire.setupSavedAt {
            menu.addItem(disabled("Setup saved \(DateFormatter.localizedString(from: saved, dateStyle: .short, timeStyle: .short))"))
        } else {
            menu.addItem(disabled("No saved setup: using what was attached at start"))
        }
        for name in touchwire.unknownNames { menu.addItem(disabled("Not in setup: \(name)")) }
        menu.addItem(devicesItem())
        menu.addItem(.separator())
        menu.addItem(action("Arm Now", #selector(armNow)))
        menu.addItem(action("Disarm", #selector(disarmNow)))
        menu.addItem(action("Lock Now", #selector(lockNow)))
        menu.addItem(action("Save Current Setup as Normal", #selector(saveSetup)))
        menu.addItem(.separator())
        let updateItem = action("Check for Updates…", #selector(checkForUpdates))
        updateItem.isEnabled = Updater.shared.canCheck
        menu.addItem(updateItem)
        let settingsItem = action("Settings…", #selector(showSettings))
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(action("Quit Touchwire", #selector(quit)))
    }

    /// Submenu of the saved setup (checked when attached) and of what's attached but not saved.
    private func devicesItem() -> NSMenuItem {
        let saved = touchwire.savedEntries
        let unsaved = touchwire.unknownNames
        let submenu = NSMenu()
        submenu.addItem(disabled(touchwire.setupSavedAt == nil ? "Normal (attached at start)" : "Saved as normal"))
        for entry in saved {
            let item = disabled(entry.attached ? entry.name : "\(entry.name) (not attached)")
            item.state = entry.attached ? .on : .off
            item.indentationLevel = 1
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        submenu.addItem(disabled(unsaved.isEmpty ? "Not saved: none" : "Not saved (Save Current Setup adds these)"))
        for name in unsaved {
            let item = disabled(name)
            item.indentationLevel = 1
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: "Devices (\(saved.count) normal, \(unsaved.count) not saved)", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func armNow() { touchwire.arm(reason: "Armed from the menu.") }
    @objc private func disarmNow() { touchwire.disarm(reason: "Disarmed from the menu.") }
    @objc private func lockNow() { Locker.lockNow() }
    @objc private func saveSetup() { touchwire.saveCurrentSetup() }
    @objc private func showSettings() { settings.show() }
    @objc private func checkForUpdates() { Updater.shared.checkForUpdates() }
    @objc private func quit() {
        EventLog.shared.write("touchwire.quit", ["source": "menu"])
        // Tells the protection service this stop was intended, so it doesn't restart the app or lock the Mac.
        FileManager.default.createFile(atPath: Config.quitMarkerURL.path, contents: Data())
        NSApp.terminate(nil)
    }
}
