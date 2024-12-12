@testable import Coder_Desktop
import Testing
import ViewInspector
import SwiftUI

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
        vpn.state = .disabled

        #expect(throws: (any Error).self) {
            _ = try view.inspect().find(ViewType.ForEach.self)
        }
    }

    @Test
    @MainActor
    func agentsWhenVPNOn() throws {
        vpn.state = .connected
        vpn.agents = createMockAgents(count: Theme.defaultVisibleAgents + 2)

        let forEach = try view.inspect().find(ViewType.ForEach.self)
        #expect(forEach.count == Theme.defaultVisibleAgents)
        #expect(throws: Never.self) { try view.inspect().find(link: "a1.coder")}
    }

    @Test
    @MainActor
    func showAllToggle() async throws {
        vpn.state = .connected
        vpn.agents = createMockAgents(count: 7)

        try await ViewHosting.host(view) { _ in
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
    @MainActor
    func noToggleFewAgents() throws {
        vpn.state = .connected
        vpn.agents = createMockAgents(count: 3)

        #expect(throws: (any Error).self) {
            _ = try view.inspect().find(ViewType.Toggle.self)
        }
    }
}
