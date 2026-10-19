import AppKit

/// The LaunchAgent that starts Touchwire at login and restarts it if it crashes or is killed (but not after Quit).
/// `Scripts/install.sh` writes the same file for development builds.
enum LoginAgent {
    static var plistURL: URL {
        Config.home.appendingPathComponent("Library/LaunchAgents/\(ProtectionService.agentLabel).plist")
    }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    /// Whether this process is the one launchd started from the agent.
    static var isRunningUnderAgent: Bool {
        ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == ProtectionService.agentLabel
    }

    /// Writes the agent for this copy of the app and hands over to it: launchd starts a new instance and this one quits.
    static func enable() throws {
        guard let executable = Bundle.main.executableURL?.path else { return }
        let plist: [String: Any] = [
            "Label": ProtectionService.agentLabel,
            "ProgramArguments": [executable],
            "LimitLoadToSessionType": "Aqua",
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive",
        ]
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
        // The new instance clears the marker; until then the protection service treats this handover as intended.
        FileManager.default.createFile(atPath: Config.quitMarkerURL.path, contents: Data())
        let domain = "gui/\(getuid())"
        ProtectionService.run("/bin/launchctl", ["bootout", "\(domain)/\(ProtectionService.agentLabel)"])
        ProtectionService.run("/bin/launchctl", ["bootstrap", domain, plistURL.path])
        EventLog.shared.write("loginagent.enabled", ["executable": executable])
        if !isRunningUnderAgent { NSApp.terminate(nil) }
    }

    /// A copy opened outside the agent (Sparkle's relaunch after an update, or a double-click) asks launchd to start
    /// the agent's copy instead, so restart-on-crash keeps working. Returns `true` when this copy should quit.
    static func handOverIfNeeded() -> Bool {
        guard isInstalled, !isRunningUnderAgent else { return false }
        EventLog.shared.write("loginagent.handover")
        let domain = "gui/\(getuid())"
        // Loads the agent if it was removed from launchd, then starts it if it isn't running.
        ProtectionService.run("/bin/launchctl", ["bootstrap", domain, plistURL.path])
        ProtectionService.run("/bin/launchctl", ["kickstart", "\(domain)/\(ProtectionService.agentLabel)"])
        return true
    }

    /// Removes the agent. If this process runs under it, launchd stops it, so Touchwire quits.
    static func disable() throws {
        FileManager.default.createFile(atPath: Config.quitMarkerURL.path, contents: Data())
        EventLog.shared.write("loginagent.disabled")
        try FileManager.default.removeItem(at: plistURL)
        // Last, since it may stop this process.
        ProtectionService.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(ProtectionService.agentLabel)"])
    }
}
