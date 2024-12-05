@testable import Coder_Desktop
import ViewInspector
import XCTest

final class AgentsTests: XCTestCase {
    private func createMockAgents(count: Int) -> [AgentRow] {
        return (1...count).map {
            AgentRow(
                id: UUID(),
                name: "a\($0)",
                status: .green,
                copyableDNS: "a\($0).example.com",
                workspaceName: "w\($0)"
            )
        }
    }

    func testAgentsWhenVPNOff() throws {
        let vpn = MockVPNService()
        vpn.state = .disabled
        let session = MockSession()
        let view = Agents<MockVPNService, MockSession>().environmentObject(vpn).environmentObject(session)

        XCTAssertThrowsError(try view.inspect().find(ViewType.ForEach.self))
    }

    func testAgentsWhenVPNOn() throws {
        let vpn = MockVPNService()
        vpn.state = .connected
        vpn.agents = createMockAgents(count: 7)
        let session = MockSession()
        let view = Agents<MockVPNService, MockSession>().environmentObject(vpn).environmentObject(session)

        let forEach = try view.inspect().find(ViewType.ForEach.self)
        XCTAssertEqual(forEach.count, 5)
        let _ = try view.inspect().find(link: "a1.coder")
    }

    func testNoToggleWhenAgentsAreFew() throws {
        let vpn = MockVPNService()
        vpn.state = .connected
        vpn.agents = createMockAgents(count: 3)
        let session = MockSession()
        let view = Agents<MockVPNService, MockSession>().environmentObject(vpn).environmentObject(session)

        XCTAssertThrowsError(try view.inspect().find(ViewType.Toggle.self))
    }
}
