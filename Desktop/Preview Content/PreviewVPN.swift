import SwiftUI

class PreviewVPN: Desktop.CoderVPN {
    @Published var state: Desktop.CoderVPNState = .disabled
    @Published var data: [Desktop.AgentRow] = [
        AgentRow(id: UUID(), name: "dogfood2", status: .red, copyableDNS: "asdf.coder"),
        AgentRow(id: UUID(), name: "testing-a-very-long-name", status: .green, copyableDNS: "asdf.coder"),
        AgentRow(id: UUID(), name: "opensrc", status: .yellow, copyableDNS: "asdf.coder"),
        AgentRow(id: UUID(), name: "gvisor", status: .gray, copyableDNS: "asdf.coder"),
        AgentRow(id: UUID(), name: "example", status: .gray, copyableDNS: "asdf.coder"),
        AgentRow(id: UUID(), name: "dogfood2", status: .red, copyableDNS: "asdf.coder"),
        AgentRow(id: UUID(), name: "testing-a-very-long-name", status: .green, copyableDNS: "asdf.coder"),
        AgentRow(id: UUID(), name: "opensrc", status: .yellow, copyableDNS: "asdf.coder"),
        AgentRow(id: UUID(), name: "gvisor", status: .gray, copyableDNS: "asdf.coder"),
        AgentRow(id: UUID(), name: "example", status: .gray, copyableDNS: "asdf.coder"),
    ]
    let shouldFail: Bool

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    private func setState(_ newState: Desktop.CoderVPNState) async {
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
