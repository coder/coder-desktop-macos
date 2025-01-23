import Foundation
import os.log
import VPNXPC

final class CallbackWrapper: @unchecked Sendable {
    private let block: (NSError?) -> Void

    init(_ block: @escaping (NSError?) -> Void) {
        self.block = block
    }

    func call(_ error: NSError?) {
        // Just forward to the original block
        block(error)
    }
}

@objc final class VPNXPCInterface: NSObject, VPNXPCProtocol, @unchecked Sendable {
    private var manager: Manager?
    private let managerLock = NSLock()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "VPNXPCInterface")

    func setManager(_ newManager: Manager?) {
        managerLock.lock()
        manager = newManager
        managerLock.unlock()
    }
    
    func getManager() -> Manager? {
        managerLock.lock()
        let m = manager
        managerLock.unlock()
        return m
    }

    func start(with reply: @escaping (NSError?) -> Void) {
        // Convert Obj-C block to a Swift @Sendable closure.
        let safeReply = CallbackWrapper(reply)
        let manager = getManager()
        
        guard let manager = manager else {
            // If somehow `start(...)` is called but no Manager is set
            reply(NSError(domain: "VPNXPC", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Manager not set"
            ]))
            return
        }
        
        // We must call the async actor method from a Task.
        Task {
            do {
                try await manager.startVPN()
                await MainActor.run {
                    safeReply.call(nil)
                }
            } catch {
                await MainActor.run {
                    safeReply.call(error as NSError)
                }
            }
        }
    }

    func stop(with reply: @escaping (NSError?) -> Void) {
        // Convert Obj-C block to a Swift @Sendable closure.
        let safeReply = CallbackWrapper(reply)
        let manager = getManager()

        guard let manager = manager else {
            // If somehow `start(...)` is called but no Manager is set
            reply(NSError(domain: "VPNXPC", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Manager not set"
            ]))
            return
        }
        
        Task {
            do {
                try await manager.stopVPN()
                await MainActor.run {
                    safeReply.call(nil)
                }
            } catch {
                await MainActor.run {
                    safeReply.call(error as NSError)
                }
            }
        }
    }

//    func getPeerInfo(with reply: @escaping (Bool, String?) -> Void) {
//        Task {
//            do {
//                try await manager.getPeerInfo()
//                reply(true, nil)
//            } catch {
//                reply(false, "\(error)")
//            }
//        }
//    }
}
