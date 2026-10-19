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

/// Watches every keyboard and mouse event in this login session through a listen-only event tap.
/// Needs Input Monitoring permission.
final class InputWatcher {
    var onInput: ((InputSample) -> Void)?
    private(set) var isRunning = false
    private var tap: CFMachPort?

    func start() -> Bool {
        if !CGPreflightListenEventAccess() {
            CGRequestListenEventAccess()
        }
        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                                    .mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: inputTapCallback, userInfo: refcon) else {
            EventLog.shared.write("input.tap_failed", ["listenAccess": CGPreflightListenEventAccess()])
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        EventLog.shared.write("input.started")
        return true
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            EventLog.shared.write("input.tap_reenabled", ["reason": type.rawValue])
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
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
    }
}

private func inputTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon {
        Unmanaged<InputWatcher>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
