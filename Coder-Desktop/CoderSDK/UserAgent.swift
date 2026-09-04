import Foundation

/// Identifies which Coder Desktop process is making a request.
public enum CoderComponent: String, Sendable {
    case app = "coder-desktop"
    case helper = "coder-desktop-core"
}

/// Go's `GOARCH` spelling, so a single pattern matches the CLI, the vpn-daemon and Desktop client.
enum GoArch: String, Sendable {
    case arm64
    case amd64
}

enum UserAgentDefaults {
    static let goos = "darwin"
    static let unknownVersion = "0.0.0"

    #if arch(arm64)
        static let arch: GoArch = .arm64
    #elseif arch(x86_64)
        static let arch: GoArch = .amd64
    #endif

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? unknownVersion
    }
}

/// Formats a `User-Agent` as `<token>/<version> (<goos>/<goarch>)`.
func userAgent(
    component: CoderComponent,
    version: String = UserAgentDefaults.version,
    arch: GoArch = UserAgentDefaults.arch
) -> String {
    "\(component.rawValue)/\(version) (\(UserAgentDefaults.goos)/\(arch.rawValue))"
}

public extension URLRequest {
    /// Sets the Coder `User-Agent`, unless `headers` already carries one.
    mutating func setCoderUserAgent(_ component: CoderComponent, unlessIn headers: [HTTPHeader]) {
        let callerSuppliedUA = headers.contains {
            $0.name.caseInsensitiveCompare(Headers.userAgent) == .orderedSame
        }
        guard !callerSuppliedUA else { return }
        setValue(userAgent(component: component), forHTTPHeaderField: Headers.userAgent)
    }
}
