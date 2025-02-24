import NetworkExtension
import os

enum NetworkExtensionState: Equatable {
    case unconfigured
    case disabled
    case enabled
    case failed(String)

    var description: String {
        switch self {
        case .unconfigured:
            "NetworkExtension not configured, try logging in again"
        case .enabled:
            "NetworkExtension tunnel enabled"
        case .disabled:
            "NetworkExtension tunnel disabled"
        case let .failed(error):
            "NetworkExtension config failed: \(error)"
        }
    }
}

/// An actor that handles configuring, enabling, and disabling the VPN tunnel via the
/// NetworkExtension APIs.
extension CoderVPNService {
    // Attempts to load the NetworkExtension configuration, returning true if successful.
    func loadNetworkExtensionConfig() async -> Bool {
        do {
            let tm = try await getTunnelManager()
            neState = .disabled
            serverAddress = tm.protocolConfiguration?.serverAddress
            return true
        } catch {
            neState = .unconfigured
            return false
        }
    }

    func configureNetworkExtension(proto: NETunnelProviderProtocol) async {
        // removing the old tunnels, rather than reconfiguring ensures that configuration changes
        // are picked up.
        do {
            try await removeNetworkExtension()
        } catch {
            logger.error("remove tunnel failed: \(error)")
            neState = .failed(error.localizedDescription)
            return
        }
        logger.debug("inserting new tunnel")

        let tm = NETunnelProviderManager()
        tm.localizedDescription = "CoderVPN"
        tm.protocolConfiguration = proto

        logger.debug("saving new tunnel")
        do {
            try await tm.saveToPreferences()
        } catch {
            logger.error("save tunnel failed: \(error)")
            neState = .failed(error.localizedDescription)
        }
        neState = .disabled
    }

    func removeNetworkExtension() async throws(VPNServiceError) {
        do {
            let tunnels = try await NETunnelProviderManager.loadAllFromPreferences()
            for tunnel in tunnels {
                try await tunnel.removeFromPreferences()
            }
        } catch {
            throw .internalError("couldn't remove tunnels: \(error)")
        }
    }

    func startTunnel() async {
        do {
            let tm = try await getTunnelManager()
            try tm.connection.startVPNTunnel()
        } catch {
            logger.error("start tunnel: \(error)")
            neState = .failed(error.localizedDescription)
            return
        }
        logger.debug("started tunnel")
        neState = .enabled
    }

    func stopTunnel() async {
        do {
            let tm = try await getTunnelManager()
            tm.connection.stopVPNTunnel()
        } catch {
            logger.error("stop tunnel: \(error)")
            neState = .failed(error.localizedDescription)
            return
        }
        logger.debug("stopped tunnel")
        neState = .disabled
    }

    @discardableResult
    private func getTunnelManager() async throws(VPNServiceError) -> NETunnelProviderManager {
        var tunnels: [NETunnelProviderManager] = []
        do {
            tunnels = try await NETunnelProviderManager.loadAllFromPreferences()
        } catch {
            throw .internalError("couldn't load tunnels: \(error)")
        }
        if tunnels.isEmpty {
            throw .internalError("no tunnels found")
        }
        return tunnels.first!
    }
}

// we're going to mark NETunnelProviderManager as Sendable since there are official APIs that return
// it async.
extension NETunnelProviderManager: @unchecked @retroactive Sendable {}
