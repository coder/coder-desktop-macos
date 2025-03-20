@testable import Coder_Desktop
import SwiftUI
import Testing
import ViewInspector

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct VPNMenuTests {
    let vpn: MockVPNService
    let fsd: MockFileSyncDaemon
    let state: AppState
    let sut: VPNMenu<MockVPNService, MockFileSyncDaemon>
    let view: any View

    init() {
        vpn = MockVPNService()
        state = AppState(persistent: false)
        sut = VPNMenu<MockVPNService, MockFileSyncDaemon>()
        fsd = MockFileSyncDaemon()
        view = sut.environmentObject(vpn).environmentObject(state).environmentObject(fsd)
    }

    @Test
    func testVPNLoggedOut() async throws {
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let toggle = try view.find(ViewType.Toggle.self)
                #expect(!toggle.isDisabled())
                #expect(throws: Never.self) { try view.find(text: "Sign in to use Coder Desktop") }
                #expect(throws: Never.self) { try view.find(button: "Sign in") }
            }
        }
    }

    @Test
    func testStartStopCalled() async throws {
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                var toggle = try view.find(ViewType.Toggle.self)
                #expect(try !toggle.isOn())

                vpn.onStart = {
                    vpn.state = .connected
                }
                await vpn.start()

                toggle = try view.find(ViewType.Toggle.self)
                #expect(try toggle.isOn())

                vpn.onStop = {
                    vpn.state = .disabled
                }
                await vpn.stop()
                #expect(try !toggle.isOn())
            }
        }
    }

    @Test
    func testVPNDisabledWhileConnecting() async throws {
        vpn.state = .disabled

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                var toggle = try view.find(ViewType.Toggle.self)
                #expect(try !toggle.isOn())

                vpn.onStart = {
                    vpn.state = .connecting
                }
                await vpn.start()

                toggle = try view.find(ViewType.Toggle.self)
                #expect(toggle.isDisabled())
            }
        }
    }

    @Test
    func testVPNDisabledWhileDisconnecting() async throws {
        vpn.state = .disabled

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                var toggle = try view.find(ViewType.Toggle.self)
                #expect(try !toggle.isOn())

                vpn.onStart = {
                    vpn.state = .connected
                }
                await vpn.start()
                #expect(try toggle.isOn())

                vpn.onStop = {
                    vpn.state = .disconnecting
                }
                await vpn.stop()

                toggle = try view.find(ViewType.Toggle.self)
                #expect(toggle.isDisabled())
            }
        }
    }

    @Test
    func testOffWhenFailed() async throws {
        state.login(baseAccessURL: URL(string: "https://coder.example.com")!, sessionToken: "fake-token")

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let toggle = try view.find(ViewType.Toggle.self)
                #expect(try !toggle.isOn())

                vpn.onStart = {
                    vpn.state = .failed(.internalError("This is a long error message!"))
                }
                await vpn.start()

                #expect(try !toggle.isOn())
                #expect(!toggle.isDisabled())
            }
        }
    }
}
