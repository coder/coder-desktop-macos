import Foundation
import Testing
import URLRouting
@testable import VPNLib

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CoderRouterTests {
    let router: CoderRouter

    init() {
        router = CoderRouter()
    }

    struct RouteTestCase: CustomStringConvertible, Sendable {
        let urlString: String
        let expectedRoute: CoderRoute?
        let description: String
    }

    @Test("RDP routes", arguments: [
        // Valid routes
        RouteTestCase(
            urlString: "coder://coder.example.com/v0/open/ws/myworkspace/agent/dev/rdp?username=user&password=pass",
            expectedRoute: .open(
                workspace: "myworkspace",
                agent: "dev",
                route: .rdp(RDPCredentials(username: "user", password: "pass"))
            ),
            description: "RDP with username and password"
        ),
        RouteTestCase(
            urlString: "coder://coder.example.com/v0/open/ws/workspace-123/agent/agent-456/rdp",
            expectedRoute: .open(
                workspace: "workspace-123",
                agent: "agent-456",
                route: .rdp(RDPCredentials(username: nil, password: nil))
            ),
            description: "RDP without credentials"
        ),
        RouteTestCase(
            urlString: "coder://coder.example.com/v0/open/ws/workspace-123/agent/agent-456/rdp?username=user",
            expectedRoute: .open(
                workspace: "workspace-123",
                agent: "agent-456",
                route: .rdp(RDPCredentials(username: "user", password: nil))
            ),
            description: "RDP with username only"
        ),
        RouteTestCase(
            urlString: "coder://coder.example.com/v0/open/ws/workspace-123/agent/agent-456/rdp?password=pass",
            expectedRoute: .open(
                workspace: "workspace-123",
                agent: "agent-456",
                route: .rdp(RDPCredentials(username: nil, password: "pass"))
            ),
            description: "RDP with password only"
        ),
        RouteTestCase(
            urlString: "coder://coder.example.com/v0/open/ws/ws-special-chars/agent/agent-with-dashes/rdp",
            expectedRoute: .open(
                workspace: "ws-special-chars",
                agent: "agent-with-dashes",
                route: .rdp(RDPCredentials(username: nil, password: nil))
            ),
            description: "RDP with special characters in workspace and agent IDs"
        ),

        // Invalid routes
        RouteTestCase(
            urlString: "coder://coder.example.com/invalid/path",
            expectedRoute: nil,
            description: "Completely invalid path"
        ),
        RouteTestCase(
            urlString: "coder://coder.example.com/v1/open/ws/workspace-123/agent/agent-456/rdp",
            expectedRoute: nil,
            description: "Invalid version prefix (v1 instead of v0)"
        ),
        RouteTestCase(
            urlString: "coder://coder.example.com/v0/open/workspace-123/agent/agent-456/rdp",
            expectedRoute: nil,
            description: "Missing 'ws' segment"
        ),
        RouteTestCase(
            urlString: "coder://coder.example.com/v0/open/ws/workspace-123/rdp",
            expectedRoute: nil,
            description: "Missing agent segment"
        ),
        RouteTestCase(
            urlString: "http://coder.example.com/v0/open/ws/workspace-123/agent/agent-456",
            expectedRoute: nil,
            description: "Wrong scheme"
        ),
    ])
    func testRdpRoutes(testCase: RouteTestCase) throws {
        let url = URL(string: testCase.urlString)!

        if let expectedRoute = testCase.expectedRoute {
            let route = try router.match(url: url)
            #expect(route == expectedRoute)
        } else {
            #expect(throws: (any Error).self) {
                _ = try router.match(url: url)
            }
        }
    }
}
