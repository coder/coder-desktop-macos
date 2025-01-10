@testable import CoderSDK
import Mocker
import Testing

@Suite(.timeLimit(.minutes(1)))
struct CoderSDKTests {
    @Test
    func user() async throws {
        let now = Date.now
        let user = User(
            id: UUID(),
            username: "johndoe",
            avatar_url: "https://example.com/img.png",
            name: "John Doe",
            email: "john.doe@example.com",
            created_at: now,
            updated_at: now,
            last_seen_at: now,
            status: "active",
            login_type: "email",
            theme_preference: "dark",
            organization_ids: [UUID()],
            roles: [
                Role(name: "user", display_name: "User", organization_id: UUID()),
            ]
        )

        let url = URL(string: "https://example.com")!
        let token = "fake-token"
        let client = Client(url: url, token: token)
        var mock = try Mock(
            url: url.appending(path: "api/v2/users/johndoe"),
            contentType: .json,
            statusCode: 200,
            data: [.get: Client.encoder.encode(user)]
        )
        var tokenSent = false
        mock.onRequestHandler = OnRequestHandler { req in
            tokenSent = req.value(forHTTPHeaderField: Headers.sessionToken) == token
        }
        mock.register()

        let retUser = try await client.user(user.username)
        #expect(user == retUser)
        #expect(tokenSent)
    }

    @Test
    func buildInfo() async throws {
        let buildInfo = BuildInfoResponse(
            external_url: "https://example.com",
            version: "v2.18.2-devel+630fd7c0a",
            dashboard_url: "https://example.com/dashboard",
            telemetry: true,
            workspace_proxy: false,
            agent_api_version: "1.0",
            provisioner_api_version: "1.2",
            upgrade_message: "foo",
            deployment_id: UUID().uuidString
        )

        let url = URL(string: "https://example.com")!
        let client = Client(url: url)
        try Mock(
            url: url.appending(path: "api/v2/buildinfo"),
            contentType: .json,
            statusCode: 200,
            data: [.get: Client.encoder.encode(buildInfo)]
        ).register()

        let retBuildInfo = try await client.buildInfo()
        #expect(buildInfo == retBuildInfo)
        #expect(retBuildInfo.semver == "2.18.2")
    }
}
