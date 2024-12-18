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

    func start() async {
        state = .connecting
        do {
            try await Task.sleep(for: .seconds(10))
        } catch {
            state = .failed(.exampleError)
            return
        }
        state = shouldFail ? .failed(.exampleError) : .connected
    }

    func stop() async {
        guard state == .connected else { return }
        state = .disconnecting
        do {
            try await Task.sleep(for: .seconds(10))
        } catch {
            state = .failed(.exampleError)
            return
        }
        state = .disabled
    }
}
