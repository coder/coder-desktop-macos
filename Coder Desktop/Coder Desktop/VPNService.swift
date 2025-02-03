import NetworkExtension
import os
import SwiftUI
import VPNLib

@MainActor
protocol VPNService: ObservableObject {
    var state: VPNServiceState { get }
    var agents: [UUID: Agent] { get }
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
    var workspaces: [UUID: String] = [:]

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

    @Published var agents: [UUID: Agent] = [:]

    // systemExtnDelegate holds a reference to the SystemExtensionDelegate so that it doesn't get
    // garbage collected while the OSSystemExtensionRequest is in flight, since the OS framework
    // only stores a weak reference to the delegate.
    var systemExtnDelegate: SystemExtensionDelegate<CoderVPNService>?

    override init() {
        super.init()
        checkSystemExtensionStatus()
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

    func clearPeers() {
        agents = [:]
        workspaces = [:]
    }

    func start() async {
        switch tunnelState {
        case .disabled, .failed:
            break
        default:
            return
        }

        await enableNetworkExtension()
        // this ping is somewhat load bearing since it causes xpc to init
        xpc.ping()
        logger.debug("network extension enabled")
    }

    func stop() async {
        guard tunnelState == .connected else { return }
        await disableNetworkExtension()
        logger.info("network extension stopped")
    }

    func configureTunnelProviderProtocol(proto: NETunnelProviderProtocol?) {
        Task {
            if let proto {
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
        logger.info("network extension peer state")
        guard let data else {
            logger.error("could not retrieve peer state from network extension")
            return
        }
        do {
            let msg = try Vpn_PeerUpdate(serializedBytes: data)
            debugPrint(msg)
            clearPeers()
            applyPeerUpdate(with: msg)
        } catch {
            logger.error("failed to decode peer update \(error)")
        }
    }

    func applyPeerUpdate(with update: Vpn_PeerUpdate) {
        // Delete agents
        update.deletedAgents
            .compactMap { UUID(uuidData: $0.id) }
            .forEach { agentID in
                agents[agentID] = nil
            }
        update.deletedWorkspaces
            .compactMap { UUID(uuidData: $0.id) }
            .forEach { workspaceID in
                workspaces[workspaceID] = nil
                for (id, agent) in agents where agent.wsID == workspaceID {
                    agents[id] = nil
                }
            }

        // Update workspaces
        for workspaceProto in update.upsertedWorkspaces {
            if let workspaceID = UUID(uuidData: workspaceProto.id) {
                workspaces[workspaceID] = workspaceProto.name
            }
        }

        for agentProto in update.upsertedAgents {
            guard let agentID = UUID(uuidData: agentProto.id) else {
                continue
            }
            guard let workspaceID = UUID(uuidData: agentProto.workspaceID) else {
                continue
            }
            let workspaceName = workspaces[workspaceID] ?? "Unknown Workspace"
            let newAgent = Agent(
                id: agentID,
                name: agentProto.name,
                // If last handshake was not within last five minutes, the agent is unhealthy
                status: agentProto.lastHandshake.date > Date.now.addingTimeInterval(-300) ? .okay : .off,
                copyableDNS: agentProto.fqdn.first ?? "UNKNOWN",
                wsName: workspaceName,
                wsID: workspaceID
            )

            // An existing agent with the same name, belonging to the same workspace
            // is from a previous workspace build, and should be removed.
            agents
                .filter { $0.value.name == agentProto.name && $0.value.wsID == workspaceID }
                .forEach { agents[$0.key] = nil }

            agents[agentID] = newAgent
        }
    }
}

extension CoderVPNService {
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
            tunnelState = .connecting
        case .connected:
            // If we moved from disabled to connected, then the NE was already
            // running, and we need to request the current peer state
            if tunnelState == .disabled {
                xpc.getPeerState()
            }
            tunnelState = .connected
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
