import Foundation

/// The root protection service. It keeps watching devices when the Touchwire app isn't running, and if the app
/// stops without being quit from the menu, it restarts it, then locks the Mac if it still isn't back.
final class Daemon {
    private let uid: uid_t
    private let devices = DeviceWatcher()
    private var config = Config.load()
    private lazy var notifier = Notifier(config: config)
    private var timer: Timer?
    private var missingSince: Date?
    private var restartTried = false
    private var lockedForMissing = false
    private var notifiedQuit = false

    /// How long the app may be missing before a restart, and before a lock.
    private let restartAfter: TimeInterval = 10
    private let lockAfter: TimeInterval = 30

    init(uid: uid_t) { self.uid = uid }

    func start() {
        EventLog.shared.use(url: URL(fileURLWithPath: ProtectionService.logPath))
        EventLog.shared.enabled = config.loggingEnabled
        devices.onChange = { [weak self] in self?.handle(device: $0) }
        devices.start(allowed: Setup.load().map { Set($0.deviceKeys) })
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.check() }
        EventLog.shared.write("daemon.started", ["uid": uid, "home": Config.home.path])
    }

    private func handle(device change: DeviceChange) {
        guard change.added else { return }
        // The saved setup may have changed since start.
        if let setup = Setup.load() { devices.allowed = Set(setup.deviceKeys) }
        guard !devices.allowed.contains(change.key), !agentRunning else { return }
        notifier.send(kind: "daemon.device", title: "New device while Touchwire isn't running", message: change.label,
                      priority: "urgent", force: true)
    }

    private func check() {
        let latest = Config.load()
        if latest != config {
            config = latest
            notifier.update(config: latest)
            EventLog.shared.enabled = latest.loggingEnabled
        }
        // Logged out, or before login after a restart: there's no app to watch.
        guard guiSessionExists, !agentRunning else {
            reset()
            return
        }
        if FileManager.default.fileExists(atPath: Config.quitMarkerURL.path) {
            if !notifiedQuit {
                notifiedQuit = true
                EventLog.shared.write("daemon.agent_quit")
                notifier.send(kind: "daemon.quit", title: "Touchwire was quit", message: "Quit from its menu. Protection is off until it's opened again.", force: true)
            }
            return
        }
        let since = missingSince ?? Date()
        missingSince = since
        let missing = Date().timeIntervalSince(since)
        if missing >= restartAfter && !restartTried {
            restartTried = true
            EventLog.shared.write("daemon.agent_restart", ["missingSeconds": Int(missing)])
            restartAgent()
            notifier.send(kind: "daemon.restart", title: "Touchwire stopped", message: "It wasn't quit from its menu. Restarting it.", force: true)
        } else if missing >= lockAfter && !lockedForMissing {
            lockedForMissing = true
            EventLog.shared.write("daemon.agent_missing", ["missingSeconds": Int(missing), "lock": !config.watchOnly])
            if !config.watchOnly { lockUserSession() }
            notifier.send(kind: "daemon.missing", title: config.watchOnly ? "Touchwire won't start" : "Touchwire won't start, so the Mac was locked",
                          message: "It stopped and didn't come back after a restart.", priority: "urgent", force: true)
        }
    }

    private func reset() {
        missingSince = nil
        restartTried = false
        lockedForMissing = false
        if !FileManager.default.fileExists(atPath: Config.quitMarkerURL.path) { notifiedQuit = false }
    }

    private var guiSessionExists: Bool {
        ProtectionService.run("/bin/launchctl", ["print", "gui/\(uid)"]).status == 0
    }

    private var agentRunning: Bool {
        ProtectionService.run("/bin/launchctl", ["print", "gui/\(uid)/\(ProtectionService.agentLabel)"]).output.contains("state = running")
    }

    private func restartAgent() {
        let plist = Config.home.appendingPathComponent("Library/LaunchAgents/\(ProtectionService.agentLabel).plist").path
        // Bootstrapping fails harmlessly when the agent is still loaded; kickstart then starts it.
        ProtectionService.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plist])
        ProtectionService.run("/bin/launchctl", ["kickstart", "gui/\(uid)/\(ProtectionService.agentLabel)"])
    }

    /// The lock has to run inside the user's session, so run this binary's `--lock` mode there.
    private func lockUserSession() {
        let result = ProtectionService.run("/bin/launchctl", ["asuser", "\(uid)", ProtectionService.executablePath, "--lock"])
        EventLog.shared.write("daemon.lock", ["status": result.status, "output": result.output])
    }
}
