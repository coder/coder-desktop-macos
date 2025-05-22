@testable import Coder_Desktop
import SwiftUI
import Testing
import ViewInspector

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct VPNStateTests {
    let vpn: MockVPNService
    let state: AppState
    let sut: VPNState<MockVPNService>
    let view: any View

    init() {
        vpn = MockVPNService()
        sut = VPNState<MockVPNService>()
        state = AppState(persistent: false)
        state.login(baseAccessURL: URL(string: "https://coder.example.com")!, sessionToken: "fake-token")
        view = sut.environmentObject(vpn).environmentObject(state)
    }

    @Test
    func testDisabledState() async throws {
        vpn.state = .disabled

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                #expect(throws: Never.self) {
                    try view.find(text: "Enable Coder Connect to see workspaces")
                }
            }
        }
    }

    @Test
    func testConnectingState() async throws {
        vpn.state = .connecting

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                _ = try view.find(text: "Starting Coder Connect...")
            }
        }
    }

    @Test
    func testDisconnectingState() async throws {
        vpn.state = .disconnecting

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                _ = try view.find(text: "Stopping Coder Connect...")
            }
        }
    }

    @Test
    func testFailedState() async throws {
        let errMsg = "Internal error occured!"
        vpn.state = .failed(.internalError(errMsg))

        try await ViewHosting.host(view.environmentObject(vpn)) {
            try await sut.inspection.inspect { view in
                let text = try view.find(ViewType.Text.self)
                #expect(try text.string() == "Internal Error: \(errMsg)")
            }
        }
    }

    @Test
    func testDefaultState() async throws {
        vpn.state = .connected

        try await ViewHosting.host(view.environmentObject(vpn)) {
            try await sut.inspection.inspect { view in
                #expect(throws: (any Error).self) {
                    _ = try view.find(ViewType.Text.self)
                }
            }
        }
    }
}
