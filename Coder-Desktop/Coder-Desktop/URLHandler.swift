import Foundation
import URLRouting

@MainActor
class URLHandler {
    let state: AppState
    let vpn: any VPNService
    let router: CoderRouter

    init(state: AppState, vpn: any VPNService) {
        self.state = state
        self.vpn = vpn
        router = CoderRouter()
    }

    func handle(_ url: URL) throws(URLError) {
        guard state.hasSession, let deployment = state.baseAccessURL else {
            throw .noSession
        }
        guard deployment.host() == url.host else {
            throw .invalidAuthority(url.host() ?? "<none>")
        }
        do {
            switch try router.match(url: url) {
            case let .open(workspace, agent, type):
                switch type {
                case let .rdp(creds):
                    handleRDP(workspace: workspace, agent: agent, creds: creds)
                }
            }
        } catch {
            throw .routerError(url: url)
        }

        func handleRDP(workspace _: String, agent _: String, creds _: RDPCredentials) {
            // TODO: Handle RDP
        }
    }
}

struct CoderRouter: ParserPrinter {
    public var body: some ParserPrinter<URLRequestData, CoderRoute> {
        Route(.case(CoderRoute.open(workspace:agent:route:))) {
            // v0/open/ws/<workspace>/agent/<agent>/<openType>
            Path { "v0"; "open"; "ws"; Parse(.string); "agent"; Parse(.string) }
            openRouter
        }
    }

    var openRouter: some ParserPrinter<URLRequestData, OpenRoute> {
        OneOf {
            Route(.memberwise(OpenRoute.rdp)) {
                Path { "rdp" }
                Query {
                    Parse(.memberwise(RDPCredentials.init)) {
                        Optionally { Field("username") }
                        Optionally { Field("password") }
                    }
                }
            }
        }
    }
}

enum URLError: Error {
    case invalidAuthority(String)
    case routerError(url: URL)
    case noSession

    var description: String {
        switch self {
        case let .invalidAuthority(authority):
            "Authority '\(authority)' does not match the host of the current Coder deployment."
        case let .routerError(url):
            "Failed to handle \(url.absoluteString) because the format is unsupported."
        case .noSession:
            "Not logged in."
        }
    }

    var localizedDescription: String { description }
}

public enum CoderRoute: Equatable, Sendable {
    case open(workspace: String, agent: String, route: OpenRoute)
}

public enum OpenRoute: Equatable, Sendable {
    case rdp(RDPCredentials)
}

// Due to a Swift Result builder limitation, we can't flatten this out to `case rdp(String?, String?)`
// https://github.com/pointfreeco/swift-url-routing/issues/50
public struct RDPCredentials: Equatable, Sendable {
    let username: String?
    let password: String?
}
