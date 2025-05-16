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
        logger.debug("VPN xpc connect called")
        guard xpc == nil else {
            logger.debug("VPN xpc already exists")
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

        logger.debug("connecting to machServiceName: \(machServiceName!)")

        xpcConn.exportedObject = self
        xpcConn.invalidationHandler = { [logger] in
            Task { @MainActor in
                logger.error("VPN XPC connection invalidated.")
                self.xpc = nil
                self.connect()
            }
        }
        xpcConn.interruptionHandler = { [logger] in
            Task { @MainActor in
                logger.error("VPN XPC connection interrupted.")
                self.xpc = nil
                self.connect()
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

    func onProgress(stage: ProgressStage, downloadProgress: DownloadProgress?) {
        Task { @MainActor in
            svc.onProgress(stage: stage, downloadProgress: downloadProgress)
        }
    }

    // The NE has verified the dylib and knows better than Gatekeeper
    func removeQuarantine(path: String, reply: @escaping (Bool) -> Void) {
        let reply = CallbackWrapper(reply)
        Task { @MainActor in
            let prompt = """
            Coder Desktop wants to execute code downloaded from \
            \(svc.serverAddress ?? "the Coder deployment"). The code has been \
            verified to be signed by Coder.
            """
            let source = """
            do shell script "xattr -d com.apple.quarantine \(path)" \
            with prompt "\(prompt)" \
            with administrator privileges
            """
            let success = await withCheckedContinuation { continuation in
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(returning: false)
                    return
                }
                // Run on a background thread
                Task.detached {
                    var error: NSDictionary?
                    script.executeAndReturnError(&error)
                    if let error {
                        self.logger.error("AppleScript error: \(error)")
                        continuation.resume(returning: false)
                    } else {
                        continuation.resume(returning: true)
                    }
                }
            }
            reply(success)
        }
    }
}
