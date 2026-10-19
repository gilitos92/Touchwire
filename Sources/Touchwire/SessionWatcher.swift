import AppKit

/// Watches the screen lock and whether this login session owns the screen (fast user switching).
final class SessionWatcher {
    enum Change: String { case locked, unlocked, sessionActive, sessionInactive }

    var onChange: ((Change) -> Void)?
    private var observers: [NSObjectProtocol] = []

    func start() {
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.onChange?(.locked)
        })
        observers.append(distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.onChange?(.unlocked)
        })
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onChange?(.sessionActive)
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onChange?(.sessionInactive)
        })
    }

    /// Reads the lock flag the window server keeps for this session.
    static var isLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}

/// Detects an active Screen Sharing or Remote Management viewer.
enum ScreenSharing {
    /// Established TCP connections to the VNC port (5900), from `netstat`, which lists sockets of every user.
    static func activeConnections() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        process.arguments = ["-anp", "tcp"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count >= 6, columns[5] == "ESTABLISHED", columns[3].hasSuffix(".5900") else { return nil }
            return "\(columns[4])"
        }
    }

    static var isActive: Bool { !activeConnections().isEmpty }
}
