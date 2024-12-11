@testable import Coder_Desktop
import ViewInspector
import XCTest

final class LoginTests: XCTestCase {
    @MainActor
    func testInitialView() throws {
        let session = MockSession()
        let client = MockClient()
        let view = TestWrapperView(wrapped: LoginForm<MockClient, MockSession>()
            .environmentObject(session)
            .environmentObject(client))

        _ = view.inspection.inspect { view in
            let wrapped = try view.find(viewWithId: TEST_ID)
            XCTAssertNoThrow(try wrapped.find(text: "Coder Desktop"))
            XCTAssertNoThrow(try wrapped.find(ViewType.TextField.self).labelView().text().string(), "Server URL")
            XCTAssertNoThrow(try wrapped.find(button: "Next"))
        }
    }

    @MainActor
    func testInvalidServerURL() throws {
        let session = MockSession()
        let client = MockClient()
        let view = TestWrapperView(wrapped: LoginForm<MockClient, MockSession>()
            .environmentObject(session)
            .environmentObject(client))

        _ = view.inspection.inspect { view in
            let wrapped = try view.find(viewWithId: TEST_ID)
            let button = try wrapped.find(button: "Next")
            try button.tap()
            XCTAssertNoThrow(try wrapped.find(text: "Invalid URL"))
        }
    }

    @MainActor
    func testValidServerURL() throws {
        let session = MockSession()
        let client = MockClient()
        let view = TestWrapperView(wrapped: LoginForm<MockClient, MockSession>()
            .environmentObject(session)
            .environmentObject(client))

        _ = view.inspection.inspect { view in
            let wrapped = try view.find(viewWithId: TEST_ID)
            try wrapped.find(ViewType.TextField.self).setInput("https://coder.example.com")
            try wrapped.find(button: "Next").tap()

            XCTAssertNoThrow(try wrapped.find(text: "Session Token"))
            XCTAssertNoThrow(try wrapped.find(ViewType.SecureField.self))
            XCTAssertNoThrow(try wrapped.find(button: "Sign In"))
        }
    }

    @MainActor
    func testBackButton() throws {
        let session = MockSession()
        let client = MockClient()
        let view = TestWrapperView(wrapped: LoginForm<MockClient, MockSession>()
            .environmentObject(session)
            .environmentObject(client))

        _ = view.inspection.inspect { view in
            let wrapped = try view.find(viewWithId: TEST_ID)
            try wrapped.find(ViewType.TextField.self).setInput("https://coder.example.com")
            try wrapped.find(button: "Next").tap()
            try wrapped.find(button: "Back").tap()

            XCTAssertNoThrow(try wrapped.find(text: "Coder Desktop"))
            XCTAssertNoThrow(try wrapped.find(button: "Next"))
        }
    }

    @MainActor
    func testInvalidSessionToken() throws {
        let session = MockSession()
        let client = MockClient()
        let view = TestWrapperView(wrapped: LoginForm<MockClient, MockSession>()
            .environmentObject(session)
            .environmentObject(client))

        _ = view.inspection.inspect { view in
            let wrapped = try view.find(viewWithId: TEST_ID)
            try wrapped.find(ViewType.TextField.self).setInput("https://coder.example.com")
            try wrapped.find(button: "Next").tap()
            try wrapped.find(ViewType.SecureField.self).setInput("")
            try wrapped.find(button: "Sign In").tap()

            XCTAssertNoThrow(try wrapped.find(text: "Invalid Session Token"))
        }
    }

    @MainActor
    func testFailedAuthentication() throws {
        let session = MockSession()
        let client = MockClient()
        client.shouldFail = true
        let view = TestWrapperView(wrapped: LoginForm<MockClient, MockSession>()
            .environmentObject(session)
            .environmentObject(client))

        _ = view.inspection.inspect { view in
            let wrapped = try view.find(viewWithId: TEST_ID)
            try wrapped.find(ViewType.TextField.self).setInput("https://coder.example.com")
            try wrapped.find(button: "Next").tap()
            try wrapped.find(ViewType.SecureField.self).setInput("valid-token")
            try wrapped.find(button: "Sign In").tap()

            XCTAssertNoThrow(try wrapped.find(text: "Could not authenticate with Coder deployment"))
        }
    }

    @MainActor
    func testSuccessfulLogin() throws {
        let session = MockSession()
        let client = MockClient()
        let view = TestWrapperView(wrapped: LoginForm<MockClient, MockSession>()
            .environmentObject(session)
            .environmentObject(client))

        _ = view.inspection.inspect { view in
            let wrapped = try view.find(viewWithId: TEST_ID)
            try wrapped.find(ViewType.TextField.self).setInput("https://coder.example.com")
            try wrapped.find(button: "Next").tap()
            try wrapped.find(ViewType.SecureField.self).setInput("valid-token")
            try wrapped.find(button: "Sign In").tap()

            XCTAssertTrue(session.hasSession)
        }
    }
}
