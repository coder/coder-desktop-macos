import NetworkExtension
import SwiftUI

@MainActor
final class PreviewVPN: Coder_Desktop.VPNService {
    @Published var state: Coder_Desktop.VPNServiceState = .disabled
    @Published var agents: [Coder_Desktop.Agent] = [
        Agent(id: UUID(), name: "dogfood2", status: .error, copyableDNS: "asdf.coder", workspaceName: "dogfood2"),
        Agent(id: UUID(), name: "testing-a-very-long-name", status: .okay, copyableDNS: "asdf.coder",
              workspaceName: "testing-a-very-long-name"),
        Agent(id: UUID(), name: "opensrc", status: .warn, copyableDNS: "asdf.coder", workspaceName: "opensrc"),
        Agent(id: UUID(), name: "gvisor", status: .off, copyableDNS: "asdf.coder", workspaceName: "gvisor"),
        Agent(id: UUID(), name: "example", status: .off, copyableDNS: "asdf.coder", workspaceName: "example"),
        Agent(id: UUID(), name: "dogfood2", status: .error, copyableDNS: "asdf.coder", workspaceName: "dogfood2"),
        Agent(id: UUID(), name: "testing-a-very-long-name", status: .okay, copyableDNS: "asdf.coder",
              workspaceName: "testing-a-very-long-name"),
        Agent(id: UUID(), name: "opensrc", status: .warn, copyableDNS: "asdf.coder", workspaceName: "opensrc"),
        Agent(id: UUID(), name: "gvisor", status: .off, copyableDNS: "asdf.coder", workspaceName: "gvisor"),
        Agent(id: UUID(), name: "example", status: .off, copyableDNS: "asdf.coder", workspaceName: "example"),
    ]
    let shouldFail: Bool

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
                state = .failed(.longTestError)
                return
            }
            state = shouldFail ? .failed(.longTestError) : .connected
        }
        defer { startTask = nil }
        await startTask?.value
    }

    var stopTask: Task<Void, Never>?
    func stop() async {
        await startTask?.value
        guard state == .connected else { return}
        if await stopTask?.value != nil {
            return
        }

        stopTask = Task {
            state = .disconnecting
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                state = .failed(.longTestError)
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
}
