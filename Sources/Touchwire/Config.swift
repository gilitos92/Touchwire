import Foundation

/// Settings read from `~/Library/Application Support/Touchwire/config.json`.
/// A missing file or key falls back to the defaults below.
struct Config: Codable {
    /// `true` logs and notifies what would lock the Mac, without locking it.
    var watchOnly = true
    /// ntfy server and topic for push notifications. An empty topic turns notifications off.
    var ntfyServer = "https://ntfy.sh"
    var ntfyTopic = ""
    /// Re-arm after this many seconds without physical input while disarmed.
    var rearmAfterIdleSeconds: TimeInterval = 600
    /// Send at most one notification per trigger kind in this window, so mouse movement doesn't spam.
    var notifyCooldownSeconds: TimeInterval = 300
    /// Remind once the Mac has stayed disarmed this long.
    var disarmedReminderSeconds: TimeInterval = 3 * 3600

    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Touchwire", isDirectory: true)
    static let url = directory.appendingPathComponent("config.json")

    static func load() -> Config {
        guard let data = try? Data(contentsOf: url) else { return Config() }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            EventLog.shared.write("config.invalid", ["error": "\(error)"])
            return Config()
        }
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        watchOnly = try c.decodeIfPresent(Bool.self, forKey: .watchOnly) ?? d.watchOnly
        ntfyServer = try c.decodeIfPresent(String.self, forKey: .ntfyServer) ?? d.ntfyServer
        ntfyTopic = try c.decodeIfPresent(String.self, forKey: .ntfyTopic) ?? d.ntfyTopic
        rearmAfterIdleSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .rearmAfterIdleSeconds) ?? d.rearmAfterIdleSeconds
        notifyCooldownSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .notifyCooldownSeconds) ?? d.notifyCooldownSeconds
        disarmedReminderSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .disarmedReminderSeconds) ?? d.disarmedReminderSeconds
    }
}
