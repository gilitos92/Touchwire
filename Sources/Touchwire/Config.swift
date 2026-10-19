import Foundation

/// Settings stored in `~/Library/Application Support/Touchwire/config.json` and edited in the Settings window.
/// A missing file or key falls back to the defaults below.
struct Config: Codable, Equatable {
    /// `true` logs and notifies what would lock the Mac, without locking it.
    var watchOnly = true
    /// Swallow the physical keystroke or click that trips the wire, so it never reaches an app. Needs Accessibility.
    var blockFirstInput = true
    /// ntfy server and topic for push notifications. An empty topic turns notifications off.
    var ntfyServer = "https://ntfy.sh"
    var ntfyTopic = ""
    /// Re-arm after this many seconds without physical input while disarmed.
    var rearmAfterIdleSeconds: TimeInterval = 600
    /// Send at most one notification per trigger kind in this window, so mouse movement doesn't spam.
    var notifyCooldownSeconds: TimeInterval = 300
    /// Remind once the Mac has stayed disarmed this long.
    var disarmedReminderSeconds: TimeInterval = 3 * 3600
    /// Write events to `~/Library/Logs/Touchwire/events.jsonl`.
    var loggingEnabled = true

    /// The protection service runs as root, so it points this at the user's home instead of its own.
    nonisolated(unsafe) static var home = FileManager.default.homeDirectoryForCurrentUser
    static var directory: URL { home.appendingPathComponent("Library/Application Support/Touchwire", isDirectory: true) }
    static var url: URL { directory.appendingPathComponent("config.json") }
    /// Written when Touchwire is quit from the menu, so the protection service knows the stop was intended.
    static var quitMarkerURL: URL { directory.appendingPathComponent("quit-requested") }

    static func load(from url: URL = url) -> Config {
        guard let data = try? Data(contentsOf: url) else { return Config() }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            EventLog.shared.write("config.invalid", ["error": "\(error)"])
            return Config()
        }
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Self.url, options: .atomic)
        // The ntfy topic works like a password.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.url.path)
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        watchOnly = try c.decodeIfPresent(Bool.self, forKey: .watchOnly) ?? d.watchOnly
        blockFirstInput = try c.decodeIfPresent(Bool.self, forKey: .blockFirstInput) ?? d.blockFirstInput
        ntfyServer = try c.decodeIfPresent(String.self, forKey: .ntfyServer) ?? d.ntfyServer
        ntfyTopic = try c.decodeIfPresent(String.self, forKey: .ntfyTopic) ?? d.ntfyTopic
        rearmAfterIdleSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .rearmAfterIdleSeconds) ?? d.rearmAfterIdleSeconds
        notifyCooldownSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .notifyCooldownSeconds) ?? d.notifyCooldownSeconds
        disarmedReminderSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .disarmedReminderSeconds) ?? d.disarmedReminderSeconds
        loggingEnabled = try c.decodeIfPresent(Bool.self, forKey: .loggingEnabled) ?? d.loggingEnabled
    }
}
