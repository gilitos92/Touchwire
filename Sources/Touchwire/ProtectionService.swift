import AppKit

/// Inspects the root protection service (a LaunchDaemon running `Touchwire --daemon`), and builds the commands that
/// install or remove it. Settings shows the commands, and runs them after macOS asks for an administrator password.
enum ProtectionService {
    static let label = "com.ggv.Touchwire.daemon"
    static let agentLabel = "com.ggv.Touchwire"
    static let plistPath = "/Library/LaunchDaemons/\(label).plist"
    /// A root-owned copy, so the service can't be changed without an administrator.
    static let appPath = "/Library/PrivilegedHelperTools/Touchwire.app"
    static var executablePath: String { "\(appPath)/Contents/MacOS/Touchwire" }
    static let logPath = "/Library/Logs/Touchwire/daemon.jsonl"

    enum Status: Equatable {
        case notInstalled
        case running(upToDate: Bool)
        case stopped
    }

    static var status: Status {
        guard FileManager.default.fileExists(atPath: plistPath) else { return .notInstalled }
        guard run("/bin/launchctl", ["print", "system/\(label)"]).output.contains("state = running") else { return .stopped }
        let installed = FileManager.default.contents(atPath: executablePath)
        let current = Bundle.main.executableURL.flatMap { FileManager.default.contents(atPath: $0.path) }
        return .running(upToDate: installed != nil && installed == current)
    }

    /// Terminal commands that install (or update) the service from this copy of the app.
    static var installCommands: String {
        let uid = getuid()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let arguments = [executablePath, "--daemon", "--uid", "\(uid)", "--home", home]
            .map { "<string>\($0)</string>" }.joined()
        let plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
            + "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\"><plist version=\"1.0\"><dict>"
            + "<key>Label</key><string>\(label)</string><key>ProgramArguments</key><array>\(arguments)</array>"
            + "<key>RunAtLoad</key><true/><key>KeepAlive</key><true/></dict></plist>"
        return """
        sudo mkdir -p /Library/PrivilegedHelperTools
        sudo rm -rf '\(appPath)'
        sudo cp -R '\(Bundle.main.bundlePath)' '\(appPath)'
        sudo chown -R root:wheel '\(appPath)'
        echo '\(plist)' | sudo tee '\(plistPath)' > /dev/null
        sudo chown root:wheel '\(plistPath)' && sudo chmod 644 '\(plistPath)'
        sudo launchctl bootout system/\(label) 2>/dev/null; sudo launchctl bootstrap system '\(plistPath)'
        """
    }

    static var uninstallCommands: String {
        """
        sudo launchctl bootout system/\(label)
        sudo rm -f '\(plistPath)'
        sudo rm -rf '\(appPath)'
        """
    }

    /// Runs the shown commands as root after macOS asks for an administrator's password. Returns an error, or nil.
    static func install() -> String? { runAsAdministrator(installCommands, prompt: "Touchwire wants to install its protection service.") }
    static func uninstall() -> String? { runAsAdministrator(uninstallCommands, prompt: "Touchwire wants to remove its protection service.") }

    private static func runAsAdministrator(_ commands: String, prompt: String) -> String? {
        // The script already runs as root, so drop the `sudo` the Terminal version needs.
        let script = commands.split(separator: "\n").map { line in
            line.replacingOccurrences(of: "sudo ", with: "")
        }.joined(separator: "\n")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("touchwire-service.sh")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try script.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            return "\(error)"
        }
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = "do shell script \"/bin/zsh \" & quoted form of \"\(file.path)\" with prompt \"\(prompt)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { return nil }
        // -128 is Cancel in the password dialog.
        if error[NSAppleScript.errorNumber] as? Int == -128 { return "Cancelled." }
        return error[NSAppleScript.errorMessage] as? String ?? "\(error)"
    }

    @discardableResult
    static func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
