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
    let agents: PreviewAgents
    let sut: VPNMenu<MockVPNService, MockFileSyncDaemon, PreviewAgents>
    let view: any View

    init() {
        vpn = MockVPNService()
        state = AppState(persistent: false)
        agents = PreviewAgents()
        sut = VPNMenu<MockVPNService, MockFileSyncDaemon, PreviewAgents>()
        fsd = MockFileSyncDaemon()
        view = sut
            .environmentObject(vpn)
            .environmentObject(state)
            .environmentObject(fsd)
            .environmentObject(agents)
    }

    @Test
    func vPNLoggedOut() async throws {
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
    func vPNLoggedOutUnconfigured() async throws {
        vpn.state = .failed(.networkExtensionError(.unconfigured))
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let toggle = try view.find(ViewType.Toggle.self)
                // Toggle should be enabled even with a failure that would
                // normally make it disabled, because we're signed out.
                #expect(!toggle.isDisabled())
                #expect(throws: Never.self) { try view.find(text: "Sign in to use Coder Desktop") }
                #expect(throws: Never.self) { try view.find(button: "Sign in") }
            }
        }
    }

    @Test
    func startStopCalled() async throws {
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
    func vPNDisabledWhileConnecting() async throws {
        vpn.state = .disabled
        try state.login(baseAccessURL: #require(URL(string: "https://coder.example.com")), sessionToken: "fake-token")

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
    func vPNDisabledWhileDisconnecting() async throws {
        vpn.state = .disabled
        try state.login(baseAccessURL: #require(URL(string: "https://coder.example.com")), sessionToken: "fake-token")

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
    func offWhenFailed() async throws {
        try state.login(baseAccessURL: #require(URL(string: "https://coder.example.com")), sessionToken: "fake-token")

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
