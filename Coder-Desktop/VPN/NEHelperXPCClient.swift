import Foundation
import os
import VPNLib

final class HelperXPCClient: @unchecked Sendable {
    var ptp: PacketTunnelProvider?
    private var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "HelperXPCSpeaker")
    private var connection: NSXPCConnection?

    private func connect() -> NSXPCConnection {
        if let connection = self.connection {
            return connection
        }

        // Though basically undocumented, System Extensions can communicate with
        // LaunchDaemons over XPC if the machServiceName used is prefixed with
        // the team identifier.
        // https://developer.apple.com/forums/thread/654466
        let connection = NSXPCConnection(
            machServiceName: helperNEMachServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: HelperNEXPCInterface.self)
        connection.exportedInterface = NSXPCInterface(with: NEXPCInterface.self)
        connection.exportedObject = self
        connection.invalidationHandler = { [weak self] in
            self?.connection = nil
        }
        connection.interruptionHandler = { [weak self] in
            self?.connection = nil
        }
        connection.setCodeSigningRequirement(Validator.xpcPeerRequirement)
        connection.resume()
        self.connection = connection
        return connection
    }

    func startDaemon(accessURL: URL, token: String, tun: FileHandle, headers: Data?) async throws {
        let conn = connect()
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ err in
                self.logger.error("failed to connect to HelperXPC \(err.localizedDescription, privacy: .public)")
                continuation.resume(throwing: err)
            }) as? HelperNEXPCInterface else {
                self.logger.error("failed to get proxy for HelperXPC")
                continuation.resume(throwing: XPCError.wrongProxyType)
                return
            }
            proxy.startDaemon(accessURL: accessURL, token: token, tun: tun, headers: headers) { err in
                if let error = err {
                    self.logger.error("Failed to start daemon: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: error)
                } else {
                    self.logger.info("successfully started daemon")
                    continuation.resume()
                }
            }
        }
    }

    func stopDaemon() async throws {
        let conn = connect()
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ err in
                self.logger.error("failed to connect to HelperXPC \(err)")
                continuation.resume(throwing: err)
            }) as? HelperNEXPCInterface else {
                self.logger.error("failed to get proxy for HelperXPC")
                continuation.resume(throwing: XPCError.wrongProxyType)
                return
            }
            proxy.stopDaemon { err in
                if let error = err {
                    self.logger.error("failed to stop daemon: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else {
                    self.logger.info("Successfully stopped daemon")
                    continuation.resume()
                }
            }
        }
    }
}

// These methods are called over XPC by the helper.
extension HelperXPCClient: NEXPCInterface {
    func applyTunnelNetworkSettings(diff: Data, reply: @escaping () -> Void) {
        let reply = CompletionWrapper(reply)
        guard let diff = try? Vpn_NetworkSettingsRequest(serializedBytes: diff) else {
            reply()
            return
        }
        Task {
            try? await ptp?.applyTunnelNetworkSettings(diff)
            reply()
        }
    }

    func cancelProvider(error: Error?, reply: @escaping () -> Void) {
        let reply = CompletionWrapper(reply)
        Task {
            ptp?.cancelTunnelWithError(error)
            reply()
        }
    }
}
