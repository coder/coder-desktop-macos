@testable import Coder_Desktop
import Testing
import ViewInspector
import Foundation

@Suite(.timeLimit(.minutes(1)))
struct AgentsTests {
    @MainActor
    private func createMockAgents(count: Int) -> [Agent] {
        return (1 ... count).map {
            Agent(
                id: UUID(),
                name: "a\($0)",
                status: .okay,
                copyableDNS: "a\($0).example.com",
                workspaceName: "w\($0)"
            )
        }
    }

    @Test
    @MainActor
    func agentsWhenVPNOff() throws {
        let vpn = MockVPNService()
        vpn.state = .disabled
        let session = MockSession()
        let view = Agents<MockVPNService, MockSession>().environmentObject(vpn).environmentObject(session)

        #expect(throws: (any Error).self) {
            _ = try view.inspect().find(ViewType.ForEach.self)
        }
    }

    @Test
    @MainActor
    func agentsWhenVPNOn() throws {
        let vpn = MockVPNService()
        vpn.state = .connected
        vpn.agents = createMockAgents(count: Theme.defaultVisibleAgents + 2)
        let session = MockSession()
        let view = Agents<MockVPNService, MockSession>().environmentObject(vpn).environmentObject(session)

        let forEach = try view.inspect().find(ViewType.ForEach.self)
        #expect(forEach.count == Theme.defaultVisibleAgents)
        #expect(throws: Never.self) { try view.inspect().find(link: "a1.coder")}
    }

    @Test
    @MainActor
    func showAllToggle() async throws {
        let vpn = MockVPNService()
        vpn.state = .connected
        vpn.agents = createMockAgents(count: 7)
        let session = MockSession()
        let view = Agents<MockVPNService, MockSession>()

        try await ViewHosting.host(view.environmentObject(vpn).environmentObject(session)) { _ in
            try await view.inspection.inspect { view in
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
    @MainActor
    func noToggleFewAgents() throws {
        let vpn = MockVPNService()
        vpn.state = .connected
        vpn.agents = createMockAgents(count: 3)
        let session = MockSession()
        let view = Agents<MockVPNService, MockSession>().environmentObject(vpn).environmentObject(session)

        #expect(throws: (any Error).self) {
            _ = try view.inspect().find(ViewType.Toggle.self)
        }
    }
}
