import Foundation
import URLRouting

// This is in VPNLib to avoid depending on `swift-collections` in both the app & extension.
public struct CoderRouter: ParserPrinter {
    public init() {}

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

public enum RouterError: Error {
    case invalidAuthority(String)
    case matchError(url: URL)
    case noSession

    public var description: String {
        switch self {
        case let .invalidAuthority(authority):
            "Authority '\(authority)' does not match the host of the current Coder deployment."
        case let .matchError(url):
            "Failed to handle \(url.absoluteString) because the format is unsupported."
        case .noSession:
            "Not logged in."
        }
    }

    public var localizedDescription: String { description }
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
    public let username: String?
    public let password: String?
}
