import NetworkExtension
import SwiftUI

@MainActor
final class PreviewVPN: Coder_Desktop.VPNService {
    @Published var state: Coder_Desktop.VPNServiceState = .connected
    @Published var menuState: VPNMenuState = .init(agents: [
        UUID(): Agent(id: UUID(), name: "dev", status: .error, hosts: ["asdf.coder"], wsName: "dogfood2",
                      wsID: UUID()),
        UUID(): Agent(id: UUID(), name: "dev", status: .okay, hosts: ["asdf.coder"],
                      wsName: "testing-a-very-long-name", wsID: UUID()),
        UUID(): Agent(id: UUID(), name: "dev", status: .warn, hosts: ["asdf.coder"], wsName: "opensrc",
                      wsID: UUID()),
        UUID(): Agent(id: UUID(), name: "dev", status: .off, hosts: ["asdf.coder"], wsName: "gvisor",
                      wsID: UUID()),
        UUID(): Agent(id: UUID(), name: "dev", status: .off, hosts: ["asdf.coder"], wsName: "example",
                      wsID: UUID()),
        UUID(): Agent(id: UUID(), name: "dev", status: .error, hosts: ["asdf.coder"], wsName: "dogfood2",
                      wsID: UUID()),
        UUID(): Agent(id: UUID(), name: "dev", status: .okay, hosts: ["asdf.coder"],
                      wsName: "testing-a-very-long-name", wsID: UUID()),
        UUID(): Agent(id: UUID(), name: "dev", status: .warn, hosts: ["asdf.coder"], wsName: "opensrc",
                      wsID: UUID()),
        UUID(): Agent(id: UUID(), name: "dev", status: .off, hosts: ["asdf.coder"], wsName: "gvisor",
                      wsID: UUID()),
        UUID(): Agent(id: UUID(), name: "dev", status: .off, hosts: ["asdf.coder"], wsName: "example",
                      wsID: UUID()),
    ], workspaces: [:])
    @Published var sysExtnState: SystemExtensionState = .installed
    @Published var neState: NetworkExtensionState = .enabled
    let shouldFail: Bool
    let longError = "This is a long error to test the UI with long error messages"

    init(shouldFail: Bool = false, extensionInstalled: Bool = true, networkExtensionEnabled: Bool = true) {
        self.shouldFail = shouldFail
        sysExtnState = extensionInstalled ? .installed : .uninstalled
        neState = networkExtensionEnabled ? .enabled : .disabled
    }

    var startTask: Task<Void, Never>?
    func start() async {
        if await startTask?.value != nil {
            return
        }

        startTask = Task {
            state = .connecting
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                state = .failed(.internalError(longError))
                return
            }
            state = shouldFail ? .failed(.internalError(longError)) : .connected
        }
        defer { startTask = nil }
        await startTask?.value
    }

    var stopTask: Task<Void, Never>?
    func stop() async {
        await startTask?.value
        guard state == .connected else { return }
        if await stopTask?.value != nil {
            return
        }

        stopTask = Task {
            state = .disconnecting
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                state = .failed(.internalError(longError))
                return
            }
            state = .disabled
        }
        defer { stopTask = nil }
        await stopTask?.value
    }

    func configureTunnelProviderProtocol(proto _: NETunnelProviderProtocol?) {
        state = .connecting
    }

    func uninstall() async -> Bool {
        // Simulate uninstallation with a delay
        do {
            try await Task.sleep(for: .seconds(2))
        } catch {
            return false
        }

        if !shouldFail {
            sysExtnState = .uninstalled
            return true
        }
        return false
    }

    func installExtension() async {
        // Simulate installation with a delay
        do {
            try await Task.sleep(for: .seconds(2))
            sysExtnState = if !shouldFail {
                .installed
            } else {
                .failed("Failed to install extension")
            }
        } catch {
            sysExtnState = .failed("Installation was interrupted")
        }
    }

    func disableExtension() async -> Bool {
        // Simulate disabling with a delay
        do {
            try await Task.sleep(for: .seconds(1))
        } catch {
            return false
        }

        if !shouldFail {
            neState = .disabled
            state = .disabled
            return true
        } else {
            neState = .failed("Failed to disable network extension")
            return false
        }
    }

    func enableExtension() async -> Bool {
        // Simulate enabling with a delay
        do {
            try await Task.sleep(for: .seconds(1))
        } catch {
            return false
        }

        if !shouldFail {
            neState = .enabled
            state = .disabled // Just disabled, not connected yet
            return true
        } else {
            neState = .failed("Failed to enable network extension")
            return false
        }
    }
}
