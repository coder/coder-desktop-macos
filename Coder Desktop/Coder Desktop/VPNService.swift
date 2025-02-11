import NetworkExtension
import os
import SwiftUI
import VPNLib

@MainActor
protocol VPNService: ObservableObject {
    var state: VPNServiceState { get }
    var menuState: VPNMenuState { get }
    func start() async
    func stop() async
    func configureTunnelProviderProtocol(proto: NETunnelProviderProtocol?)
}

enum VPNServiceState: Equatable {
    case disabled
    case connecting
    case disconnecting
    case connected
    case failed(VPNServiceError)
}

enum VPNServiceError: Error, Equatable {
    case internalError(String)
    case systemExtensionError(SystemExtensionState)
    case networkExtensionError(NetworkExtensionState)

    var description: String {
        switch self {
        case let .internalError(description):
            "Internal Error: \(description)"
        case let .systemExtensionError(state):
            state.description
        case let .networkExtensionError(state):
            state.description
        }
    }
}

@MainActor
final class CoderVPNService: NSObject, VPNService {
    var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "vpn")
    lazy var xpc: VPNXPCInterface = .init(vpn: self)

    @Published var tunnelState: VPNServiceState = .disabled
    @Published var sysExtnState: SystemExtensionState = .uninstalled
    @Published var neState: NetworkExtensionState = .unconfigured
    var state: VPNServiceState {
        guard sysExtnState == .installed else {
            return .failed(.systemExtensionError(sysExtnState))
        }
        guard neState == .enabled || neState == .disabled else {
            return .failed(.networkExtensionError(neState))
        }
        return tunnelState
    }

    @Published var menuState: VPNMenuState = .init()

    // systemExtnDelegate holds a reference to the SystemExtensionDelegate so that it doesn't get
    // garbage collected while the OSSystemExtensionRequest is in flight, since the OS framework
    // only stores a weak reference to the delegate.
    var systemExtnDelegate: SystemExtensionDelegate<CoderVPNService>?

    var serverAddress: String?

    override init() {
        super.init()
        installSystemExtension()
        Task {
            await loadNetworkExtensionConfig()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(vpnDidUpdate(_:)),
            name: .NEVPNStatusDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func start() async {
        switch tunnelState {
        case .disabled, .failed:
            break
        default:
            return
        }

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
                do {
                    try await removeNetworkExtension()
                    neState = .unconfigured
                    tunnelState = .disabled
                } catch {
                    logger.error("failed to remove network extension: \(error)")
                    neState = .failed(error.localizedDescription)
                }
            }
        }
    }

    func onExtensionPeerUpdate(_ data: Data) {
        logger.info("network extension peer update")
        do {
            let msg = try Vpn_PeerUpdate(serializedBytes: data)
            debugPrint(msg)
            applyPeerUpdate(with: msg)
        } catch {
            logger.error("failed to decode peer update \(error)")
        }
    }

    func onExtensionPeerState(_ data: Data?) {
        guard let data else {
            logger.error("could not retrieve peer state from network extension, it may not be running")
            return
        }
        logger.info("received network extension peer state")
        do {
            let msg = try Vpn_PeerUpdate(serializedBytes: data)
            debugPrint(msg)
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
}

extension CoderVPNService {
    // swiftlint:disable:next cyclomatic_complexity
    @objc private func vpnDidUpdate(_ notification: Notification) {
        guard let connection = notification.object as? NETunnelProviderSession else {
            return
        }
        switch connection.status {
        case .disconnected:
            connection.fetchLastDisconnectError { err in
                self.tunnelState = if let err {
                    .failed(.internalError(err.localizedDescription))
                } else {
                    .disabled
                }
            }
        case .connecting:
            // If transitioning to 'connecting' from any other state,
            // then the network extension is running, and we can connect over XPC
            if tunnelState != .connecting {
                xpc.connect()
                xpc.ping()
                tunnelState = .connecting
            }
        case .connected:
            // If transitioning to 'connected' from any other state, the tunnel has
            // finished starting, and we can learn the peer state
            if tunnelState != .connected {
                xpc.connect()
                xpc.getPeerState()
                tunnelState = .connected
            }
        case .reasserting:
            tunnelState = .connecting
        case .disconnecting:
            tunnelState = .disconnecting
        case .invalid:
            tunnelState = .failed(.networkExtensionError(.unconfigured))
        @unknown default:
            tunnelState = .disabled
        }
    }
}
