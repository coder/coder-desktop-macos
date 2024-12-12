@testable import Coder_Desktop
import ViewInspector
import Testing

@Suite(.timeLimit(.minutes(1)))
struct LoginTests {
    @Test
    @MainActor
    func testInitialView() async throws {
        let session = MockSession()
        let view = LoginForm<MockClient, MockSession>()

        try await ViewHosting.host(view.environmentObject(session)) { _ in
            try await view.inspection.inspect { view in
                #expect(throws: Never.self) { try view.find(text: "Coder Desktop") }
                #expect(throws: Never.self) { try view.find(text: "Server URL") }
                #expect(throws: Never.self) { try view.find(button: "Next") }
            }
        }
    }

    @Test
    @MainActor
    func testInvalidServerURL() async throws {
        let session = MockSession()
        let view = LoginForm<MockClient, MockSession>()

        try await ViewHosting.host(view.environmentObject(session)) { _ in
            try await view.inspection.inspect { view in
                try view.find(ViewType.TextField.self).setInput("")
                try view.find(button: "Next").tap()
                #expect(throws: Never.self) { try view.find(text: "Invalid URL") }
            }
        }
    }

    @Test
    @MainActor
    func testValidServerURL() async throws {
        let session = MockSession()
        let view = LoginForm<MockClient, MockSession>()

        try await ViewHosting.host(view.environmentObject(session)) { _ in
            try await view.inspection.inspect { view in
                try view.find(ViewType.TextField.self).setInput("https://coder.example.com")
                try view.find(button: "Next").tap()

                #expect(throws: Never.self) { try view.find(text: "Session Token") }
                #expect(throws: Never.self) { try view.find(ViewType.SecureField.self) }
                #expect(throws: Never.self) { try view.find(button: "Sign In") }
            }
        }
    }

    @Test
    @MainActor
    func testBackButton() async throws {
        let session = MockSession()
        let view = LoginForm<MockClient, MockSession>()

        try await ViewHosting.host(view.environmentObject(session)) { _ in
            try await view.inspection.inspect { view in
                try view.find(ViewType.TextField.self).setInput("https://coder.example.com")
                try view.find(button: "Next").tap()
                try view.find(button: "Back").tap()

                #expect(throws: Never.self) { try view.find(text: "Coder Desktop") }
                #expect(throws: Never.self) { try view.find(button: "Next") }
            }
        }
    }

    @Test
    @MainActor
    func testInvalidSessionToken() async throws {
        let session = MockSession()
        let view = LoginForm<MockClient, MockSession>()

        try await ViewHosting.host(view.environmentObject(session)) { _ in
            try await view.inspection.inspect { view in
                try view.find(ViewType.TextField.self).setInput("https://coder.example.com")
                try view.find(button: "Next").tap()
                try view.find(ViewType.SecureField.self).setInput("")
                try await view.actualView().submit()
                #expect(throws: Never.self) { try view.find(text: "Invalid Session Token") }
            }
        }
    }

    @Test
    @MainActor
    func testFailedAuthentication() async throws {
        let session = MockSession()
        let login = LoginForm<MockErrorClient, MockSession>()

        try await ViewHosting.host(login.environmentObject(session)) { _ in
            try await login.inspection.inspect { view in
                try view.find(ViewType.TextField.self).setInput("https://coder.example.com")
                try view.find(button: "Next").tap()
                #expect(throws: Never.self) { try view.find(text: "Session Token") }
                try view.find(ViewType.SecureField.self).setInput("valid-token")
                try await view.actualView().submit()
                #expect(throws: Never.self) { try view.find(text: "Could not authenticate with Coder deployment") }
            }
        }
    }

    @Test
    @MainActor
    func testSuccessfulLogin() async throws {
        let session = MockSession()
        let view = LoginForm<MockClient, MockSession>()

        try await ViewHosting.host(view.environmentObject(session)) { _ in
            try await view.inspection.inspect { view in
                try view.find(ViewType.TextField.self).setInput("https://coder.example.com")
                try view.find(button: "Next").tap()
                try view.find(ViewType.SecureField.self).setInput("valid-token")
                try view.find(button: "Sign In").tap()

                #expect(session.hasSession)
            }
        }
    }
}
