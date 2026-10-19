import Foundation
import IOKit

/// A device that appeared or disappeared after Touchwire started.
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
}

/// Watches IOKit for USB, HID (USB and Bluetooth keyboards, mice and the like) and Thunderbolt devices.
/// Everything present at start is the baseline; only later arrivals are reported as new.
final class DeviceWatcher {
    var onChange: ((DeviceChange) -> Void)?
    /// Devices that arrived after start and are still attached.
    private(set) var newDevices: [UInt64: DeviceChange] = [:]
    private var baselineCount = 0

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

    func start() {
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
                // Draining the iterator arms the notification; what it holds now is the baseline.
                drain(iterator, context: context)
                context.armed = true
            }
        }
        EventLog.shared.write("device.started", ["baselineCount": baselineCount])
    }

    fileprivate func drain(_ iterator: io_iterator_t, context: Context) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var registryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &registryID)
            if !context.armed {
                if context.added {
                    baselineCount += 1
                    EventLog.shared.write("device.baseline", ["family": context.family, "registryID": registryID,
                                                              "properties": Self.properties(of: service)])
                }
                continue
            }
            let change: DeviceChange
            if context.added {
                change = DeviceChange(added: true, family: context.family, registryID: registryID, properties: Self.properties(of: service))
                newDevices[registryID] = change
            } else {
                // A terminated service has lost most properties; reuse what was captured on arrival.
                let known = newDevices.removeValue(forKey: registryID)
                change = DeviceChange(added: false, family: context.family, registryID: registryID, properties: known?.properties ?? [:])
            }
            EventLog.shared.write(change.added ? "device.added" : "device.removed",
                                  ["family": change.family, "registryID": registryID, "properties": change.properties])
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
