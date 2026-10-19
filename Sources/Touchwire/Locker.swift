import Foundation

/// Locks the screen at once, whatever the screen-lock setting says.
enum Locker {
    private typealias LockFunction = @convention(c) () -> Int32

    /// `SACLockScreenImmediate` is the private function behind Control-Command-Q.
    private static let lockFunction: LockFunction? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
              let symbol = dlsym(handle, "SACLockScreenImmediate") else { return nil }
        return unsafeBitCast(symbol, to: LockFunction.self)
    }()

    static var isAvailable: Bool { lockFunction != nil }

    @discardableResult
    static func lockNow() -> Bool {
        guard let lockFunction else {
            EventLog.shared.write("lock.unavailable")
            return false
        }
        let result = lockFunction()
        EventLog.shared.write("lock.requested", ["result": result])
        return result == 0
    }
}
