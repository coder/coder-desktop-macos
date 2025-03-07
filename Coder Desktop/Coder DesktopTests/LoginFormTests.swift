@testable import Coder_Desktop
@testable import CoderSDK
import Mocker
import SwiftUI
import Testing
import ViewInspector

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LoginTests {
    let state: AppState
    let sut: LoginForm
    let view: any View

    init() {
        state = AppState(persistent: false)
        sut = LoginForm()
        let store = UserDefaults(suiteName: #file)!
        store.removePersistentDomain(forName: #file)
        view = sut.environmentObject(state)
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
        let url = URL(string: "https://testFailedAuthentication.com")!
        let buildInfo = BuildInfoResponse(
            version: "v2.20.0"
        )
        try Mock(
            url: url.appendingPathComponent("/api/v2/buildinfo"),
            statusCode: 200,
            data: [.get: Client.encoder.encode(buildInfo)]
        ).register()
        Mock(url: url.appendingPathComponent("/api/v2/users/me"), statusCode: 401, data: [.get: Data()]).register()

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
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
            username: "admin"
        )
        let buildInfo = BuildInfoResponse(
            version: "v2.20.0"
        )

        try Mock(
            url: url.appendingPathComponent("/api/v2/users/me"),
            statusCode: 200,
            data: [.get: Client.encoder.encode(user)]
        ).register()

        try Mock(
            url: url.appendingPathComponent("/api/v2/buildinfo"),
            statusCode: 200,
            data: [.get: Client.encoder.encode(buildInfo)]
        ).register()

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                try view.find(ViewType.TextField.self).setInput(url.absoluteString)
                try view.find(button: "Next").tap()
                try view.find(ViewType.SecureField.self).setInput("valid-token")
                try await view.actualView().submit()

                #expect(state.hasSession)
            }
        }
    }
}
