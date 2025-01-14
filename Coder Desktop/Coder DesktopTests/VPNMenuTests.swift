@testable import Coder_Desktop
import SwiftUI
import Testing
import ViewInspector

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct VPNMenuTests {
    let vpn: MockVPNService
    let session: MockSession
    let sut: VPNMenu<MockVPNService, MockSession>
    let view: any View

    init() {
        vpn = MockVPNService()
        session = MockSession()
        sut = VPNMenu<MockVPNService, MockSession>()
        view = sut.environmentObject(vpn).environmentObject(session)
    }

    @Test
    func testVPNLoggedOut() async throws {
        session.hasSession = false

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let toggle = try view.find(ViewType.Toggle.self)
                #expect(toggle.isDisabled())
                #expect(throws: Never.self) { try view.find(text: "Sign in to use CoderVPN") }
                #expect(throws: Never.self) { try view.find(button: "Sign In") }
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
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let toggle = try view.find(ViewType.Toggle.self)
                #expect(try !toggle.isOn())

                vpn.onStart = {
                    vpn.state = .failed(.longTestError)
                }
                await vpn.start()

                #expect(try !toggle.isOn())
                #expect(!toggle.isDisabled())
            }
        }
    }
}
