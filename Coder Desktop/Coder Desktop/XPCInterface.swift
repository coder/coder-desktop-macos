import Foundation
import os
import VPNXPC

@objc final class VPNXPCInterface: NSObject, VPNXPCClientCallbackProtocol, @unchecked Sendable {
    private var svc: CoderVPNService
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "VPNXPCInterface")
    private let xpc: VPNXPCProtocol

    init(vpn: CoderVPNService) {
        svc = vpn

        let networkExtDict = Bundle.main.object(forInfoDictionaryKey: "NetworkExtension") as? [String: Any]
        let machServiceName = networkExtDict?["NEMachServiceName"] as? String
        let xpcConn = NSXPCConnection(machServiceName: machServiceName!)
        xpcConn.remoteObjectInterface = NSXPCInterface(with: VPNXPCProtocol.self)
        xpcConn.exportedInterface = NSXPCInterface(with: VPNXPCClientCallbackProtocol.self)
        guard let proxy = xpcConn.remoteObjectProxy as? VPNXPCProtocol else {
            fatalError("invalid xpc cast")
        }
        xpc = proxy

        super.init()

        xpcConn.exportedObject = self
        xpcConn.invalidationHandler = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.logger.error("XPC connection invalidated.")
            }
        }
        xpcConn.interruptionHandler = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.logger.error("XPC connection interrupted.")
            }
        }
        xpcConn.resume()

        xpc.ping {
            print("Got response from XPC")
        }
    }

    func ping() {
        xpc.ping {
            Task { @MainActor in
                print("Got response from XPC")
            }
        }
    }

    func onPeerUpdate(_ data: Data) {
        Task { @MainActor in
            svc.onExtensionPeerUpdate(data)
        }
    }

    func onStart() {
        Task { @MainActor in
            svc.onExtensionStart()
        }
    }

    func onStop() {
        Task { @MainActor in
            svc.onExtensionStop()
        }
    }

    func onError(_ err: NSError) {
        Task { @MainActor in
            svc.onExtensionError(err)
        }
    }
}
