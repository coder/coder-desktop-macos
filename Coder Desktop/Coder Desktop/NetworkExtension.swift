import NetworkExtension
import os

enum NetworkExtensionState: Equatable {
    case unconfigured
    case disbled
    case enabled
    case failed(String)

    var description: String {
        switch self {
        case .unconfigured:
            return "Not logged in to Coder"
        case .enabled:
            return "NetworkExtension tunnel enabled"
        case .disbled:
            return "NetworkExtension tunnel disabled"
        case let .failed(error):
            return "NetworkExtension config failed: \(error)"
        }
    }
}

/// An actor that handles configuring, enabling, and disabling the VPN tunnel via the
/// NetworkExtension APIs.
extension CoderVPNService {
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

    func enableNetworkExtension() async {
        do {
            let tm = try await getTunnelManager()
            if !tm.isEnabled {
                tm.isEnabled = true
                try await tm.saveToPreferences()
                logger.debug("saved tunnel with enabled=true")
            }
            try tm.connection.startVPNTunnel()
        } catch {
            logger.error("enable network extension: \(error)")
            neState = .failed(error.localizedDescription)
            return
        }
        logger.debug("enabled and started tunnel")
        neState = .enabled
    }

    func disableNetworkExtension() async {
        do {
            let tm = try await getTunnelManager()
            tm.connection.stopVPNTunnel()
            tm.isEnabled = false

            try await tm.saveToPreferences()
        } catch {
            logger.error("disable network extension: \(error)")
            neState = .failed(error.localizedDescription)
            return
        }
        logger.debug("saved tunnel with enabled=false")
        neState = .disbled
    }

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
