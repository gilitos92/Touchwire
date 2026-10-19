import AppKit

let arguments = CommandLine.arguments

func argument(after flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

if arguments.contains("--lock") {
    // Run by the protection service inside the user's session.
    exit(Locker.lockNow() ? 0 : 1)
} else if arguments.contains("--daemon") {
    guard let uid = argument(after: "--uid").flatMap(UInt32.init), let home = argument(after: "--home") else {
        FileHandle.standardError.write(Data("usage: Touchwire --daemon --uid <uid> --home <path>\n".utf8))
        exit(64)
    }
    Config.home = URL(fileURLWithPath: home, isDirectory: true)
    let daemon = Daemon(uid: uid)
    daemon.start()
    RunLoop.main.run()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
