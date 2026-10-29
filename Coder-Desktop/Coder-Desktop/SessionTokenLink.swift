import Foundation

/// Why an app link that needs a session token isn't given one.
enum SessionTokenBlockReason: Equatable {
    case untrustedURL
    case wrongDeployment(link: String, signedIn: URL)

    var description: String {
        switch self {
        case .untrustedURL:
            "This app's URL isn't trusted to sign you in to Coder. Ask your template administrator to fix the "
                + "app's url in the template's coder_app configuration."
        case let .wrongDeployment(link, signedIn):
            "This app signs in to \(link), but Coder Desktop is signed in to \(signedIn.absoluteString)."
        }
    }
}

/// Decides whether an external app link may receive the user's session token,
/// using the same rules as the Coder dashboard.
enum SessionTokenLink {
    static let placeholder = "$SESSION_TOKEN"

    private struct Handler {
        /// Scheme and authority, matched case-insensitively.
        let base: String
        /// Matched exactly, up to where the params start.
        let path: String
        var firstParam = ""
    }

    private static let handlers: [Handler] = [
        "vscode", "vscode-insiders", "windsurf", "devin", "cursor", "kiro", "positron", "antigravity",
        "antigravity-ide",
    ].flatMap { scheme in
        ["/open?", "/openDevContainer?"].map { path in Handler(base: "\(scheme)://coder.coder-remote", path: path) }
    } + [
        Handler(base: "jetbrains://gateway", path: "/coder?"),
        Handler(base: "jetbrains://gateway", path: "/com.coder.toolbox?"),
        // Gateway also handles non-Coder providers, such as `type=ssh`.
        Handler(base: "jetbrains-gateway://connect", path: "#", firstParam: "type=coder&"),
    ]

    static func isKnownHandler(_ appURL: String) -> Bool {
        handler(for: appURL) != nil
    }

    /// Returns nil if the link has no placeholder, or its only `url` is
    /// `signedInURL` or `dashboardURL`.
    static func blockReason(_ appURL: String, signedInURL: URL, dashboardURL: URL?) -> SessionTokenBlockReason? {
        guard appURL.contains(placeholder) else { return nil }
        guard appURL.components(separatedBy: placeholder).count == 2,
              let handler = handler(for: appURL)
        else { return .untrustedURL }

        // The placeholder is replaced raw, so it must be the raw `token` value.
        // Gateway doesn't decode names, IDEs decode values twice, and VS Code
        // ignores params after a `#`.
        let params = String(appURL.dropFirst(handler.base.count + handler.path.count))
        let entries = params.components(separatedBy: "&")
        guard entries.contains("token=\(placeholder)"),
              entries.allSatisfy({ entry in !entry.prefix { char in char != "=" }.contains("%") }),
              !params.contains("#"),
              let decoded = params.removingPercentEncoding,
              !decoded.unicodeScalars.contains("%"),
              let url = urlParam(params),
              urlParam(decoded) == url
        else { return .untrustedURL }

        let trusted = [signedInURL, dashboardURL].compactMap(\.self)
        return trusted.contains { trustedURL in isSameOrigin(url, trustedURL) }
            ? nil
            : .wrongDeployment(link: url, signedIn: signedInURL)
    }

    /// Only printable ASCII links match, so parsers can't drop a tab, LF or CR
    /// and `lowercased()` can't fold a Kelvin sign into `k`.
    private static func handler(for appURL: String) -> Handler? {
        guard appURL.unicodeScalars.allSatisfy({ scalar in (0x20 ..< 0x7F).contains(scalar.value) }) else {
            return nil
        }
        return handlers.first { handler in
            appURL.prefix(handler.base.count).lowercased() == handler.base
                && appURL.dropFirst(handler.base.count).hasPrefix(handler.path + handler.firstParam)
        }
    }

    /// Returns `url` if the names are unique and it's a bare http(s) origin,
    /// matched raw since parsing normalizes `/.` and drops an empty `?`.
    private static func urlParam(_ query: String) -> String? {
        // Split on scalars like `URLSearchParams`, since `&` followed by a
        // combining mark is one `Character`.
        let params = query.unicodeScalars.split(separator: "&").map { entry in
            entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map { part in
                let plain = String(part).replacingOccurrences(of: "+", with: " ", options: .literal)
                return plain.removingPercentEncoding ?? plain
            }
        }
        guard Set(params.map { param in param[0] }).count == params.count,
              let url = params.first(where: { param in param[0] == "url" && param.count == 2 })?[1],
              url.range(of: #"^https?://[^/\\?#@\s]+/?\z"#, options: [.regularExpression, .caseInsensitive]) != nil
        else { return nil }
        return url
    }

    private static func isSameOrigin(_ link: String, _ url: URL) -> Bool {
        guard let origin = URL(string: link) else { return false }
        let port = { (target: URL) in target.port ?? (target.scheme?.lowercased() == "https" ? 443 : 80) }
        return origin.scheme?.lowercased() == url.scheme?.lowercased()
            && origin.host?.lowercased() == url.host?.lowercased()
            && port(origin) == port(url)
    }
}
