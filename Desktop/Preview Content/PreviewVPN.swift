import SwiftUI

class PreviewVPN: Desktop.CoderVPN {
    @Published var state: Desktop.CoderVPNState = .disabled
    @Published var data: [Desktop.AgentRow] = [
        AgentRow(id: UUID(), name: "dogfood2", status: .red, copyableDNS: "asdf.coder"),
        AgentRow(id: UUID(), name: "testing-a-very-long-name", status: .green, copyableDNS: "asdf.coder"),
        AgentRow(id: UUID(), name: "opensrc", status: .yellow, copyableDNS: "asdf.coder"),
        AgentRow(id: UUID(), name: "gvisor", status: .gray, copyableDNS: "asdf.coder"),
        AgentRow(id: UUID(), name: "example", status: .gray, copyableDNS: "asdf.coder")
    ]
    func start() async {
            await MainActor.run {
                state = .connecting
            }
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                await MainActor.run {
                    state = .failed("Timed out starting CoderVPN")
                }
                return
            }
            await MainActor.run {
                state = .connected
            }
        }

    func stop() async {
        await MainActor.run {
            state = .disconnecting
        }
        do {
            try await Task.sleep(nanoseconds: 1_000_000_000) // Simulate network delay
        } catch {
            await MainActor.run {
                state = .failed("Timed out stopping CoderVPN")
            }
            return
        }
        await MainActor.run {
            state = .disabled
        }
    }
}
