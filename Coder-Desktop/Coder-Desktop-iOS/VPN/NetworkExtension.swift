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
            "NetworkExtension: \(error)"
        }
    }
}

/// Handles configuring, enabling, and disabling the VPN tunnel via the
/// NetworkExtension APIs. Unlike macOS there's no system extension to
/// install: the extension ships inside the app, and saving the configuration
/// prompts the user to allow it.
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
            neState = .failed("Failed to remove configuration: \(error.description)")
            return
        }
        logger.debug("inserting new tunnel")

        let tm = NETunnelProviderManager()
        tm.localizedDescription = "Coder"
        tm.protocolConfiguration = proto

        logger.debug("saving new tunnel")
        do {
            try await tm.saveToPreferences()
            neState = .disabled
        } catch {
            // This typically fails when the user declines the permission dialog
            logger.error("save tunnel failed: \(error)")
            neState = .failed(
                "Failed to save configuration: \(error.localizedDescription). Try logging in and out again."
            )
        }
    }

    func removeNetworkExtension() async throws(VPNServiceError) {
        do {
            let tunnels = try await NETunnelProviderManager.loadAllFromPreferences()
            for tunnel in tunnels {
                try await tunnel.removeFromPreferences()
            }
        } catch {
            throw .internalError(error.localizedDescription)
        }
    }

    func startTunnel() async {
        let tm: NETunnelProviderManager
        do {
            tm = try await getTunnelManager()
        } catch {
            logger.error("get tunnel: \(error)")
            neState = .failed("Failed to get VPN configuration: \(error.description)")
            return
        }
        do {
            // iOS kills Network Extensions that exceed the (~50 MiB) memory
            // limit. On-demand restarts the tunnel if that ever happens, and
            // is cleared again when the user disconnects.
            tm.onDemandRules = [NEOnDemandRuleConnect()]
            tm.isOnDemandEnabled = true
            try await tm.saveToPreferences()
            try tm.connection.startVPNTunnel()
        } catch {
            logger.error("start tunnel: \(error)")
            neState = .failed("Failed to start VPN tunnel: \(error.localizedDescription)")
            return
        }
        logger.debug("started tunnel")
        neState = .enabled
    }

    func stopTunnel() async {
        do {
            let tm = try await getTunnelManager()
            tm.isOnDemandEnabled = false
            try await tm.saveToPreferences()
            tm.connection.stopVPNTunnel()
        } catch {
            logger.error("stop tunnel: \(error)")
            neState = .failed("Failed to stop VPN tunnel: \(error.localizedDescription)")
            return
        }
        logger.debug("stopped tunnel")
        neState = .disabled
    }

    @discardableResult
    func getTunnelManager() async throws(VPNServiceError) -> NETunnelProviderManager {
        var tunnels: [NETunnelProviderManager] = []
        do {
            tunnels = try await NETunnelProviderManager.loadAllFromPreferences()
            logger.debug("loaded \(tunnels.count) tunnel(s)")
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
