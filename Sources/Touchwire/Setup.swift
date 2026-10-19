import Foundation

/// The "normal" devices and displays, saved from the menu with Save Current Setup as Normal.
struct Setup: Codable {
    var savedAt: Date
    var deviceKeys: [String]
    var displayKeys: [String]
    /// Human-readable names, for reading the file.
    var deviceNames: [String]
    var displayNames: [String]

    static let url = Config.directory.appendingPathComponent("setup.json")

    static func load() -> Setup? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Setup.self, from: data)
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Config.directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Self.url, options: .atomic)
    }
}
