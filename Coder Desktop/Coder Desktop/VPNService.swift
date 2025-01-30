import NetworkExtension
import os
import SwiftUI
import VPNLib
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
            "This is a long error to test the UI with long errors"
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
    var terminating = false

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

    @Published var agents: [Agent] = []

    // systemExtnDelegate holds a reference to the SystemExtensionDelegate so that it doesn't get
    // garbage collected while the OSSystemExtensionRequest is in flight, since the OS framework
    // only stores a weak reference to the delegate.
    var systemExtnDelegate: SystemExtensionDelegate<CoderVPNService>?

    override init() {
        super.init()
        installSystemExtension()
        Task {
            await loadNetworkExtension()
        }
    }

    func start() async {
        guard tunnelState == .disabled else { return }
        // this ping is somewhat load bearing since it causes xpc to init
        xpc.ping()
        tunnelState = .connecting
        await enableNetworkExtension()
        logger.debug("network extension enabled")
    }

    func stop() async {
        guard tunnelState == .connected else { return }
        tunnelState = .disconnecting
        await disableNetworkExtension()
        logger.info("network extension stopped")
    }

    // Instructs the service to stop the VPN and then quit once the stop event
    // is read over XPC.
    // MUST only be called from `NSApplicationDelegate.applicationShouldTerminate`
    // MUST eventually call `NSApp.reply(toApplicationShouldTerminate: true)`
    func quit() async {
        guard tunnelState == .connected else {
            NSApp.reply(toApplicationShouldTerminate: true)
            return
        }
        terminating = true
        await stop()
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
        // TODO: handle peer update
        logger.info("network extension peer update")
        do {
            let msg = try Vpn_TunnelMessage(serializedBytes: data)
            debugPrint(msg)
        } catch {
            logger.error("failed to decode peer update \(error)")
        }
    }

    func onExtensionStart() {
        logger.info("network extension reported started")
        tunnelState = .connected
    }

    func onExtensionStop() {
        logger.info("network extension reported stopped")
        tunnelState = .disabled
        if terminating {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
    }

    func onExtensionError(_ error: NSError) {
        logger.error("network extension reported error: \(error)")
        tunnelState = .failed(.internalError(error.localizedDescription))
    }
}
