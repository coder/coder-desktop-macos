import SwiftUI

class PreviewVPN: Coder_Desktop.VPNService {
    @Published var state: Coder_Desktop.VPNServiceState = .disabled
    @Published var agents: [Coder_Desktop.Agent] = [
        Agent(id: UUID(), name: "dogfood2", status: .error, copyableDNS: "asdf.coder", workspaceName: "dogfood2"),
        Agent(id: UUID(), name: "testing-a-very-long-name", status: .okay, copyableDNS: "asdf.coder",
                 workspaceName: "testing-a-very-long-name"
        ),
        Agent(id: UUID(), name: "opensrc", status: .warn, copyableDNS: "asdf.coder", workspaceName: "opensrc"),
        Agent(id: UUID(), name: "gvisor", status: .off, copyableDNS: "asdf.coder", workspaceName: "gvisor"),
        Agent(id: UUID(), name: "example", status: .off, copyableDNS: "asdf.coder", workspaceName: "example"),
        Agent(id: UUID(), name: "dogfood2", status: .error, copyableDNS: "asdf.coder", workspaceName: "dogfood2"),
        Agent(id: UUID(), name: "testing-a-very-long-name", status: .okay, copyableDNS: "asdf.coder",
                 workspaceName: "testing-a-very-long-name"
        ),
        Agent(id: UUID(), name: "opensrc", status: .warn, copyableDNS: "asdf.coder", workspaceName: "opensrc"),
        Agent(id: UUID(), name: "gvisor", status: .off, copyableDNS: "asdf.coder", workspaceName: "gvisor"),
        Agent(id: UUID(), name: "example", status: .off, copyableDNS: "asdf.coder", workspaceName: "example"),
    ]
    let shouldFail: Bool

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    private func setState(_ newState: Coder_Desktop.VPNServiceState) async {
        await MainActor.run {
            self.state = newState
        }
    }

    func start() async {
        await setState(.connecting)
        do {
            try await Task.sleep(nanoseconds: 1000000000)
        } catch {
            await setState(.failed(.exampleError))
            return
        }
        if shouldFail {
            await setState(.failed(.exampleError))
        } else {
            await setState(.connected)
        }
    }

    func stop() async {
        guard state == .connected else { return }
        await setState(.disconnecting)
        do {
            try await Task.sleep(nanoseconds: 1000000000) // Simulate network delay
        } catch {
            await setState(.failed(.exampleError))
            return
        }
        await setState(.disabled)
    }
}
