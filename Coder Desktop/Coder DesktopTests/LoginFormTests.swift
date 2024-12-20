@testable import Coder_Desktop
import SwiftUI
import Testing
import ViewInspector

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LoginTests {
    let session: MockSession
    let sut: LoginForm<MockClient, MockSession>
    let view: any View

    init() {
        session = MockSession()
        sut = LoginForm<MockClient, MockSession>()
        view = sut.environmentObject(session)
    }

    @Test
    func testInitialView() async throws {
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                #expect(throws: Never.self) { try view.find(text: "Coder Desktop") }
                #expect(throws: Never.self) { try view.find(text: "Server URL") }
                #expect(throws: Never.self) { try view.find(button: "Next") }
            }
        }
    }

    @Test
    func testInvalidServerURL() async throws {
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.find(ViewType.TextField.self).setInput("http://")
                try view.find(button: "Next").tap()
                #expect(throws: Never.self) { try view.find(ViewType.Alert.self) }
            }
        }
    }

    @Test
    func testValidServerURL() async throws {
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.find(ViewType.TextField.self).setInput("https://coder.example.com")
                try view.find(button: "Next").tap()

                #expect(throws: Never.self) { try view.find(text: "Session Token") }
                #expect(throws: Never.self) { try view.find(ViewType.SecureField.self) }
                #expect(throws: Never.self) { try view.find(button: "Sign In") }
            }
        }
    }

    @Test
    func testBackButton() async throws {
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.find(ViewType.TextField.self).setInput("https://coder.example.com")
                try view.find(button: "Next").tap()
                try view.find(button: "Back").tap()

                #expect(throws: Never.self) { try view.find(text: "Coder Desktop") }
                #expect(throws: Never.self) { try view.find(button: "Next") }
            }
        }
    }

    @Test
    func testFailedAuthentication() async throws {
        let login = LoginForm<MockErrorClient, MockSession>()

        try await ViewHosting.host(login.environmentObject(session)) {
            try await login.inspection.inspect { view in
                try view.find(ViewType.TextField.self).setInput("https://coder.example.com")
                try view.find(button: "Next").tap()
                #expect(throws: Never.self) { try view.find(text: "Session Token") }
                try view.find(ViewType.SecureField.self).setInput("valid-token")
                try await view.actualView().submit()
                #expect(throws: Never.self) { try view.find(ViewType.Alert.self) }
            }
        }
    }

    @Test
    func testSuccessfulLogin() async throws {
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.find(ViewType.TextField.self).setInput("https://coder.example.com")
                try view.find(button: "Next").tap()
                try view.find(ViewType.SecureField.self).setInput("valid-token")
                try await view.actualView().submit()

                #expect(session.hasSession)
            }
        }
    }
}
