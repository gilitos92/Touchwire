import Foundation
import IOKit

/// A device that appeared or disappeared.
struct DeviceChange {
    let added: Bool
    let family: String
    let registryID: UInt64
    let properties: [String: Any]

    var label: String {
        let name = properties["Product"] ?? properties["USB Product Name"] ?? properties["IORegistryEntryName"] ?? "Unknown device"
        let transport = properties["Transport"].map { " (\($0))" } ?? ""
        return "\(name)\(transport)"
    }

    /// Identity that survives replugging and restarts, unlike the registry ID.
    var key: String {
        let parts: [Any?] = [family, properties["VendorID"] ?? properties["idVendor"], properties["ProductID"] ?? properties["idProduct"],
                             properties["SerialNumber"] ?? properties["USB Serial Number"], properties["Transport"],
                             properties["Product"] ?? properties["USB Product Name"] ?? properties["IORegistryEntryName"]]
        return parts.map { $0.map { "\($0)" } ?? "" }.joined(separator: "|")
    }
}

/// Watches IOKit for USB, HID (USB and Bluetooth keyboards, mice and the like) and Thunderbolt devices.
/// A device is unknown when it isn't in the saved setup (or, before one is saved, wasn't attached at start).
final class DeviceWatcher {
    var onChange: ((DeviceChange) -> Void)?
    /// Every device attached now, by registry ID.
    private(set) var attached: [UInt64: DeviceChange] = [:]
    /// Device keys that count as normal.
    var allowed: Set<String> = []

    var unknownDevices: [DeviceChange] { attached.values.filter { !allowed.contains($0.key) } }
    var currentKeys: Set<String> { Set(attached.values.map(\.key)) }

    private let families = ["IOUSBHostDevice", "IOHIDDevice", "IOThunderboltSwitch"]
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var contexts: [Context] = []

    fileprivate final class Context {
        weak var watcher: DeviceWatcher?
        let family: String
        let added: Bool
        var armed = false
        init(watcher: DeviceWatcher, family: String, added: Bool) {
            self.watcher = watcher; self.family = family; self.added = added
        }
    }

    /// `allowed` nil means "whatever is attached now".
    func start(allowed saved: Set<String>?) {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .commonModes)
        for family in families {
            for added in [true, false] {
                let context = Context(watcher: self, family: family, added: added)
                contexts.append(context)
                var iterator: io_iterator_t = 0
                let type = added ? kIOFirstMatchNotification : kIOTerminatedNotification
                let result = IOServiceAddMatchingNotification(port, type, IOServiceMatching(family), deviceCallback,
                                                              Unmanaged.passUnretained(context).toOpaque(), &iterator)
                guard result == KERN_SUCCESS else {
                    EventLog.shared.write("device.watch_failed", ["family": family, "result": result])
                    continue
                }
                iterators.append(iterator)
                // Draining the iterator arms the notification; what it holds now is already attached.
                drain(iterator, context: context)
                context.armed = true
            }
        }
        allowed = saved ?? currentKeys
        EventLog.shared.write("device.started", ["attached": attached.count, "unknown": unknownDevices.map(\.label),
                                                 "usingSavedSetup": saved != nil])
    }

    fileprivate func drain(_ iterator: io_iterator_t, context: Context) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var registryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &registryID)
            let change: DeviceChange
            if context.added {
                change = DeviceChange(added: true, family: context.family, registryID: registryID, properties: Self.properties(of: service))
                attached[registryID] = change
            } else {
                // A terminated service has lost most properties; reuse what was captured on arrival.
                let known = attached.removeValue(forKey: registryID)
                change = DeviceChange(added: false, family: context.family, registryID: registryID, properties: known?.properties ?? [:])
            }
            guard context.armed else {
                EventLog.shared.write("device.present", ["family": change.family, "registryID": registryID, "properties": change.properties])
                continue
            }
            EventLog.shared.write(change.added ? "device.added" : "device.removed",
                                  ["family": change.family, "registryID": registryID, "properties": change.properties,
                                   "known": allowed.contains(change.key)])
            onChange?(change)
        }
    }

    private static let interestingKeys = ["Product", "USB Product Name", "Manufacturer", "Transport", "VendorID", "idVendor",
                                          "ProductID", "idProduct", "SerialNumber", "USB Serial Number", "PrimaryUsagePage",
                                          "PrimaryUsage", "Built-In", "DeviceUsagePairs"]

    private static func properties(of service: io_service_t) -> [String: Any] {
        var result: [String: Any] = [:]
        var name = [CChar](repeating: 0, count: 128)
        if IORegistryEntryGetName(service, &name) == KERN_SUCCESS {
            result["IORegistryEntryName"] = String(cString: name)
        }
        var className = [CChar](repeating: 0, count: 128)
        if IOObjectGetClass(service, &className) == KERN_SUCCESS {
            result["IOClass"] = String(cString: className)
        }
        for key in interestingKeys {
            guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { continue }
            if JSONSerialization.isValidJSONObject([value]) { result[key] = value } else { result[key] = "\(value)" }
        }
        return result
    }
}

private func deviceCallback(refcon: UnsafeMutableRawPointer?, iterator: io_iterator_t) {
    guard let refcon else { return }
    let context = Unmanaged<DeviceWatcher.Context>.fromOpaque(refcon).takeUnretainedValue()
    context.watcher?.drain(iterator, context: context)
}
