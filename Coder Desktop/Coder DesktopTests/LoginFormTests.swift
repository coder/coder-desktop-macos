@testable import Coder_Desktop
@testable import CoderSDK
import Mocker
import SwiftUI
import Testing
import ViewInspector

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LoginTests {
    let session: MockSession
    let sut: LoginForm<MockSession>
    let view: any View

    init() {
        session = MockSession()
        sut = LoginForm<MockSession>()
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
        let login = LoginForm<MockSession>()
        let url = URL(string: "https://testFailedAuthentication.com")!
        Mock(url: url.appendingPathComponent("/api/v2/users/me"), statusCode: 401, data: [.get: Data()]).register()

        try await ViewHosting.host(login.environmentObject(session)) {
            try await login.inspection.inspect { view in
                try view.find(ViewType.TextField.self).setInput(url.absoluteString)
                try view.find(button: "Next").tap()
                #expect(throws: Never.self) { try view.find(text: "Session Token") }
                try view.find(ViewType.SecureField.self).setInput("invalid-token")
                try await view.actualView().submit()
                #expect(throws: Never.self) { try view.find(ViewType.Alert.self) }
            }
        }
    }

    @Test
    func testSuccessfulLogin() async throws {
        let url = URL(string: "https://testSuccessfulLogin.com")!

        let user = User(
            id: UUID(),
            username: "admin",
            avatar_url: "",
            name: "admin",
            email: "admin@coder.com",
            created_at: Date.now,
            updated_at: Date.now,
            last_seen_at: Date.now,
            status: "active",
            login_type: "none",
            theme_preference: "dark",
            organization_ids: [],
            roles: []
        )

        try Mock(
            url: url.appendingPathComponent("/api/v2/users/me"),
            statusCode: 200,
            data: [.get: Client.encoder.encode(user)]
        ).register()

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.find(ViewType.TextField.self).setInput(url.absoluteString)
                try view.find(button: "Next").tap()
                try view.find(ViewType.SecureField.self).setInput("valid-token")
                try await view.actualView().submit()

                #expect(session.hasSession)
            }
        }
    }
}
