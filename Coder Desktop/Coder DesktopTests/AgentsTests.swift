@testable import Coder_Desktop
import ViewInspector
import XCTest

final class AgentsTests: XCTestCase {
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

    @MainActor
    func testShowAllToggle() throws {
        let vpn = MockVPNService()
        vpn.state = .connected
        vpn.agents = createMockAgents(count: 7)
        let session = MockSession()
        let view = TestWrapperView(wrapped: Agents<MockVPNService, MockSession>()
            .environmentObject(vpn)
            .environmentObject(session))

        _ = view.inspection.inspect { view in
            let wrapped = try view.find(viewWithId: TEST_ID)

            let toggle = try wrapped.find(ViewType.Toggle.self)
            XCTAssertEqual(try toggle.labelView().text().string(), "Show All")
            XCTAssertFalse(try toggle.isOn())

            try toggle.tap()

            let forEach = try wrapped.find(ViewType.ForEach.self)
            XCTAssertEqual(forEach.count, 7)

            try toggle.tap()
            XCTAssertEqual(try toggle.labelView().text().string(), "Show Less")
            XCTAssertEqual(forEach.count, 5)
        }
    }

    func testNoToggleFewAgents() throws {
        let vpn = MockVPNService()
        vpn.state = .connected
        vpn.agents = createMockAgents(count: 3)
        let session = MockSession()
        let view = Agents<MockVPNService, MockSession>().environmentObject(vpn).environmentObject(session)

        XCTAssertThrowsError(try view.inspect().find(ViewType.Toggle.self))
    }
}
