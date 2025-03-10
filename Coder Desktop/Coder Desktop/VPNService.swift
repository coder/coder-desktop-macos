import NetworkExtension
import os
import SwiftUI
import VPNLib

@MainActor
protocol VPNService: ObservableObject {
    var state: VPNServiceState { get }
    var menuState: VPNMenuState { get }
    var sysExtnState: SystemExtensionState { get }
    var neState: NetworkExtensionState { get }
    func start() async
    func stop() async
    func configureTunnelProviderProtocol(proto: NETunnelProviderProtocol?)
    func uninstall() async -> Bool
    func installExtension() async
    func disableExtension() async -> Bool
    func enableExtension() async -> Bool
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
            "SystemExtensionError: \(state.description)"
        case let .networkExtensionError(state):
            "NetworkExtensionError: \(state.description)"
        }
    }

    var localizedDescription: String { description }
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

    func uninstall() async -> Bool {
        logger.info("Uninstalling VPN system extension...")

        // First stop any active VPN tunnels
        if tunnelState == .connected || tunnelState == .connecting {
            await stop()

            // Wait for tunnel state to actually change to disabled
            let startTime = Date()
            let timeout = TimeInterval(10) // 10 seconds timeout

            while tunnelState != .disabled {
                // Check for timeout
                if Date().timeIntervalSince(startTime) > timeout {
                    logger.warning("Timeout waiting for VPN to disconnect before uninstall")
                    break
                }

                // Wait a bit before checking again
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        // Remove network extension configuration
        do {
            try await removeNetworkExtension()
            neState = .unconfigured
            tunnelState = .disabled
        } catch {
            logger.error("Failed to remove network extension configuration: \(error.localizedDescription)")
            // Continue with deregistration even if removing network extension failed
        }

        // Deregister the system extension
        let success = await deregisterSystemExtension()
        if success {
            logger.info("Successfully uninstalled VPN system extension")
            sysExtnState = .uninstalled
        } else {
            logger.error("Failed to uninstall VPN system extension")
            sysExtnState = .failed("Deregistration failed")
        }

        return success
    }

    func installExtension() async {
        logger.info("Installing VPN system extension...")

        // Install the system extension
        installSystemExtension()

        // We don't need to await here since the installSystemExtension method
        // uses a delegate callback system to update the state
    }

    func disableExtension() async -> Bool {
        logger.info("Disabling VPN network extension without uninstalling...")

        // First stop any active VPN tunnel
        if tunnelState == .connected || tunnelState == .connecting {
            await stop()
        }

        // Remove network extension configuration but keep the system extension
        do {
            try await removeNetworkExtension()
            neState = .unconfigured
            tunnelState = .disabled
            logger.info("Successfully disabled network extension")
            return true
        } catch {
            logger.error("Failed to disable network extension: \(error.localizedDescription)")
            neState = .failed(error.localizedDescription)
            return false
        }
    }

    func enableExtension() async -> Bool {
        logger.info("Enabling VPN network extension...")

        // Ensure system extension is installed
        let extensionInstalled = await ensureSystemExtensionInstalled()
        if !extensionInstalled {
            return false
        }

        // Get the initial state for comparison
        let initialNeState = neState

        // Directly inject AppState dependency to call reconfigure
        if let appState = (NSApp.delegate as? AppDelegate)?.state, appState.hasSession {
            appState.reconfigure()
        } else {
            // No valid session, the user likely needs to log in again
            await MainActor.run {
                NSApp.sendAction(#selector(NSApplication.showLoginWindow), to: nil, from: nil)
            }
        }

        // Wait for network extension state to change
        let stateChanged = await waitForNetworkExtensionChange(from: initialNeState)
        if !stateChanged {
            return false
        }

        logger.info("Network extension was reconfigured successfully")

        // Try to connect to VPN if needed
        return await tryConnectAfterReconfiguration()
    }

    private func ensureSystemExtensionInstalled() async -> Bool {
        if sysExtnState != .installed {
            installSystemExtension()
            // Wait for the system extension to be installed
            for _ in 0 ..< 30 { // Wait up to 3 seconds
                if sysExtnState == .installed {
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }

            if sysExtnState != .installed {
                logger.error("Failed to install system extension during enableExtension")
                return false
            }
        }
        return true
    }

    private func waitForNetworkExtensionChange(from initialState: NetworkExtensionState) async -> Bool {
        // Wait for network extension state to change from the initial state
        for _ in 0 ..< 30 { // Wait up to 3 seconds
            // If the state changes at all from the initial state, we consider reconfiguration successful
            if neState != initialState || neState == .enabled {
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        logger.error("Network extension configuration didn't change after reconfiguration request")
        return false
    }

    private func tryConnectAfterReconfiguration() async -> Bool {
        // If already enabled, we're done
        if neState == .enabled {
            logger.info("Network extension enabled successfully")
            return true
        }

        // Wait a bit longer for the configuration to be fully applied
        try? await Task.sleep(for: .milliseconds(500))

        // If the extension is in a state we can work with, try to start the VPN
        if case .failed = neState {
            logger.error("Network extension in failed state, skipping auto-connection")
        } else if neState != .unconfigured {
            logger.info("Attempting to automatically connect to VPN after reconfiguration")
            await start()

            if tunnelState == .connecting || tunnelState == .connected {
                logger.info("VPN connection started successfully after reconfiguration")
                return true
            }
        }

        // If we get here, the extension was reconfigured but not successfully enabled
        // Since configuration was successful, return true so user can manually connect
        return true
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
        // Non-connected -> Connected: Retrieve Peers
        case (_, .connected):
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
