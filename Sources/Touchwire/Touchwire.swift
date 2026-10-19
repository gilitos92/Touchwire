import Foundation

/// Decides when to lock, disarm and re-arm, from what the watchers report.
///
/// - Armed: physical input, a new device or an unknown display trips it.
/// - Tripped: the Mac is locked. Unlocking at the Mac disarms it; unlocking through Screen Sharing re-arms it.
/// - Disarmed: someone who knows the password is at the Mac. It re-arms after idle time, when new devices are
///   unplugged, or from the menu.
///
/// In watch-only mode a trip only logs and notifies "would lock"; the state stays armed.
final class Touchwire {
    enum State: String { case armed, tripped, disarmed }

    private(set) var state: State = .armed { didSet { if state != oldValue { stateChanged() } } }
    private(set) var stateSince = Date()
    private(set) var lastTrip: String?
    var onStateChange: (() -> Void)?

    private(set) var config: Config
    private let notifier: Notifier
    private let input = InputWatcher()
    private let devices = DeviceWatcher()
    private let displays = DisplayWatcher()
    private let session = SessionWatcher()
    private var lastPhysicalInput = Date()
    private var remindedDisarmed = false
    private var timer: Timer?
    private var lastInputLog: [String: Date] = [:]
    private var lastWouldLockLog: [String: Date] = [:]
    /// The last software input source that wasn't this app, to check at unlock whether it's still running.
    private var lastSoftwareInput: (pid: Int64, path: String, time: Date)?

    var inputMonitoringActive: Bool { input.isRunning }
    var setupSavedAt: Date? { Setup.load()?.savedAt }
    /// Devices and displays attached now that aren't in the saved setup.
    var unknownNames: [String] {
        Array(Set(devices.unknownDevices.map(\.label))).sorted() + displays.unknownDisplays.map { $0.name.isEmpty ? "Display \($0.key)" : $0.name }
    }

    init(config: Config) {
        self.config = config
        notifier = Notifier(config: config)
    }

    func start() {
        input.onInput = { [weak self] in self?.handle(input: $0) }
        devices.onChange = { [weak self] in self?.handle(device: $0) }
        displays.onChange = { [weak self] unknown, _ in self?.handle(unknownDisplays: unknown) }
        session.onChange = { [weak self] in self?.handle(session: $0) }

        let setup = Setup.load()
        _ = input.start()
        devices.start(allowed: setup.map { Set($0.deviceKeys) })
        displays.start(allowed: setup.map { Set($0.displayKeys) })
        session.start()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.tick() }

        EventLog.shared.write("touchwire.started", ["watchOnly": config.watchOnly, "inputMonitoring": input.isRunning,
                                                   "lockAvailable": Locker.isAvailable, "locked": SessionWatcher.isLocked])
        notifier.send(kind: "started", title: "Touchwire started",
                      message: config.watchOnly ? "Watch-only: it notifies but won't lock." : "Armed: it locks on physical contact.",
                      priority: "default", force: true)
        // Something not in the saved setup may have been plugged in while Touchwire wasn't running.
        if !unknownNames.isEmpty {
            trip(kind: "device", reason: "Not in the saved setup: \(unknownNames.joined(separator: ", "))")
        }
    }

    /// Makes everything attached now the normal setup.
    func saveCurrentSetup() {
        let current = DisplayWatcher.currentDisplays()
        let setup = Setup(savedAt: Date(), deviceKeys: devices.currentKeys.sorted(), displayKeys: current.map(\.key).sorted(),
                          deviceNames: Array(Set(devices.attached.values.map(\.label))).sorted(), displayNames: current.map(\.name))
        do {
            try setup.save()
            devices.allowed = Set(setup.deviceKeys)
            displays.allowed = Set(setup.displayKeys)
            EventLog.shared.write("setup.saved", ["devices": setup.deviceNames, "displays": setup.displayNames])
        } catch {
            EventLog.shared.write("setup.save_failed", ["error": "\(error)"])
        }
        onStateChange?()
    }

    func reload(config: Config) {
        self.config = config
        notifier.update(config: config)
        EventLog.shared.write("config.reloaded", ["watchOnly": config.watchOnly])
        onStateChange?()
    }

    // MARK: Manual controls

    func arm(reason: String) {
        EventLog.shared.write("touchwire.armed", ["reason": reason])
        state = .armed
        notifier.send(kind: "armed", title: "Touchwire armed", message: reason, priority: "default", force: true)
    }

    func disarm(reason: String) {
        EventLog.shared.write("touchwire.disarmed", ["reason": reason])
        lastPhysicalInput = Date()
        state = .disarmed
        notifier.send(kind: "disarmed", title: "Touchwire disarmed", message: reason, priority: "default", force: true)
    }

    func sendTestNotification() {
        notifier.send(kind: "test", title: "Touchwire test", message: "Notifications work.", priority: "default", force: true)
    }

    // MARK: Events

    private func handle(input sample: InputSample) {
        logSampled(sample)
        guard sample.looksPhysical else {
            if sample.sourcePID != Int64(getpid()) {
                lastSoftwareInput = (sample.sourcePID, processPath(sample.sourcePID), Date())
            }
            return
        }
        lastPhysicalInput = Date()
        if state == .armed {
            trip(kind: "input.\(sample.category.rawValue)", reason: "Physical \(sample.category.rawValue) input")
        }
    }

    private func handle(device change: DeviceChange) {
        let known = devices.allowed.contains(change.key)
        if change.added {
            if !known && (state == .armed || SessionWatcher.isLocked) {
                trip(kind: "device", reason: "New device: \(change.label)")
            }
        } else if !known && state == .disarmed && devices.unknownDevices.isEmpty {
            arm(reason: "The added devices were unplugged.")
        }
    }

    private func handle(unknownDisplays: [DisplayInfo]) {
        guard !unknownDisplays.isEmpty else { return }
        let names = unknownDisplays.map { $0.name.isEmpty ? "display \($0.key)" : $0.name }.joined(separator: ", ")
        if state == .armed || SessionWatcher.isLocked {
            trip(kind: "display", reason: "New display: \(names)")
        }
    }

    private func handle(session change: SessionWatcher.Change) {
        var fields: [String: Any] = ["change": change.rawValue, "state": state.rawValue]
        guard change == .unlocked else {
            EventLog.shared.write("session.\(change.rawValue)", fields)
            return
        }
        let remote = ScreenSharing.isActive
        fields["screenSharing"] = ScreenSharing.sessionProcesses()
        if let last = lastSoftwareInput {
            fields["lastSoftwareInput"] = ["pid": last.pid, "path": last.path, "secondsAgo": Int(Date().timeIntervalSince(last.time)),
                                           "stillRunning": !processPath(last.pid).isEmpty]
        }
        fields["classifiedAs"] = remote ? "remote" : "local"
        EventLog.shared.write("session.unlocked", fields)
        if remote {
            arm(reason: "Unlocked through Screen Sharing.")
        } else {
            disarm(reason: "Unlocked at the Mac.")
        }
    }

    private func trip(kind: String, reason: String) {
        lastTrip = reason
        if config.watchOnly {
            // Mouse movement trips on every event; log each kind at most every 10 seconds.
            let now = Date()
            if now.timeIntervalSince(lastWouldLockLog[kind] ?? .distantPast) >= 10 {
                lastWouldLockLog[kind] = now
                EventLog.shared.write("trip.would_lock", ["kind": kind, "reason": reason])
            }
            notifier.send(kind: kind, title: "Touchwire would lock", message: reason)
            onStateChange?()
            return
        }
        guard state != .tripped || !SessionWatcher.isLocked else {
            notifier.send(kind: kind, title: "Touchwire: activity while locked", message: reason)
            return
        }
        EventLog.shared.write("trip.locked", ["kind": kind, "reason": reason])
        Locker.lockNow()
        state = .tripped
        notifier.send(kind: kind, title: "Touchwire locked the Mac", message: reason, priority: "urgent", force: true)
    }

    private func tick() {
        guard state == .disarmed else { return }
        let idle = Date().timeIntervalSince(lastPhysicalInput)
        if idle >= config.rearmAfterIdleSeconds {
            arm(reason: "No physical input for \(Int(idle / 60)) minutes.")
        } else if !remindedDisarmed, Date().timeIntervalSince(stateSince) >= config.disarmedReminderSeconds {
            remindedDisarmed = true
            notifier.send(kind: "reminder", title: "Touchwire still disarmed",
                          message: "Disarmed for \(Int(Date().timeIntervalSince(stateSince) / 3600)) hours.", force: true)
        }
    }

    private func stateChanged() {
        stateSince = Date()
        remindedDisarmed = false
        onStateChange?()
    }

    /// Logs a sample when its source changes, or every 5 seconds per source, so mouse movement doesn't flood the log.
    private func logSampled(_ sample: InputSample) {
        let signature = "\(sample.category.rawValue)-\(sample.sourcePID)-\(sample.sourceStateID)"
        let now = Date()
        if let last = lastInputLog[signature], now.timeIntervalSince(last) < 5 { return }
        lastInputLog[signature] = now
        var fields = sample.fields
        fields["state"] = state.rawValue
        fields["screenSharing"] = ScreenSharing.sessionProcesses()
        EventLog.shared.write("input.sample", fields)
    }
}
