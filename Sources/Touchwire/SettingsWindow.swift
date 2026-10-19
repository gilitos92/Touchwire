import AppKit
import SwiftUI

/// State behind the Settings window. Every change is saved and applied at once.
final class SettingsModel: ObservableObject {
    @Published var config: Config {
        didSet { if config != oldValue { save() } }
    }
    @Published var serviceStatus = ProtectionService.status
    @Published var serviceMessage: String?
    @Published var hasAccessibility = InputWatcher.hasAccessibility
    @Published var hasInputMonitoring = InputWatcher.hasInputMonitoring
    @Published var canBlock = false
    @Published var startsAtLogin = LoginAgent.isInstalled

    let touchwire: Touchwire

    init(touchwire: Touchwire) {
        self.touchwire = touchwire
        config = touchwire.config
        canBlock = touchwire.inputCanBlock
    }

    func refresh() {
        config = touchwire.config
        serviceStatus = ProtectionService.status
        hasAccessibility = InputWatcher.hasAccessibility
        hasInputMonitoring = InputWatcher.hasInputMonitoring
        canBlock = touchwire.inputCanBlock
        startsAtLogin = LoginAgent.isInstalled
    }

    func setStartsAtLogin(_ on: Bool) {
        do {
            if on { try LoginAgent.enable() } else { try LoginAgent.disable() }
        } catch {
            serviceMessage = "Couldn't change Start at Login: \(error.localizedDescription)"
        }
        refresh()
    }

    func newTopic() {
        config.ntfyTopic = "touchwire-" + (0..<12).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    private func save() {
        do {
            try config.save()
            touchwire.apply(config: config)
        } catch {
            serviceMessage = "Couldn't save settings: \(error.localizedDescription)"
        }
    }

    func restartInput() {
        touchwire.restartInput()
        refresh()
    }

    func installService() {
        serviceMessage = ProtectionService.install() ?? "Installed."
        refresh()
    }

    func uninstallService() {
        serviceMessage = ProtectionService.uninstall() ?? "Removed."
        refresh()
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        serviceMessage = "Commands copied."
    }

    func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Binds a field stored in seconds to a control showing another unit.
    func seconds(_ keyPath: WritableKeyPath<Config, TimeInterval>, per unit: Double) -> Binding<Int> {
        Binding(get: { Int((self.config[keyPath: keyPath] / unit).rounded()) },
                set: { self.config[keyPath: keyPath] = Double($0) * unit })
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var showCommands = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Start at login and keep running", isOn: Binding(get: { model.startsAtLogin },
                                                                       set: { model.setStartsAtLogin($0) }))
                Text("Restarts Touchwire if it crashes or is killed, but not after Quit. Turning it off quits Touchwire.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Protection") {
                Toggle("Lock the Mac when triggered", isOn: Binding(get: { !model.config.watchOnly },
                                                                  set: { model.config.watchOnly = !$0 }))
                Text(model.config.watchOnly ? "Watch-only: triggers notify you but don't lock." : "Physical contact locks the Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Block the physical input that triggers it", isOn: $model.config.blockFirstInput)
                Text("The first keystroke or click never reaches an app. Needs Accessibility.")
                    .font(.caption).foregroundStyle(.secondary)
                Stepper("Re-arm after \(model.seconds(\.rearmAfterIdleSeconds, per: 60).wrappedValue) min without physical input",
                        value: model.seconds(\.rearmAfterIdleSeconds, per: 60), in: 1...240)
                Stepper("Remind me after \(model.seconds(\.disarmedReminderSeconds, per: 3600).wrappedValue) h disarmed",
                        value: model.seconds(\.disarmedReminderSeconds, per: 3600), in: 1...48)
            }

            Section("Permissions") {
                permissionRow("Input Monitoring", granted: model.hasInputMonitoring, anchor: "Privacy_ListenEvent",
                              detail: "Needed to see keyboard and mouse input.")
                permissionRow("Accessibility", granted: model.hasAccessibility, anchor: "Privacy_Accessibility",
                              detail: model.canBlock ? "Input blocking is active." : "Needed to block input.")
                Button("Restart Input Watch") { model.restartInput() }
                    .help("Use after granting a permission.")
            }

            Section("Notifications (ntfy)") {
                TextField("Server", text: $model.config.ntfyServer)
                HStack {
                    TextField("Topic", text: $model.config.ntfyTopic)
                    Button("New Random Topic") { model.newTopic() }
                }
                Text("Follow this topic in the ntfy app. Anyone with the topic can read the alerts.")
                    .font(.caption).foregroundStyle(.secondary)
                Stepper("At most one alert per trigger every \(model.seconds(\.notifyCooldownSeconds, per: 60).wrappedValue) min",
                        value: model.seconds(\.notifyCooldownSeconds, per: 60), in: 1...60)
                Button("Send Test Notification") { model.touchwire.sendTestNotification() }
            }

            Section("Protection Service") {
                LabeledContent("Status", value: statusText)
                Text("A root background service. It watches devices while the app isn't running, restarts the app if it's stopped without Quit, and locks the Mac if it doesn't come back.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(installTitle) { model.installService() }
                    if model.serviceStatus != .notInstalled {
                        Button("Remove…") { model.uninstallService() }
                    }
                    Spacer()
                    Button(showCommands ? "Hide Commands" : "Show Commands") { showCommands.toggle() }
                }
                if showCommands {
                    commandBlock(ProtectionService.installCommands, title: "Install")
                    commandBlock(ProtectionService.uninstallCommands, title: "Remove")
                }
                if let message = model.serviceMessage {
                    Text(message).font(.caption)
                }
            }

            Section("Logging") {
                Toggle("Keep an event log", isOn: $model.config.loggingEnabled)
                HStack {
                    Text(EventLog.shared.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([EventLog.shared.url]) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .frame(minHeight: 520)
    }

    private var statusText: String {
        switch model.serviceStatus {
        case .notInstalled: return "Not installed"
        case .stopped: return "Installed, not running"
        case .running(let upToDate): return upToDate ? "Running" : "Running an older version"
        }
    }

    private var installTitle: String {
        switch model.serviceStatus {
        case .notInstalled: return "Install…"
        case .running(upToDate: true): return "Reinstall…"
        default: return "Update…"
        }
    }

    private func permissionRow(_ name: String, granted: Bool, anchor: String, detail: String) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
            VStack(alignment: .leading) {
                Text(name)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("Open Settings") { model.openPrivacyPane(anchor) } }
        }
    }

    private func commandBlock(_ commands: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption.bold())
                Spacer()
                Button("Copy") { model.copy(commands) }.controlSize(.small)
            }
            Text(commands)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Owns the single Settings window.
final class SettingsWindowController {
    private var window: NSWindow?
    private let model: SettingsModel

    init(touchwire: Touchwire) { model = SettingsModel(touchwire: touchwire) }

    func show() {
        model.refresh()
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = "Touchwire Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
