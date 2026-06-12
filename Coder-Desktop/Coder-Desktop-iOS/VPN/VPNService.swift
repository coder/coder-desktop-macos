import NetworkExtension
import os
import SwiftUI
import VPNLib

enum VPNServiceState: Equatable {
    case disabled
    case connecting
    case disconnecting
    case connected
    case failed(VPNServiceError)

    var canBeStarted: Bool {
        switch self {
        // A tunnel failure should not prevent a reconnect attempt
        case .disabled, .failed:
            true
        default:
            false
        }
    }
}

enum VPNServiceError: Error, Equatable {
    case internalError(String)
    case networkExtensionError(NetworkExtensionState)

    public var description: String {
        switch self {
        case let .internalError(description):
            "Internal Error: \(description)"
        case let .networkExtensionError(state):
            "NetworkExtensionError: \(state.description)"
        }
    }

    public var localizedDescription: String { description }
}

@MainActor
final class CoderVPNService: NSObject, ObservableObject {
    var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "vpn")

    @Published private(set) var tunnelState: VPNServiceState = .disabled
    @Published var neState: NetworkExtensionState = .unconfigured
    @Published private(set) var menuState: VPNMenuState = .init()

    var state: VPNServiceState {
        guard neState == .enabled || neState == .disabled else {
            return .failed(.networkExtensionError(neState))
        }
        return tunnelState
    }

    var serverAddress: String?

    override init() {
        super.init()
        // Subscribe to system VPN updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(vpnDidUpdateNotification(_:)),
            name: .NEVPNStatusDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func vpnDidUpdateNotification(_ notification: Notification) {
        guard let session = notification.object as? NETunnelProviderSession else {
            return
        }
        vpnDidUpdate(session)
    }

    // Loads the configuration & current tunnel status on app launch, as the
    // extension may already be running.
    func initialize() async {
        guard await loadNetworkExtensionConfig() else { return }
        if let tm = try? await getTunnelManager(),
           let session = tm.connection as? NETunnelProviderSession
        {
            vpnDidUpdate(session)
        }
    }

    func start() async {
        switch tunnelState {
        case .disabled, .failed:
            break
        default:
            return
        }

        menuState.clear()
        await startTunnel()
        logger.debug("network extension enabled")
    }

    func stop() async {
        guard tunnelState == .connected else { return }
        await stopTunnel()
        logger.info("network extension stopped")
    }

    func configureTunnelProviderProtocol(proto: NETunnelProviderProtocol?) {
        Task {
            if let proto {
                serverAddress = proto.serverAddress
                await configureNetworkExtension(proto: proto)
                // this just configures the VPN, it doesn't enable it
                tunnelState = .disabled
            } else {
                do throws(VPNServiceError) {
                    try await removeNetworkExtension()
                    neState = .unconfigured
                    tunnelState = .disabled
                } catch {
                    logger.error("failed to remove configuration: \(error)")
                    neState = .failed("Failed to remove configuration: \(error.description)")
                }
            }
        }
    }

    // Asks the extension for the current peer state. iOS app extensions
    // can't use XPC, so this goes over `sendProviderMessage`.
    func refreshPeerState() async {
        guard tunnelState == .connected,
              let tm = try? await getTunnelManager(),
              let session = tm.connection as? NETunnelProviderSession
        else { return }
        let data = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            do {
                try session.sendProviderMessage(CoderIPC.getPeerStateMessage.data(using: .utf8)!) { resp in
                    continuation.resume(returning: resp)
                }
            } catch {
                self.logger.error("failed to send provider message: \(error)")
                continuation.resume(returning: nil)
            }
        }
        guard let data else {
            logger.error("could not retrieve peer state from network extension, it may not be running")
            return
        }
        do {
            let msg = try Vpn_PeerUpdate(serializedBytes: data)
            menuState.clear()
            applyPeerUpdate(with: msg)
        } catch {
            logger.error("failed to decode peer update \(error)")
        }
    }

    func applyPeerUpdate(with update: Vpn_PeerUpdate) {
        // Delete agents
        update.deletedAgents.forEach { menuState.deleteAgent(withId: $0.id) }
        update.deletedWorkspaces.forEach { menuState.deleteWorkspace(withId: $0.id) }
        // Upsert workspaces before agents to populate agent workspace names
        update.upsertedWorkspaces.forEach { menuState.upsertWorkspace($0) }
        update.upsertedAgents.forEach { menuState.upsertAgent($0) }
    }

    func vpnDidUpdate(_ connection: NETunnelProviderSession) {
        switch (tunnelState, connection.status) {
        // Any -> Disconnected: Update UI w/ error if present
        case (_, .disconnected):
            connection.fetchLastDisconnectError { err in
                Task { @MainActor in
                    self.tunnelState = if let err {
                        .failed(.internalError(err.localizedDescription))
                    } else {
                        .disabled
                    }
                }
            }
        // Connecting -> Connecting: no-op
        case (.connecting, .connecting):
            break
        // Connected -> Connected: no-op
        case (.connected, .connected):
            break
        case (_, .connecting):
            tunnelState = .connecting
        // Non-connected -> Connected: Retrieve Peers
        case (_, .connected):
            tunnelState = .connected
            Task { await refreshPeerState() }
        // Any -> Reasserting
        case (_, .reasserting):
            tunnelState = .connecting
        // Any -> Disconnecting
        case (_, .disconnecting):
            tunnelState = .disconnecting
        // Any -> Invalid
        case (_, .invalid):
            tunnelState = .failed(.networkExtensionError(.unconfigured))
        @unknown default:
            tunnelState = .disabled
        }
    }
}
