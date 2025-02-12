@testable import Coder_Desktop
import SwiftUI
import Testing
import ViewInspector

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AgentsTests {
    let vpn: MockVPNService
    let session: MockSession
    let sut: Agents<MockVPNService, MockSession>
    let view: any View

    init() {
        vpn = MockVPNService()
        session = MockSession()
        sut = Agents<MockVPNService, MockSession>()
        view = sut.environmentObject(vpn).environmentObject(session)
    }

    private func createMockAgents(count: Int, status: AgentStatus = .okay) -> [UUID: Agent] {
        Dictionary(uniqueKeysWithValues: (1 ... count).map {
            let agent = Agent(
                id: UUID(),
                name: "dev",
                status: status,
                hosts: ["a\($0).coder"],
                wsName: "ws\($0)",
                wsID: UUID()
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
        #expect(throws: Never.self) { try view.inspect().find(link: "a1.coder") }
    }

    @Test
    func showAllToggle() async throws {
        vpn.state = .connected
        vpn.menuState = .init(agents: createMockAgents(count: 7))

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                var toggle = try view.find(ViewType.Toggle.self)
                var forEach = try view.find(ViewType.ForEach.self)
                #expect(forEach.count == Theme.defaultVisibleAgents)
                #expect(try toggle.labelView().text().string() == "Show all")
                #expect(try !toggle.isOn())

                try toggle.tap()
                toggle = try view.find(ViewType.Toggle.self)
                forEach = try view.find(ViewType.ForEach.self)
                #expect(forEach.count == Theme.defaultVisibleAgents + 2)
                #expect(try toggle.labelView().text().string() == "Show less")

                try toggle.tap()
                toggle = try view.find(ViewType.Toggle.self)
                forEach = try view.find(ViewType.ForEach.self)
                #expect(try toggle.labelView().text().string() == "Show all")
                #expect(forEach.count == Theme.defaultVisibleAgents)
            }
        }
    }

    @Test
    func noToggleFewAgents() throws {
        vpn.state = .connected
        vpn.menuState = .init(agents: createMockAgents(count: 3))

        #expect(throws: (any Error).self) {
            _ = try view.inspect().find(ViewType.Toggle.self)
        }
    }

    @Test func showAllToggle_noOnlineWorkspaces() async throws {
        vpn.state = .connected
        let tmpAgents = createMockAgents(count: Theme.defaultVisibleAgents + 1, status: .off)
        vpn.menuState = .init(agents: tmpAgents)

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                var toggle = try view.find(ViewType.Toggle.self)
                var forEach = try view.find(ViewType.ForEach.self)
                #expect(throws: Never.self) { try view.find(text: "No running workspaces!") }
                #expect(forEach.count == 0)
                #expect(try toggle.labelView().text().string() == "Show all")
                #expect(try !toggle.isOn())

                try toggle.tap()
                toggle = try view.find(ViewType.Toggle.self)
                forEach = try view.find(ViewType.ForEach.self)
                #expect(forEach.count == Theme.defaultVisibleAgents + 1)
                #expect(try toggle.labelView().text().string() == "Show less")

                try toggle.tap()
                toggle = try view.find(ViewType.Toggle.self)
                forEach = try view.find(ViewType.ForEach.self)
                #expect(try toggle.labelView().text().string() == "Show all")
                #expect(forEach.count == 0)
            }
        }
    }

    @Test
    func showAllToggle_oneOfflineWorkspace() async throws {
        vpn.state = .connected
        vpn.menuState = .init(agents: createMockAgents(count: Theme.defaultVisibleAgents - 2))
        let offlineAgent = Agent(
            id: UUID(),
            name: "dev",
            status: .off,
            hosts: ["offline.coder"],
            wsName: "offlinews",
            wsID: UUID()
        )
        vpn.menuState.agents[offlineAgent.id] = offlineAgent

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                var toggle = try view.find(ViewType.Toggle.self)
                var forEach = try view.find(ViewType.ForEach.self)
                #expect(forEach.count == Theme.defaultVisibleAgents - 2)
                #expect(try toggle.labelView().text().string() == "Show all")
                #expect(try !toggle.isOn())

                try toggle.tap()
                toggle = try view.find(ViewType.Toggle.self)
                forEach = try view.find(ViewType.ForEach.self)
                #expect(forEach.count == Theme.defaultVisibleAgents - 1)
                #expect(try toggle.labelView().text().string() == "Show less")

                try toggle.tap()
                toggle = try view.find(ViewType.Toggle.self)
                forEach = try view.find(ViewType.ForEach.self)
                #expect(try toggle.labelView().text().string() == "Show all")
                #expect(forEach.count == Theme.defaultVisibleAgents - 2)
            }
        }
    }
}
