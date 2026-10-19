import Foundation
import os

/// Appends one JSON object per line to `~/Library/Logs/Touchwire/events.jsonl`, and mirrors it to the unified log.
final class EventLog {
    static let shared = EventLog()

    let url: URL
    private let logger = Logger(subsystem: "com.ggv.Touchwire", category: "events")
    private let queue = DispatchQueue(label: "touchwire.eventlog")
    private let formatter = ISO8601DateFormatter()

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Touchwire", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("events.jsonl")
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func write(_ event: String, _ fields: [String: Any] = [:]) {
        var record = fields
        record["event"] = event
        record["time"] = formatter.string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
              var line = String(data: data, encoding: .utf8) else { return }
        logger.log("\(line, privacy: .public)")
        line += "\n"
        queue.async { [url] in
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
