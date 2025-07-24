import Foundation
import NetworkExtension
import os
import VPNLib

@objc final class AppXPCListener: NSObject, AppXPCInterface, @unchecked Sendable {
    private var svc: CoderVPNService
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppXPCListener")
    private var connection: NSXPCConnection?

    init(vpn: CoderVPNService) {
        svc = vpn
        super.init()
    }

    func connect() -> NSXPCConnection {
        if let connection {
            return connection
        }

        let connection = NSXPCConnection(
            machServiceName: helperAppMachServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: HelperAppXPCInterface.self)
        connection.exportedInterface = NSXPCInterface(with: AppXPCInterface.self)
        connection.exportedObject = self
        connection.invalidationHandler = {
            self.logger.error("XPC connection invalidated")
            self.connection = nil
            _ = self.connect()
        }
        connection.interruptionHandler = {
            self.logger.error("XPC connection interrupted")
            self.connection = nil
            _ = self.connect()
        }
        logger.info("connecting to \(helperAppMachServiceName)")
        connection.setCodeSigningRequirement(SignatureValidator.peerRequirement)
        connection.resume()
        self.connection = connection
        return connection
    }

    func onPeerUpdate(_ diff: Data, reply: @escaping () -> Void) {
        let reply = CompletionWrapper(reply)
        Task { @MainActor in
            svc.onExtensionPeerUpdate(diff)
            reply()
        }
    }

    func onProgress(stage: ProgressStage, downloadProgress: DownloadProgress?, reply: @escaping () -> Void) {
        let reply = CompletionWrapper(reply)
        Task { @MainActor in
            svc.onProgress(stage: stage, downloadProgress: downloadProgress)
            reply()
        }
    }
}

// These methods are called to request updatess from the Helper.
extension AppXPCListener {
    func ping() async throws {
        let conn = connect()
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ err in
                self.logger.error("failed to connect to HelperXPC \(err.localizedDescription, privacy: .public)")
                continuation.resume(throwing: err)
            }) as? HelperAppXPCInterface else {
                self.logger.error("failed to get proxy for HelperXPC")
                continuation.resume(throwing: XPCError.wrongProxyType)
                return
            }
            proxy.ping {
                self.logger.info("Connected to Helper over XPC")
                continuation.resume()
            }
        }
    }

    func getPeerState() async throws {
        let conn = connect()
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ err in
                self.logger.error("failed to connect to HelperXPC \(err.localizedDescription, privacy: .public)")
                continuation.resume(throwing: err)
            }) as? HelperAppXPCInterface else {
                self.logger.error("failed to get proxy for HelperXPC")
                continuation.resume(throwing: XPCError.wrongProxyType)
                return
            }
            proxy.getPeerState { data in
                Task { @MainActor in
                    self.svc.onExtensionPeerState(data)
                }
                continuation.resume()
            }
        }
    }
}
