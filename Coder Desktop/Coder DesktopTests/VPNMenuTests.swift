@testable import Coder_Desktop
import Testing
import ViewInspector

@Suite(.timeLimit(.minutes(1)))
struct VPNMenuTests {
    @Test
    @MainActor
    func testVPNLoggedOut() async throws {
        let vpn = MockVPNService()
        let session = MockSession()
        session.hasSession = false
        let view = VPNMenu<MockVPNService, MockSession>()

        try await ViewHosting.host(view.environmentObject(vpn).environmentObject(session)) { _ in
            try await view.inspection.inspect { view in
                let toggle = try view.find(ViewType.Toggle.self)
                #expect(toggle.isDisabled())
                #expect(throws: Never.self) { try view.find(text: "Sign in to use CoderVPN") }
                #expect(throws: Never.self) { try view.find(button: "Sign In") }
            }
        }
    }

    @Test
    @MainActor
    func testStartStopCalled() async throws {
        let vpn = MockVPNService()
        let session = MockSession()
        let view = VPNMenu<MockVPNService, MockSession>()

        try await ViewHosting.host(view.environmentObject(vpn).environmentObject(session)) { _ in
            try await view.inspection.inspect { view in
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
    @MainActor
    func testVPNDisabledWhileConnecting() async throws {
        let vpn = MockVPNService()
        let session = MockSession()
        vpn.state = .disabled
        let view = VPNMenu<MockVPNService, MockSession>()

        try await ViewHosting.host(view.environmentObject(vpn).environmentObject(session)) { _ in
            try await view.inspection.inspect { view in
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
    @MainActor
    func testVPNDisabledWhileDisconnecting() async throws {
        let vpn = MockVPNService()
        let session = MockSession()
        vpn.state = .disabled
        let view = VPNMenu<MockVPNService, MockSession>()

        try await ViewHosting.host(view.environmentObject(vpn).environmentObject(session)) { _ in
            try await view.inspection.inspect { view in
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
    @MainActor
    func testOffWhenFailed() async throws {
        let vpn = MockVPNService()
        let session = MockSession()
        let view = VPNMenu<MockVPNService, MockSession>()

        try await ViewHosting.host(view.environmentObject(vpn).environmentObject(session)) { _ in
            try await view.inspection.inspect { view in
                let toggle = try view.find(ViewType.Toggle.self)
                #expect(try !toggle.isOn())

                vpn.onStart = {
                    vpn.state = .failed(.exampleError)
                }
                await vpn.start()

                #expect(try !toggle.isOn())
                #expect(!toggle.isDisabled())
            }
        }
    }
}
