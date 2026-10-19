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

/// Watches display connections. The displays present at start are the allowed set (the dummy HDMI plug).
final class DisplayWatcher {
    /// Called with displays that weren't in the allowed set, and whether the set is back to normal.
    var onChange: ((_ unknown: [DisplayInfo], _ current: [DisplayInfo]) -> Void)?
    private(set) var allowed: Set<String> = []
    private var lastReported: Set<String> = []

    func start() {
        let current = Self.currentDisplays()
        allowed = Set(current.map(\.key))
        EventLog.shared.write("display.baseline", ["displays": current.map(\.fields)])
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
