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

    func getPeerState(with reply: @escaping (Data?) -> Void) {
        let reply = CallbackWrapper(reply)
        Task {
            let data = try? await manager?.getPeerState().serializedData()
            reply(data)
        }
    }

    func ping(with reply: @escaping () -> Void) {
        reply()
    }
}
