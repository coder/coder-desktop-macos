@testable import Coder_Desktop
import SwiftUI
import Testing
import ViewInspector

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct VPNStateTests {
    let vpn: MockVPNService
    let sut: VPNState<MockVPNService>
    let view: any View

    init() {
        vpn = MockVPNService()
        sut = VPNState<MockVPNService>()
        view = sut.environmentObject(vpn)
    }

    @Test
    func testDisabledState() async throws {
        vpn.state = .disabled

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                #expect(throws: Never.self) {
                    try view.find(text: "Enable CoderVPN to see agents")
                }
            }
        }
    }

    @Test
    func testConnectingState() async throws {
        vpn.state = .connecting

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let progressView = try view.find(ViewType.ProgressView.self)
                #expect(try progressView.labelView().text().string() == "Starting CoderVPN...")
            }
        }
    }

    @Test
    func testDisconnectingState() async throws {
        vpn.state = .disconnecting

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let progressView = try view.find(ViewType.ProgressView.self)
                #expect(try progressView.labelView().text().string() == "Stopping CoderVPN...")
            }
        }
    }

    @Test
    func testFailedState() async throws {
        vpn.state = .failed(.exampleError)

        try await ViewHosting.host(view.environmentObject(vpn)) {
            try await sut.inspection.inspect { view in
                let text = try view.find(ViewType.Text.self)
                #expect(try text.string() == VPNServiceError.exampleError.description)
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
