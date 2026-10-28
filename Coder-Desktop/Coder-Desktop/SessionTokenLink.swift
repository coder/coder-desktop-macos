import Foundation

/// Decides whether an external app link may receive the user's session token.
/// Applies the same rules as the Coder dashboard.
enum SessionTokenLink {
    /// Replaced with the user's session token in trusted app links.
    static let placeholder = "$SESSION_TOKEN"

    /// Shown when an app needs a session token but its link isn't trusted with one.
    static let blockedMessage = "This app's URL isn't trusted to sign you in to Coder."

    private struct Handler {
        /// Scheme and authority, matched case-insensitively.
        let base: String
        /// Path through the first required param, matched exactly.
        let path: String
    }

    /// The only deep-link handlers that may receive the session token.
    private static let handlers: [Handler] = [
        "vscode", "vscode-insiders", "windsurf", "devin", "cursor", "kiro", "positron", "antigravity",
        "antigravity-ide",
    ].flatMap { scheme in
        ["/open?", "/openDevContainer?"].map { Handler(base: "\(scheme)://coder.coder-remote", path: $0) }
    } + [
        Handler(base: "jetbrains://gateway", path: "/coder?"),
        Handler(base: "jetbrains://gateway", path: "/com.coder.toolbox?"),
        // Gateway also handles non-Coder providers, such as `type=ssh`.
        Handler(base: "jetbrains-gateway://connect", path: "#type=coder&"),
    ]

    /// Returns the link with the placeholder replaced by `token`, or by an empty
    /// string for sub-agent apps. Links without the placeholder are returned
    /// unchanged. Returns nil if the link isn't trusted with a token.
    static func substitute(
        _ appURL: String,
        deploymentURL: URL,
        token: String,
        isSubAgentApp: Bool
    ) -> String? {
        guard appURL.contains(placeholder) else { return appURL }
        guard isDestinationTrusted(appURL, deploymentURL: deploymentURL) else { return nil }
        // Sub-agent apps never get a token; `coder open app` refuses them too.
        return appURL.replacingOccurrences(of: placeholder, with: isSubAgentApp ? "" : token)
    }

    /// True when the link opens a known Coder handler, its only `url` param is
    /// `deploymentURL`'s origin, and the placeholder is its only `token`.
    static func isDestinationTrusted(_ appURL: String, deploymentURL: URL) -> Bool {
        // `URL(string:)` percent-encodes non-ASCII, so a valid link is printable
        // ASCII. That also keeps Swift's grapheme-based string comparisons
        // byte-exact. Some URL parsers drop tab, LF and CR, so `ur\tl` could
        // become a second `url` in the IDE.
        guard appURL.unicodeScalars.allSatisfy({ (0x20 ..< 0x7F).contains($0.value) }),
              appURL.components(separatedBy: placeholder).count == 2,
              let handler = handler(for: appURL)
        else { return false }

        let params = String(appURL.dropFirst(
            handler.base.count + handler.path.prefix { $0 != "?" && $0 != "#" }.count + 1
        ))
        let entries = params.components(separatedBy: "&")
        // Substitution replaces the raw placeholder, so it must be the raw
        // `token` entry. JetBrains Gateway doesn't decode names, so they must be
        // literal. IDEs decode values twice, so check that view too and reject
        // leftovers. A later `#` would hide params from IDEs that read only the
        // query.
        guard !params.contains("#"),
              entries.contains("token=\(placeholder)"),
              entries.allSatisfy({ !$0.prefix { $0 != "=" }.contains("%") }),
              let decoded = params.removingPercentEncoding,
              !decoded.unicodeScalars.contains("%")
        else { return false }
        return hasTrustedParams(params, deploymentURL: deploymentURL)
            && hasTrustedParams(decoded, deploymentURL: deploymentURL)
    }

    /// True when `url` is only an origin, optionally with a trailing slash. A
    /// path could reach a workspace app on the deployment, and userinfo can hide
    /// a different host from IDEs that decode it again. Matched on the raw
    /// string, since parsing normalizes `/.` and drops an empty `?`.
    static func isBareOrigin(_ url: String) -> Bool {
        url.range(of: #"^[a-zA-Z][a-zA-Z0-9+.-]*://[^/\\?#@\s]+/?\z"#, options: .regularExpression) != nil
            && URLComponents(string: url)?.host?.isEmpty == false
    }

    /// True when the link opens a known Coder IDE handler.
    static func isKnownHandler(_ appURL: String) -> Bool {
        handler(for: appURL) != nil
    }

    /// The known handler the link starts with, if any. Compared as UTF-8 with
    /// ASCII-only case folding, so a Kelvin sign doesn't match `kiro`.
    private static func handler(for appURL: String) -> Handler? {
        let bytes = appURL.utf8
        return handlers.first { handler in
            let base = handler.base.utf8
            return bytes.prefix(base.count).map { (65 ... 90).contains($0) ? $0 + 32 : $0 }.elementsEqual(base)
                && bytes.dropFirst(base.count).starts(with: handler.path.utf8)
        }
    }

    /// Every name appears once, `token` is the placeholder, `url` is the deployment.
    private static func hasTrustedParams(_ query: String, deploymentURL: URL) -> Bool {
        // Parsed like `URLSearchParams`. Split on scalars, since `&` or `=`
        // followed by a combining mark is one `Character`.
        let params = query.unicodeScalars.split(separator: "&").map { entry in
            entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map { part in
                let plain = String(part).replacingOccurrences(of: "+", with: " ", options: .literal)
                return plain.removingPercentEncoding ?? plain
            }
        }
        let value = { (name: String) in params.first { $0[0] == name }.map { $0.count > 1 ? $0[1] : "" } }
        guard Set(params.map { $0[0] }).count == params.count,
              value("token") == placeholder,
              let url = value("url"),
              isBareOrigin(url),
              let url = URL(string: url),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return false }
        let defaultPort = scheme == "https" ? 443 : 80
        return scheme == deploymentURL.scheme?.lowercased()
            && url.host?.lowercased() == deploymentURL.host?.lowercased()
            && (url.port ?? defaultPort) == (deploymentURL.port ?? defaultPort)
    }
}
