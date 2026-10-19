import ApplicationServices
import CoreGraphics
import Foundation

/// One keyboard or mouse event, with the fields that say where it came from.
struct InputSample {
    enum Category: String { case keyboard, mouse }

    let category: Category
    let type: CGEventType
    /// Process that posted the event. Real hardware is expected to report 0; software reports its own ID.
    let sourcePID: Int64
    let sourceUserID: Int64
    /// 1 is the HID system state (hardware); other values are private or combined-session states.
    let sourceStateID: Int64
    let keyboardType: Int64
    let mouseSubtype: Int64

    /// The working hypothesis the watch-only phase is testing.
    var looksPhysical: Bool { sourcePID == 0 }

    var fields: [String: Any] {
        ["category": category.rawValue, "type": type.rawValue, "pid": sourcePID, "uid": sourceUserID,
         "stateID": sourceStateID, "keyboardType": keyboardType, "mouseSubtype": mouseSubtype,
         "looksPhysical": looksPhysical, "process": processPath(sourcePID)]
    }
}

/// Watches every keyboard and mouse event in this login session through an event tap.
/// Watching needs Input Monitoring. Blocking events needs Accessibility; without it the tap only listens.
final class InputWatcher {
    var onInput: ((InputSample) -> Void)?
    /// Asked for each event when the tap can block; `true` drops the event before any app sees it.
    var shouldBlock: ((InputSample) -> Bool)?
    private(set) var isRunning = false
    private(set) var canBlock = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    static var hasAccessibility: Bool { AXIsProcessTrusted() }
    static var hasInputMonitoring: Bool { CGPreflightListenEventAccess() }

    @discardableResult
    func start() -> Bool {
        stop()
        if !Self.hasInputMonitoring {
            CGRequestListenEventAccess()
        }
        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                                    .mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        func create(_ options: CGEventTapOptions) -> CFMachPort? {
            CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: options,
                              eventsOfInterest: mask, callback: inputTapCallback, userInfo: refcon)
        }
        let blocking = Self.hasAccessibility ? create(.defaultTap) : nil
        guard let tap = blocking ?? create(.listenOnly) else {
            EventLog.shared.write("input.tap_failed", ["inputMonitoring": Self.hasInputMonitoring])
            return false
        }
        self.tap = tap
        canBlock = blocking != nil
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        EventLog.shared.write("input.started", ["canBlock": canBlock, "inputMonitoring": Self.hasInputMonitoring])
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        isRunning = false
        canBlock = false
    }

    /// Returns `false` to drop the event.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            EventLog.shared.write("input.tap_reenabled", ["reason": type.rawValue])
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        let isKeyboard = type == .keyDown || type == .flagsChanged
        let sample = InputSample(
            category: isKeyboard ? .keyboard : .mouse,
            type: type,
            sourcePID: event.getIntegerValueField(.eventSourceUnixProcessID),
            sourceUserID: event.getIntegerValueField(.eventSourceUserID),
            sourceStateID: event.getIntegerValueField(.eventSourceStateID),
            keyboardType: isKeyboard ? event.getIntegerValueField(.keyboardEventKeyboardType) : 0,
            mouseSubtype: isKeyboard ? 0 : event.getIntegerValueField(.mouseEventSubtype)
        )
        onInput?(sample)
        return !(canBlock && shouldBlock?(sample) == true)
    }
}

private func inputTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let pass = Unmanaged<InputWatcher>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
    return pass ? Unmanaged.passUnretained(event) : nil
}
