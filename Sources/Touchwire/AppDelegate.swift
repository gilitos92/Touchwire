import AppKit

/// Menu bar item showing Touchwire's state, with manual controls.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var touchwire: Touchwire!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        touchwire = Touchwire(config: Config.load())
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
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
        menu.addItem(.separator())
        menu.addItem(action("Arm Now", #selector(armNow)))
        menu.addItem(action("Disarm", #selector(disarmNow)))
        menu.addItem(action("Lock Now", #selector(lockNow)))
        menu.addItem(action("Save Current Setup as Normal", #selector(saveSetup)))
        menu.addItem(.separator())
        menu.addItem(action("Send Test Notification", #selector(testNotification)))
        menu.addItem(action("Reload Config", #selector(reloadConfig)))
        menu.addItem(action("Show Log in Finder", #selector(showLog)))
        menu.addItem(.separator())
        menu.addItem(action("Quit Touchwire", #selector(quit)))
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
    @objc private func testNotification() { touchwire.sendTestNotification() }
    @objc private func reloadConfig() { touchwire.reload(config: Config.load()) }
    @objc private func showLog() { NSWorkspace.shared.activateFileViewerSelecting([EventLog.shared.url]) }
    @objc private func quit() {
        EventLog.shared.write("touchwire.quit", ["source": "menu"])
        NSApp.terminate(nil)
    }
}
