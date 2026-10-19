import Foundation

/// Sends push notifications through ntfy (https://ntfy.sh), with a per-kind cooldown.
final class Notifier {
    private var config: Config
    private var lastSent: [String: Date] = [:]

    init(config: Config) { self.config = config }

    func update(config: Config) { self.config = config }

    /// `kind` groups notifications for the cooldown; `force` skips it.
    func send(kind: String, title: String, message: String, priority: String = "high", force: Bool = false) {
        let now = Date()
        if !force, let last = lastSent[kind], now.timeIntervalSince(last) < config.notifyCooldownSeconds {
            return
        }
        lastSent[kind] = now
        guard !config.ntfyTopic.isEmpty,
              let url = URL(string: config.ntfyServer)?.appendingPathComponent(config.ntfyTopic) else {
            EventLog.shared.write("notify.skipped", ["kind": kind, "reason": "no ntfy topic"])
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(message.utf8)
        request.setValue(title, forHTTPHeaderField: "Title")
        request.setValue(priority, forHTTPHeaderField: "Priority")
        request.setValue("rotating_light", forHTTPHeaderField: "Tags")
        URLSession.shared.dataTask(with: request) { _, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            EventLog.shared.write("notify.sent", ["kind": kind, "status": status, "error": error.map { "\($0)" } ?? ""])
        }.resume()
    }
}
