import Foundation
import os.log
import VPNLib
import VPNXPC

@objc final class XPCInterface: NSObject, VPNXPCProtocol, @unchecked Sendable {
    private var manager: Manager?
    private let managerLock = NSLock()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "VPNXPCInterface")

    func setManager(_ newManager: Manager?) {
        managerLock.lock()
        defer { managerLock.unlock() }
        manager = newManager
    }

    func getManager() -> Manager? {
        managerLock.lock()
        defer { managerLock.unlock() }
        let m = manager

        return m
    }

    func getPeerInfo(with reply: @escaping () -> Void) {
        reply()
    }

    func ping(with reply: @escaping () -> Void) {
        reply()
    }
}
