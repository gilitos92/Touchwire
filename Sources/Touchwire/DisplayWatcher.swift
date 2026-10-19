import AppKit
import CoreGraphics

/// One display's identity, as macOS reports it.
struct DisplayInfo: Hashable {
    let id: CGDirectDisplayID
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32
    let name: String

    /// Identity without the display ID, which can change across reconnects.
    var key: String { "\(vendor)-\(model)-\(serial)" }

    var fields: [String: Any] {
        ["id": id, "vendor": vendor, "model": model, "serial": serial, "name": name]
    }
}

/// Watches display connections. A display is unknown when it isn't in the saved setup
/// (or, before one is saved, wasn't connected at start).
final class DisplayWatcher {
    /// Called with the displays that aren't allowed, and every display connected now.
    var onChange: ((_ unknown: [DisplayInfo], _ current: [DisplayInfo]) -> Void)?
    var allowed: Set<String> = []
    private var lastReported: Set<String> = []

    var unknownDisplays: [DisplayInfo] { Self.currentDisplays().filter { !allowed.contains($0.key) } }

    /// `allowed` nil means "whatever is connected now".
    func start(allowed saved: Set<String>?) {
        let current = Self.currentDisplays()
        allowed = saved ?? Set(current.map(\.key))
        lastReported = Set(current.map(\.key))
        EventLog.shared.write("display.started", ["displays": current.map(\.fields), "usingSavedSetup": saved != nil])
        CGDisplayRegisterReconfigurationCallback(displayCallback, Unmanaged.passUnretained(self).toOpaque())
    }

    fileprivate func reconfigured() {
        let current = Self.currentDisplays()
        let keys = Set(current.map(\.key))
        guard keys != lastReported else { return }
        lastReported = keys
        let unknown = current.filter { !allowed.contains($0.key) }
        EventLog.shared.write("display.changed", ["displays": current.map(\.fields), "unknown": unknown.map(\.fields)])
        onChange?(unknown, current)
    }

    static func currentDisplays() -> [DisplayInfo] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        let names = Dictionary(NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, String)? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            return (id, screen.localizedName)
        }, uniquingKeysWith: { a, _ in a })
        return ids.prefix(Int(count)).map { id in
            DisplayInfo(id: id, vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                        serial: CGDisplaySerialNumber(id), name: names[id] ?? "")
        }
    }
}

private func displayCallback(display: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags, userInfo: UnsafeMutableRawPointer?) {
    // The callback fires before and after each change; act once it has settled.
    guard let userInfo, !flags.contains(.beginConfigurationFlag) else { return }
    let watcher = Unmanaged<DisplayWatcher>.fromOpaque(userInfo).takeUnretainedValue()
    DispatchQueue.main.async { watcher.reconfigured() }
}
