import Foundation
import NetworkExtension
import os
import VPNLib

@objc final class VPNXPCInterface: NSObject, VPNXPCClientCallbackProtocol, @unchecked Sendable {
    private var svc: CoderVPNService
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "VPNXPCInterface")
    private var xpc: VPNXPCProtocol?

    init(vpn: CoderVPNService) {
        svc = vpn
        super.init()
    }

    func connect() {
        guard xpc == nil else {
            return
        }
        let networkExtDict = Bundle.main.object(forInfoDictionaryKey: "NetworkExtension") as? [String: Any]
        let machServiceName = networkExtDict?["NEMachServiceName"] as? String
        let xpcConn = NSXPCConnection(machServiceName: machServiceName!)
        xpcConn.remoteObjectInterface = NSXPCInterface(with: VPNXPCProtocol.self)
        xpcConn.exportedInterface = NSXPCInterface(with: VPNXPCClientCallbackProtocol.self)
        guard let proxy = xpcConn.remoteObjectProxy as? VPNXPCProtocol else {
            fatalError("invalid xpc cast")
        }
        xpc = proxy

        xpcConn.exportedObject = self
        xpcConn.invalidationHandler = { [logger] in
            Task { @MainActor in
                logger.error("XPC connection invalidated.")
                self.xpc = nil
            }
        }
        xpcConn.interruptionHandler = { [logger] in
            Task { @MainActor in
                logger.error("XPC connection interrupted.")
                self.xpc = nil
            }
        }
        xpcConn.resume()
    }

    func ping() {
        xpc?.ping {
            Task { @MainActor in
                self.logger.info("Connected to NE over XPC")
            }
        }
    }

    func getPeerState() {
        xpc?.getPeerState { data in
            Task { @MainActor in
                self.svc.onExtensionPeerState(data)
            }
        }
    }

    func onPeerUpdate(_ data: Data) {
        Task { @MainActor in
            svc.onExtensionPeerUpdate(data)
        }
    }
}
