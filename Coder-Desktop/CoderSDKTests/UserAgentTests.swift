@testable import CoderSDK
import Foundation
import Mocker
import Testing

@Suite(.timeLimit(.minutes(1)))
struct UserAgentTests {
    // The pattern operators are expected to match against every Coder client.
    static let grammar = #"^coder-desktop(-core)?/[0-9]+\.[0-9]+\.[0-9]+ \(darwin/(amd64|arm64)\)$"#

    static let stubVersion = "0.8.4"
    static let stubServerVersion = "v2.18.2"

    @Test
    func appToken() {
        #expect(
            userAgent(component: .app, version: Self.stubVersion, arch: .arm64)
                == "coder-desktop/\(Self.stubVersion) (darwin/arm64)"
        )
    }

    @Test
    func helperToken() {
        #expect(
            userAgent(component: .helper, version: Self.stubVersion, arch: .arm64)
                == "coder-desktop-core/\(Self.stubVersion) (darwin/arm64)"
        )
    }

    // The CLI and the vpn-daemon report `amd64`, so an Intel build must too.
    @Test
    func intelReportsGoArchNotSwiftArch() {
        let ua = userAgent(component: .app, version: Self.stubVersion, arch: .amd64)
        #expect(ua == "coder-desktop/\(Self.stubVersion) (darwin/amd64)")
        #expect(!ua.contains("x86_64"))
    }

    @Test
    func matchesGrammar() throws {
        let regex = try Regex(Self.grammar)
        for component in [CoderComponent.app, .helper] {
            for arch in [GoArch.arm64, .amd64] {
                let ua = userAgent(component: component, version: Self.stubVersion, arch: arch)
                #expect(ua.contains(regex))
            }
            // The version the running bundle actually reports.
            #expect(userAgent(component: component).contains(regex))
        }
    }

    @Test
    func missingVersionFallsBackToValidGrammar() throws {
        let regex = try Regex(Self.grammar)
        let ua = userAgent(
            component: .app,
            version: UserAgentDefaults.unknownVersion,
            arch: .arm64
        )
        #expect(ua == "coder-desktop/\(UserAgentDefaults.unknownVersion) (darwin/arm64)")
        #expect(ua.contains(regex))
    }

    @Test
    func setOnRequest() async throws {
        // A distinct host per test: Mocker's registry is process-global and
        // suites run in parallel.
        let url = URL(string: "https://ua-default.example.com")!
        let client = Client(url: url, component: .helper)
        let sentUA = try await capturedUserAgent(client: client, url: url)

        #expect(try sentUA.contains(Regex(Self.grammar)))
        #expect(sentUA.hasPrefix("coder-desktop-core/"))
    }

    // A user-configured literal header must replace ours outright. Caller headers
    // are applied with `addValue`, which would otherwise comma-join the two.
    @Test
    func callerSuppliedUserAgentWins() async throws {
        let url = URL(string: "https://ua-override.example.com")!
        let custom = "my-own-agent/1.2.3"
        let client = Client(
            url: url,
            headers: [.init(name: "user-agent", value: custom)],
            component: .helper
        )
        let sentUA = try await capturedUserAgent(client: client, url: url)

        #expect(sentUA == custom)
        #expect(!sentUA.contains("coder-desktop"))
    }

    /// Runs `buildInfo()` against a mock and returns the `User-Agent` it sent.
    private func capturedUserAgent(client: Client, url: URL) async throws -> String {
        var mock = try Mock(
            url: url.appending(path: "api/v2/buildinfo"),
            contentType: .json,
            statusCode: 200,
            data: [.get: CoderSDK.encoder.encode(BuildInfoResponse(version: Self.stubServerVersion))]
        )
        var sentUA: String?
        mock.onRequestHandler = OnRequestHandler { req in
            sentUA = req.value(forHTTPHeaderField: Headers.userAgent)
        }
        mock.register()

        _ = try await client.buildInfo()
        return try #require(sentUA)
    }
}
