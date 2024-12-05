import SwiftUI

class PreviewVPN: Coder_Desktop.VPNService {
    @Published var state: Coder_Desktop.VPNServiceState = .disabled
    @Published var agents: [Coder_Desktop.AgentRow] = [
        AgentRow(id: UUID(), name: "dogfood2", status: .red, copyableDNS: "asdf.coder", workspaceName: "dogfood2"),
        AgentRow(id: UUID(), name: "testing-a-very-long-name", status: .green, copyableDNS: "asdf.coder",
                 workspaceName: "testing-a-very-long-name"
        ),
        AgentRow(id: UUID(), name: "opensrc", status: .yellow, copyableDNS: "asdf.coder", workspaceName: "opensrc"),
        AgentRow(id: UUID(), name: "gvisor", status: .gray, copyableDNS: "asdf.coder", workspaceName: "gvisor"),
        AgentRow(id: UUID(), name: "example", status: .gray, copyableDNS: "asdf.coder", workspaceName: "example"),
        AgentRow(id: UUID(), name: "dogfood2", status: .red, copyableDNS: "asdf.coder", workspaceName: "dogfood2"),
        AgentRow(id: UUID(), name: "testing-a-very-long-name", status: .green, copyableDNS: "asdf.coder",
                 workspaceName: "testing-a-very-long-name"
        ),
        AgentRow(id: UUID(), name: "opensrc", status: .yellow, copyableDNS: "asdf.coder", workspaceName: "opensrc"),
        AgentRow(id: UUID(), name: "gvisor", status: .gray, copyableDNS: "asdf.coder", workspaceName: "gvisor"),
        AgentRow(id: UUID(), name: "example", status: .gray, copyableDNS: "asdf.coder", workspaceName: "example"),
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
