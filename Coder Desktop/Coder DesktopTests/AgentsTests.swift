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

    private func createMockAgents(count: Int) -> [UUID: Agent] {
        Dictionary(uniqueKeysWithValues: (1 ... count).map {
            let agent = Agent(
                id: UUID(),
                name: "dev",
                status: .okay,
                copyableDNS: "a\($0).example.com",
                wsName: "a\($0)",
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

    @Test
    func agentsWhenVPNOn() throws {
        vpn.state = .connected
        vpn.agents = createMockAgents(count: Theme.defaultVisibleAgents + 2)

        let forEach = try view.inspect().find(ViewType.ForEach.self)
        #expect(forEach.count == Theme.defaultVisibleAgents)
        // Agents are sorted by status, and then by name in alphabetical order
        #expect(throws: Never.self) { try view.inspect().find(link: "a1.coder") }
    }

    @Test
    func showAllToggle() async throws {
        vpn.state = .connected
        vpn.agents = createMockAgents(count: 7)

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                var toggle = try view.find(ViewType.Toggle.self)
                #expect(try toggle.labelView().text().string() == "Show All")
                #expect(try !toggle.isOn())

                try toggle.tap()
                toggle = try view.find(ViewType.Toggle.self)
                var forEach = try view.find(ViewType.ForEach.self)
                #expect(forEach.count == Theme.defaultVisibleAgents + 2)
                #expect(try toggle.labelView().text().string() == "Show Less")

                try toggle.tap()
                toggle = try view.find(ViewType.Toggle.self)
                forEach = try view.find(ViewType.ForEach.self)
                #expect(try toggle.labelView().text().string() == "Show All")
                #expect(forEach.count == Theme.defaultVisibleAgents)
            }
        }
    }

    @Test
    func noToggleFewAgents() throws {
        vpn.state = .connected
        vpn.agents = createMockAgents(count: 3)

        #expect(throws: (any Error).self) {
            _ = try view.inspect().find(ViewType.Toggle.self)
        }
    }
}
