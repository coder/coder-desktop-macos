import CoderSDK
import Foundation
import os
import VPNLib

// This listener handles XPC connections from the Coder Desktop System Network
// Extension (`com.coder.Coder-Desktop.VPN`).
class HelperNEXPCListener: NSObject, NSXPCListenerDelegate, HelperNEXPCInterface, @unchecked Sendable {
    private var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "HelperNEXPCListener")
    private var conns: [NSXPCConnection] = []

    // Hold a reference to the tun file handle
    // to prevent it from being closed.
    private var tunFile: FileHandle?

    override init() {
        super.init()
    }

    func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        logger.info("new active connection")
        newConnection.exportedInterface = NSXPCInterface(with: HelperNEXPCInterface.self)
        newConnection.exportedObject = self
        newConnection.remoteObjectInterface = NSXPCInterface(with: NEXPCInterface.self)
        newConnection.invalidationHandler = { [weak self] in
            guard let self else { return }
            conns.removeAll { $0 == newConnection }
            logger.debug("connection invalidated")
        }
        newConnection.interruptionHandler = { [weak self] in
            guard let self else { return }
            conns.removeAll { $0 == newConnection }
            logger.debug("connection interrupted")
        }
        newConnection.setCodeSigningRequirement(SignatureValidator.peerRequirement)
        newConnection.resume()
        conns.append(newConnection)
        return true
    }

    let startSymbol = "OpenTunnel"

    // swiftlint:disable:next function_parameter_count
    func startDaemon(
        accessURL: URL,
        token: String,
        tun: FileHandle,
        headers: Data?,
        useSoftNetIsolation: Bool,
        reply: @escaping (Error?) -> Void
    ) {
        logger.info("startDaemon called")
        tunFile = tun
        let reply = CallbackWrapper(reply)
        Task { @MainActor in
            do throws(ManagerError) {
                let manager = try await Manager(
                    cfg: .init(
                        apiToken: token,
                        serverUrl: accessURL,
                        tunFd: tun.fileDescriptor,
                        useSoftNetIsolation: useSoftNetIsolation,
                        literalHeaders: headers.flatMap { try? JSONDecoder().decode([HTTPHeader].self, from: $0) } ?? []
                    )
                )
                try await manager.startVPN()
                globalManager = manager
            } catch {
                reply(makeNSError(suffix: "Manager", desc: error.description))
                return
            }
            reply(nil)
        }
    }

    func stopDaemon(reply: @escaping (Error?) -> Void) {
        logger.info("stopDaemon called")
        let reply = CallbackWrapper(reply)
        Task { @MainActor in
            guard let manager = globalManager else {
                logger.error("stopDaemon called with nil Manager")
                reply(makeNSError(suffix: "Manager", desc: "Missing Manager"))
                return
            }
            do throws(ManagerError) {
                try await manager.stopVPN()
            } catch {
                reply(makeNSError(suffix: "Manager", desc: error.description))
                return
            }
            globalManager = nil
            reply(nil)
        }
    }
}

// These methods are called to send updates to the Coder Desktop System Network
// Extension.
extension HelperNEXPCListener {
    func cancelProvider(error: Error?) async throws {
        try await withCheckedThrowingContinuation { continuation in
            guard let proxy = conns.last?.remoteObjectProxyWithErrorHandler({ err in
                self.logger.error("failed to connect to HelperNEXPC \(err.localizedDescription, privacy: .public)")
                continuation.resume(throwing: err)
            }) as? NEXPCInterface else {
                self.logger.error("failed to get proxy for HelperNEXPCInterface")
                continuation.resume(throwing: XPCError.wrongProxyType)
                return
            }
            proxy.cancelProvider(error: error) {
                self.logger.info("provider cancelled")
                continuation.resume()
            }
        } as Void
    }

    func applyTunnelNetworkSettings(diff: Vpn_NetworkSettingsRequest) async throws {
        let bytes = try diff.serializedData()
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = conns.last?.remoteObjectProxyWithErrorHandler({ err in
                self.logger.error("failed to connect to HelperNEXPC \(err.localizedDescription, privacy: .public)")
                continuation.resume(throwing: err)
            }) as? NEXPCInterface else {
                self.logger.error("failed to get proxy for HelperNEXPCInterface")
                continuation.resume(throwing: XPCError.wrongProxyType)
                return
            }
            proxy.applyTunnelNetworkSettings(diff: bytes) {
                self.logger.info("applied tunnel network setting")
                continuation.resume()
            }
        }
    }
}

// This listener handles XPC connections from the Coder Desktop App
// (`com.coder.Coder-Desktop`).
class HelperAppXPCListener: NSObject, NSXPCListenerDelegate, HelperAppXPCInterface, @unchecked Sendable {
    private var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "HelperAppXPCListener")
    private var conns: [NSXPCConnection] = []

    override init() {
        super.init()
    }

    func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        logger.info("new app connection")
        newConnection.exportedInterface = NSXPCInterface(with: HelperAppXPCInterface.self)
        newConnection.exportedObject = self
        newConnection.remoteObjectInterface = NSXPCInterface(with: AppXPCInterface.self)
        newConnection.invalidationHandler = { [weak self] in
            guard let self else { return }
            conns.removeAll { $0 == newConnection }
            logger.debug("app connection invalidated")
        }
        newConnection.setCodeSigningRequirement(SignatureValidator.peerRequirement)
        newConnection.resume()
        conns.append(newConnection)
        return true
    }

    func getPeerState(with reply: @escaping (Data?) -> Void) {
        logger.info("getPeerState called")
        let reply = CallbackWrapper(reply)
        Task { @MainActor in
            let data = try? await globalManager?.getPeerState().serializedData()
            reply(data)
        }
    }

    func ping(reply: @escaping () -> Void) {
        reply()
    }
}

// These methods are called to send updates to the Coder Desktop App.
extension HelperAppXPCListener {
    func onPeerUpdate(update: Vpn_PeerUpdate) async throws {
        let bytes = try update.serializedData()
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = conns.last?.remoteObjectProxyWithErrorHandler({ err in
                self.logger.error("failed to connect to HelperAppXPC \(err.localizedDescription, privacy: .public)")
                continuation.resume(throwing: err)
            }) as? AppXPCInterface else {
                self.logger.error("failed to get proxy for HelperAppXPCInterface")
                continuation.resume(throwing: XPCError.wrongProxyType)
                return
            }
            proxy.onPeerUpdate(bytes) {
                self.logger.info("sent peer update")
                continuation.resume()
            }
        }
    }

    func onProgress(stage: ProgressStage, downloadProgress: DownloadProgress?) async throws {
        try await withCheckedThrowingContinuation { continuation in
            guard let proxy = conns.last?.remoteObjectProxyWithErrorHandler({ err in
                self.logger.error("failed to connect to HelperAppXPC \(err.localizedDescription, privacy: .public)")
                continuation.resume(throwing: err)
            }) as? AppXPCInterface else {
                self.logger.error("failed to get proxy for HelperAppXPCInterface")
                continuation.resume(throwing: XPCError.wrongProxyType)
                return
            }
            proxy.onProgress(stage: stage, downloadProgress: downloadProgress) {
                self.logger.info("sent progress update")
                continuation.resume()
            }
        } as Void
    }
}
