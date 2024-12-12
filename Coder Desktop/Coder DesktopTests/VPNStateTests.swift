@testable import Coder_Desktop
import ViewInspector
import Testing

@Suite(.timeLimit(.minutes(1)))
struct VPNStateTests {
    @Test
    @MainActor
    func testDisabledState() async throws {
        let vpn = MockVPNService()
        vpn.state = .disabled
        let view = VPNState<MockVPNService>()

        try await ViewHosting.host(view.environmentObject(vpn)) { _ in
            try await view.inspection.inspect { view in
                #expect(throws: Never.self) {
                    try view.find(text: "Enable CoderVPN to see agents")
                }
            }
        }
    }

    @Test
    @MainActor
    func testConnectingState() async throws {
        let vpn = MockVPNService()
        vpn.state = .connecting
        let view = VPNState<MockVPNService>()

        try await ViewHosting.host(view.environmentObject(vpn)) { _ in
            try await view.inspection.inspect { view in
                let progressView = try view.find(ViewType.ProgressView.self)
                #expect(try progressView.labelView().text().string() == "Starting CoderVPN...")
            }
        }
    }

    @Test
    @MainActor
    func testDisconnectingState() async throws {
        let vpn = MockVPNService()
        vpn.state = .disconnecting
        let view = VPNState<MockVPNService>()

        try await ViewHosting.host(view.environmentObject(vpn)) { _ in
            try await view.inspection.inspect { view in
                let progressView = try view.find(ViewType.ProgressView.self)
                #expect(try progressView.labelView().text().string() == "Stopping CoderVPN...")
            }
        }
    }

    @Test
    @MainActor
    func testFailedState() async throws {
        let vpn = MockVPNService()
        vpn.state = .failed(.exampleError)
        let view = VPNState<MockVPNService>()

        try await ViewHosting.host(view.environmentObject(vpn)) { _ in
            try await view.inspection.inspect { view in
                let text = try view.find(ViewType.Text.self)
                #expect(try text.string() == VPNServiceError.exampleError.description)
            }
        }
    }

    @Test
    @MainActor
    func testDefaultState() async throws {
        let vpn = MockVPNService()
        vpn.state = .connected
        let view = VPNState<MockVPNService>()

        try await ViewHosting.host(view.environmentObject(vpn)) { _ in
            try await view.inspection.inspect { view in
                #expect(throws: (any Error).self) {
                    _ = try view.find(ViewType.Text.self)
                }
            }
        }
    }
}
