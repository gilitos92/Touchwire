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
///
/// Two signals, both logged so the watch-only phase can show which one is reliable:
/// an established connection to the VNC port (5900), and a running Screen Sharing session process.
enum ScreenSharing {
    /// Always running, connected or not, so it says nothing about a viewer.
    private static let idleProcesses: Set<String> = ["ScreenSharingSubscriber"]

    /// Remote addresses connected to port 5900, from `netstat`, which lists sockets of every user.
    static func activeConnections() -> [String] {
        run("/usr/sbin/netstat", ["-anp", "tcp"]).split(separator: "\n").compactMap { line in
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count >= 6, columns[5] == "ESTABLISHED", columns[3].hasSuffix(".5900") else { return nil }
            return "\(columns[4])"
        }
    }

    /// Names of running Screen Sharing processes that only exist during a session.
    static func sessionProcesses() -> [String] {
        let names = run("/bin/ps", ["-axo", "comm="]).split(separator: "\n").map { ($0 as Substring).split(separator: "/").last.map(String.init) ?? "" }
        return Array(Set(names.filter { $0.lowercased().contains("screensharing") && !idleProcesses.contains($0) })).sorted()
    }

    static var isActive: Bool { !activeConnections().isEmpty || !sessionProcesses().isEmpty }

    static var snapshot: [String: Any] { ["connections": activeConnections(), "processes": sessionProcesses()] }

    private static func run(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Path of a running process's executable, or "" if it has exited.
func processPath(_ pid: Int64) -> String {
    guard pid > 0 else { return "" }
    var buffer = [CChar](repeating: 0, count: 4096)
    let length = proc_pidpath(Int32(pid), &buffer, UInt32(buffer.count))
    return length > 0 ? String(cString: buffer) : ""
}
