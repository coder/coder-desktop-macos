import NetworkExtension
import os
import SwiftUI
import VPNLib

@MainActor
protocol VPNService: ObservableObject {
    var state: VPNServiceState { get }
    var menuState: VPNMenuState { get }
    var progress: VPNProgress { get }
    func start() async
    func stop() async
    func configureTunnelProviderProtocol(proto: NETunnelProviderProtocol?)
    var startWhenReady: Bool { get set }
}

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
    case systemExtensionError(SystemExtensionState)
    case networkExtensionError(NetworkExtensionState)
    case helperError(HelperState)

    public var description: String {
        switch self {
        case let .internalError(description):
            "Internal Error: \(description)"
        case let .systemExtensionError(state):
            "SystemExtensionError: \(state.description)"
        case let .networkExtensionError(state):
            "NetworkExtensionError: \(state.description)"
        case let .helperError(state):
            "HelperError: \(state.description)"
        }
    }

    public var localizedDescription: String { description }
}

@MainActor
final class CoderVPNService: NSObject, VPNService {
    var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "vpn")
    lazy var xpc: VPNXPCInterface = .init(vpn: self)

    @Published var tunnelState: VPNServiceState = .disabled {
        didSet {
            if tunnelState == .connecting {
                progress = .init(stage: .initial, downloadProgress: nil)
            }
        }
    }

    @Published var sysExtnState: SystemExtensionState = .uninstalled
    @Published var neState: NetworkExtensionState = .unconfigured
    var state: VPNServiceState {
        // The ordering here is important. The button to open the settings page
        // where the helper is approved is a no-op if the user has a settings
        // window on the page where the system extension is approved.
        // So, we want to ensure the helper settings button is clicked first.
        guard helperState == .installed else {
            return .failed(.helperError(helperState))
        }
        guard sysExtnState == .installed else {
            return .failed(.systemExtensionError(sysExtnState))
        }
        guard neState == .enabled || neState == .disabled else {
            return .failed(.networkExtensionError(neState))
        }
        if startWhenReady, tunnelState.canBeStarted {
            startWhenReady = false
            Task { await start() }
        }
        return tunnelState
    }

    @Published var helperState: HelperState = .uninstalled

    @Published var progress: VPNProgress = .init(stage: .initial, downloadProgress: nil)

    @Published var menuState: VPNMenuState = .init()

    // Whether the VPN should start as soon as possible
    var startWhenReady: Bool = false
    var onStart: (() -> Void)?

    // systemExtnDelegate holds a reference to the SystemExtensionDelegate so that it doesn't get
    // garbage collected while the OSSystemExtensionRequest is in flight, since the OS framework
    // only stores a weak reference to the delegate.
    var systemExtnDelegate: SystemExtensionDelegate<CoderVPNService>?

    var serverAddress: String?

    override init() {
        super.init()
    }

    func start() async {
        switch tunnelState {
        case .disabled, .failed:
            break
        default:
            return
        }

        // We have to manually fetch the helper state,
        // and we don't want to start the VPN
        // if the helper is not ready.
        refreshHelperState()
        if helperState != .installed {
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

    func onProgress(stage: ProgressStage, downloadProgress: DownloadProgress?) {
        progress = .init(stage: stage, downloadProgress: downloadProgress)
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
    public func vpnDidUpdate(_ connection: NETunnelProviderSession) {
        switch (tunnelState, connection.status) {
        // Any -> Disconnected: Update UI w/ error if present
        case (_, .disconnected):
            connection.fetchLastDisconnectError { err in
                self.tunnelState = if let err {
                    .failed(.internalError(err.localizedDescription))
                } else {
                    .disabled
                }
            }
        // Connecting -> Connecting: no-op
        case (.connecting, .connecting):
            break
        // Connected -> Connected: no-op
        case (.connected, .connected):
            break
        // Non-connecting -> Connecting: Establish XPC
        case (_, .connecting):
            xpc.connect()
            xpc.ping()
            tunnelState = .connecting
        // Non-connected -> Connected:
        // - Retrieve Peers
        // - Run `onStart` closure
        case (_, .connected):
            onStart?()
            xpc.connect()
            xpc.getPeerState()
            tunnelState = .connected
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
