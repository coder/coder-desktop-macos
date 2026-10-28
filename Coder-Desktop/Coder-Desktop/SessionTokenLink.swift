import Foundation

/// Decides whether an external app link may receive the user's session token,
/// using the same rules as the Coder dashboard.
enum SessionTokenLink {
    static let placeholder = "$SESSION_TOKEN"
    static let blockedMessage = "This app's URL isn't trusted to sign you in to Coder."

    /// `base` (scheme and authority) is case-insensitive; `path` runs through
    /// the first param and is exact.
    private static let handlers: [(base: String, path: String)] = [
        "vscode", "vscode-insiders", "windsurf", "devin", "cursor", "kiro", "positron", "antigravity",
        "antigravity-ide",
    ].flatMap { scheme in
        ["/open?", "/openDevContainer?"].map { ("\(scheme)://coder.coder-remote", $0) }
    } + [
        ("jetbrains://gateway", "/coder?"),
        ("jetbrains://gateway", "/com.coder.toolbox?"),
        // Gateway also handles non-Coder providers, such as `type=ssh`.
        ("jetbrains-gateway://connect", "#type=coder&"),
    ]

    static func isKnownHandler(_ appURL: String) -> Bool {
        handler(for: appURL) != nil
    }

    /// Replaces the placeholder with `token`, or with nothing for sub-agent apps.
    /// Links without the placeholder are unchanged. Returns nil if the link
    /// isn't trusted.
    static func substitute(_ appURL: String, deploymentURL: URL, token: String, isSubAgentApp: Bool) -> String? {
        guard appURL.contains(placeholder) else { return appURL }
        guard isDestinationTrusted(appURL, deploymentURL: deploymentURL) else { return nil }
        return appURL.replacingOccurrences(of: placeholder, with: isSubAgentApp ? "" : token)
    }

    /// True when the link opens a known handler, its only `url` is the
    /// deployment's bare origin, and the placeholder is its only `token`.
    static func isDestinationTrusted(_ appURL: String, deploymentURL: URL) -> Bool {
        // Printable ASCII only: some parsers drop tab, LF and CR, so `ur\tl`
        // could become `url`, and it keeps grapheme comparisons byte-exact.
        guard appURL.unicodeScalars.allSatisfy({ (0x20 ..< 0x7F).contains($0.value) }),
              appURL.components(separatedBy: placeholder).count == 2,
              let handler = handler(for: appURL)
        else { return false }

        let paramsStart = handler.base.count + handler.path.prefix { $0 != "?" && $0 != "#" }.count + 1
        let params = String(appURL.dropFirst(paramsStart))
        let entries = params.components(separatedBy: "&")
        // The placeholder is replaced raw, so it must be the raw `token` entry.
        // Gateway doesn't decode names, and IDEs decode values twice.
        guard !params.contains("#"),
              entries.contains("token=\(placeholder)"),
              entries.allSatisfy({ !$0.prefix { $0 != "=" }.contains("%") }),
              let decoded = params.removingPercentEncoding,
              !decoded.unicodeScalars.contains("%")
        else { return false }
        return hasTrustedParams(params, deploymentURL: deploymentURL)
            && hasTrustedParams(decoded, deploymentURL: deploymentURL)
    }

    private static func handler(for appURL: String) -> (base: String, path: String)? {
        // Compare UTF-8 with ASCII-only case folding, so a Kelvin sign isn't `k`.
        let bytes = appURL.utf8
        return handlers.first { handler in
            let base = handler.base.utf8
            return bytes.prefix(base.count).map { (65 ... 90).contains($0) ? $0 + 32 : $0 }.elementsEqual(base)
                && bytes.dropFirst(base.count).starts(with: handler.path.utf8)
        }
    }

    private static func hasTrustedParams(_ query: String, deploymentURL: URL) -> Bool {
        // Parsed like `URLSearchParams`, split on scalars since `&` followed by a
        // combining mark is one `Character`.
        let params = query.unicodeScalars.split(separator: "&").map { entry in
            entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map { part in
                let plain = String(part).replacingOccurrences(of: "+", with: " ", options: .literal)
                return plain.removingPercentEncoding ?? plain
            }
        }
        let value = { (name: String) in params.first { $0[0] == name }.map { $0.count > 1 ? $0[1] : "" } }
        // `url` must be a bare origin, matched raw since parsing normalizes `/.` and `?`.
        guard Set(params.map { $0[0] }).count == params.count,
              value("token") == placeholder,
              let url = value("url"),
              url.range(of: #"^https?://[^/\\?#@\s]+/?\z"#, options: [.regularExpression, .caseInsensitive]) != nil,
              let url = URLComponents(string: url),
              let deployment = URLComponents(url: deploymentURL, resolvingAgainstBaseURL: false)
        else { return false }
        let port = { (c: URLComponents) in c.port ?? (c.scheme?.lowercased() == "https" ? 443 : 80) }
        return url.scheme?.lowercased() == deployment.scheme?.lowercased()
            && url.host?.lowercased() == deployment.host?.lowercased()
            && port(url) == port(deployment)
    }
}
