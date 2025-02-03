import Foundation
import os.log
import VPNLib

@objc final class XPCInterface: NSObject, VPNXPCProtocol, @unchecked Sendable {
    private var lockedManager: Manager?
    private let managerLock = NSLock()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "VPNXPCInterface")

    var manager: Manager? {
        get {
            managerLock.lock()
            defer { managerLock.unlock() }
            return lockedManager
        }
        set {
            managerLock.lock()
            defer { managerLock.unlock() }
            lockedManager = newValue
        }
    }

    func getPeerInfo(with reply: @escaping () -> Void) {
        // TODO: Retrieve from Manager
        reply()
    }

    func ping(with reply: @escaping () -> Void) {
        reply()
    }
}
