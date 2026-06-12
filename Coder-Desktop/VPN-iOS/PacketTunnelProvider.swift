import CoderSDK
import NetworkExtension
import os
import VPNLib

class PacketTunnelProvider: NEPacketTunnelProvider, @unchecked Sendable {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "provider")
    // a `tunnelRemoteAddress` is required, but not currently used.
    private var currentSettings: NEPacketTunnelNetworkSettings = .init(tunnelRemoteAddress: "127.0.0.1")
    private var manager: TunnelManager?

    override nonisolated(nonsending) func startTunnel(
        options _: [String: NSObject]?
    ) async throws {
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let baseAccessURL = proto.serverAddress
        else {
            logger.error("startTunnel called with nil protocolConfiguration")
            throw makeNSError(suffix: "PTP", desc: "Missing Configuration")
        }
        // HACK: We can't write to the system keychain, and the NE can't read the user keychain.
        guard let token = proto.providerConfiguration?["token"] as? String else {
            logger.error("startTunnel called with nil token")
            throw makeNSError(suffix: "PTP", desc: "Missing Token")
        }
        let headers: [HTTPHeader] = (proto.providerConfiguration?["literalHeaders"] as? Data)
            .flatMap { try? JSONDecoder().decode([HTTPHeader].self, from: $0) } ?? []
        logger.debug("retrieved token & access URL")
        guard let tunFd = tunnelFileDescriptor else {
            logger.error("startTunnel called with nil tunnelFileDescriptor")
            throw makeNSError(suffix: "PTP", desc: "Missing Tunnel File Descriptor")
        }
        let manager = try await TunnelManager(provider: self, cfg: .init(
            apiToken: token,
            serverUrl: .init(string: baseAccessURL)!,
            tunFd: tunFd,
            literalHeaders: headers
        ))
        self.manager = manager
        try await manager.startVPN()
    }

    override func stopTunnel(
        with _: NEProviderStopReason
    ) async {
        logger.debug("stopping tunnel")
        try? await manager?.stopVPN()
        manager = nil
        logger.info("tunnel stopped")
    }

    override func handleAppMessage(_ messageData: Data) async -> Data? {
        guard let cmd = String(data: messageData, encoding: .utf8) else {
            return nil
        }
        switch cmd {
        case CoderIPC.getPeerStateMessage:
            guard let manager else { return nil }
            return try? await manager.getPeerState().serializedData()
        default:
            logger.warning("received unknown app message: \(cmd, privacy: .public)")
            return nil
        }
    }

    // Wrapper around `setTunnelNetworkSettings` that supports merging updates
    func applyTunnelNetworkSettings(_ diff: Vpn_NetworkSettingsRequest) async throws {
        logger.debug("applying settings diff: \(diff.debugDescription, privacy: .public)")
        currentSettings.merge(with: diff)
        logger.info("applying settings: \(self.currentSettings.debugDescription, privacy: .public)")
        try await setTunnelNetworkSettings(currentSettings)
    }
}
