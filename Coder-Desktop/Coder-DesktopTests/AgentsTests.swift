@testable import Coder_Desktop
import SwiftUI
import Testing
import ViewInspector

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AgentsTests {
    let vpn: MockVPNService
    let state: AppState
    let sut: Agents<MockVPNService>
    let view: any View

    init() {
        vpn = MockVPNService()
        state = AppState(persistent: false)
        state.login(baseAccessURL: URL(string: "https://coder.example.com")!, sessionToken: "fake-token")
        sut = Agents<MockVPNService>()
        view = sut.environmentObject(vpn).environmentObject(state)
    }

    private func createMockAgents(count: Int, status: AgentStatus = .okay) -> [UUID: Agent] {
        Dictionary(uniqueKeysWithValues: (1 ... count).map {
            let agent = Agent(
                id: UUID(),
                name: "dev",
                status: status,
                hosts: ["a\($0).coder"],
                wsName: "ws\($0)",
                wsID: UUID(),
                lastPing: nil,
                primaryHost: "a\($0).coder"
            )
            return (agent.id, agent)
        })
    }

    @Test
    func agentsWhenVPNOff() throws {
        vpn.state = .disabled

        #expect(throws: (any Error).self) {
            _ = try view.inspect().find(ViewType.ForEach.self)
        }
    }

    @Test func noAgents() async throws {
        vpn.state = .connected
        vpn.menuState = .init(agents: [:])

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                #expect(throws: Never.self) { try view.find(text: "No workspaces!") }
            }
        }
    }

    @Test
    func agentsWhenVPNOn() throws {
        vpn.state = .connected
        vpn.menuState = .init(agents: createMockAgents(count: Theme.defaultVisibleAgents + 2))

        let forEach = try view.inspect().find(ViewType.ForEach.self)
        #expect(forEach.count == Theme.defaultVisibleAgents)
        // Agents are sorted by status, and then by name in alphabetical order
        #expect(throws: Never.self) { try view.inspect().find(text: "a1.coder") }
    }

    @Test
    func showAllButton() async throws {
        vpn.state = .connected
        vpn.menuState = .init(agents: createMockAgents(count: 7))

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                #expect(try view.find(ViewType.ForEach.self).count == Theme.defaultVisibleAgents)
                #expect(throws: Never.self) { try view.find(button: "Show all") }
                #expect(throws: (any Error).self) { try view.find(button: "Show less") }

                try view.find(button: "Show all").tap()
                #expect(try view.find(ViewType.ForEach.self).count == Theme.defaultVisibleAgents + 2)
                #expect(throws: Never.self) { try view.find(button: "Show less") }
                #expect(throws: (any Error).self) { try view.find(button: "Show all") }

                try view.find(button: "Show less").tap()
                #expect(try view.find(ViewType.ForEach.self).count == Theme.defaultVisibleAgents)
                #expect(throws: Never.self) { try view.find(button: "Show all") }
            }
        }
    }

    @Test
    func noShowAllButtonFewAgents() throws {
        vpn.state = .connected
        vpn.menuState = .init(agents: createMockAgents(count: 3))

        #expect(throws: (any Error).self) {
            _ = try view.inspect().find(button: "Show all")
        }
    }

    @Test
    func showOfflineWorkspace() async throws {
        vpn.state = .connected
        vpn.menuState = .init(
            agents: createMockAgents(count: Theme.defaultVisibleAgents - 1),
            workspaces: [UUID(): Workspace(id: UUID(), name: "offline", agents: .init())]
        )

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let forEach = try view.find(ViewType.ForEach.self)
                #expect(forEach.count == Theme.defaultVisibleAgents)
                #expect(throws: Never.self) { try view.find(text: "offline.coder") }
            }
        }
    }
}
