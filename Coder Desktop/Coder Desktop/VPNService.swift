import NetworkExtension
import os
import SwiftUI
import VPNXPC

@MainActor
protocol VPNService: ObservableObject {
    var state: VPNServiceState { get }
    var agents: [Agent] { get }
    func start() async
    // Stop must be idempotent
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
    case longTestError

    var description: String {
        switch self {
        case .longTestError:
            return "This is a long error to test the UI with long errors"
        case let .internalError(description):
            return "Internal Error: \(description)"
        case let .systemExtensionError(state):
            return state.description
        case let .networkExtensionError(state):
            return state.description
        }
    }
}

@MainActor
final class CoderVPNService: NSObject, VPNService {
    var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "vpn")
    var xpcConn: NSXPCConnection
    @Published var tunnelState: VPNServiceState = .disabled
    @Published var sysExtnState: SystemExtensionState = .uninstalled
    @Published var neState: NetworkExtensionState = .unconfigured
    var state: VPNServiceState {
        guard sysExtnState == .installed else {
            return .failed(.systemExtensionError(sysExtnState))
        }
        guard neState == .enabled || neState == .disbled else {
            return .failed(.networkExtensionError(neState))
        }
        return tunnelState
    }

    @Published var agents: [Agent] = []

    // systemExtnDelegate holds a reference to the SystemExtensionDelegate so that it doesn't get
    // garbage collected while the OSSystemExtensionRequest is in flight, since the OS framework
    // only stores a weak reference to the delegate.
    var systemExtnDelegate: SystemExtensionDelegate<CoderVPNService>?

    override init() {
        xpcConn = NSXPCConnection(serviceName: "com.coder.Coder-Desktop.VPNXPC")
        xpcConn.remoteObjectInterface = NSXPCInterface(with: VPNXPCProtocol.self)
        xpcConn.resume()

        super.init()
        installSystemExtension()
    }

    var startTask: Task<Void, Never>?
    func start() async {
        if await startTask?.value != nil {
            return
        }
        startTask = Task {
            tunnelState = .connecting
            await enableNetworkExtension()
            logger.debug("network extension enabled")
            if let proxy = xpcConn.remoteObjectProxy as? VPNXPCProtocol {
                proxy.start { _ in
                    self.tunnelState = .connected
                }
            }
        }
        defer { startTask = nil }
        await startTask?.value
    }

    var stopTask: Task<Void, Never>?
    func stop() async {
        // Wait for a start operation to finish first
        await startTask?.value
        guard state == .connected else { return }
        if await stopTask?.value != nil {
            return
        }
        stopTask = Task {
            tunnelState = .disconnecting
            if let proxy = xpcConn.remoteObjectProxy as? VPNXPCProtocol {
                proxy.stop { _ in }
            }
            await disableNetworkExtension()
            logger.info("network extension stopped")
            tunnelState = .disabled
        }
        defer { stopTask = nil }
        await stopTask?.value
    }

    func configureTunnelProviderProtocol(proto: NETunnelProviderProtocol?) {
        Task {
            if proto != nil {
                await configureNetworkExtension(proto: proto!)
                // this just configures the VPN, it doesn't enable it
                tunnelState = .disabled
            } else {
                do {
                    try await removeNetworkExtension()
                    neState = .unconfigured
                    tunnelState = .disabled
                } catch {
                    logger.error("failed to remoing network extension: \(error)")
                    neState = .failed(error.localizedDescription)
                }
            }
        }
    }
}
