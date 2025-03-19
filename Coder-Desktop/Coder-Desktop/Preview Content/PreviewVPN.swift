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
    let shouldFail: Bool
    let longError = "This is a long error to test the UI with long error messages"

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
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

    var startWhenReady: Bool = false
}
