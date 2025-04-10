@testable import CoderSDK
import Foundation
import Mocker
import Testing

@Suite(.timeLimit(.minutes(1)))
struct CoderSDKTests {
    @Test
    func user() async throws {
        let user = User(
            id: UUID(),
            username: "johndoe"
        )

        let url = URL(string: "https://example.com")!
        let token = "fake-token"
        let client = Client(url: url, token: token, headers: [.init(name: "X-Test-Header", value: "foo")])
        var mock = try Mock(
            url: url.appending(path: "api/v2/users/johndoe"),
            contentType: .json,
            statusCode: 200,
            data: [.get: CoderSDK.encoder.encode(user)]
        )
        var correctHeaders = false
        mock.onRequestHandler = OnRequestHandler { req in
            correctHeaders = req.value(forHTTPHeaderField: Headers.sessionToken) == token &&
                req.value(forHTTPHeaderField: "X-Test-Header") == "foo"
        }
        mock.register()

        let retUser = try await client.user(user.username)
        #expect(user == retUser)
        #expect(correctHeaders)
    }

    @Test
    func buildInfo() async throws {
        let buildInfo = BuildInfoResponse(
            version: "v2.18.2-devel+630fd7c0a"
        )

        let url = URL(string: "https://example.com")!
        let client = Client(url: url)
        try Mock(
            url: url.appending(path: "api/v2/buildinfo"),
            contentType: .json,
            statusCode: 200,
            data: [.get: CoderSDK.encoder.encode(buildInfo)]
        ).register()

        let retBuildInfo = try await client.buildInfo()
        #expect(buildInfo == retBuildInfo)
        #expect(retBuildInfo.semver == "2.18.2")
    }
}
