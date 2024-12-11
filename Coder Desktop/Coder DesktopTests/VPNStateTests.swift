@testable import Coder_Desktop
import ViewInspector
import XCTest

final class VPNStateTests: XCTestCase {
    func testDisabledState() throws {
        let vpn = MockVPNService()
        vpn.state = .disabled
        let view = VPNState<MockVPNService>().environmentObject(vpn)
        _ = try view.inspect().find(text: "Enable CoderVPN to see agents")
    }

    func testConnectingState() throws {
        let vpn = MockVPNService()
        vpn.state = .connecting
        let view = VPNState<MockVPNService>().environmentObject(vpn)

        let progressView = try view.inspect().find(ViewType.ProgressView.self)
        XCTAssertEqual(try progressView.labelView().text().string(), "Starting CoderVPN...")
    }

    func testDisconnectingState() throws {
        let vpn = MockVPNService()
        vpn.state = .disconnecting
        let view = VPNState<MockVPNService>().environmentObject(vpn)

        let progressView = try view.inspect().find(ViewType.ProgressView.self)
        XCTAssertEqual(try progressView.labelView().text().string(), "Stopping CoderVPN...")
    }

    func testFailedState() throws {
        let vpn = MockVPNService()
        vpn.state = .failed(.exampleError)
        let view = VPNState<MockVPNService>().environmentObject(vpn)

        let text = try view.inspect().find(ViewType.Text.self)
        XCTAssertEqual(try text.string(), VPNServiceError.exampleError.description)
    }

    func testDefaultState() throws {
        let vpn = MockVPNService()
        vpn.state = .connected
        let view = VPNState<MockVPNService>().environmentObject(vpn)

        XCTAssertThrowsError(try view.inspect().find(ViewType.Text.self))
    }
}
