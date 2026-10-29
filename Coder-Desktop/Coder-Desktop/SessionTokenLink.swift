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

    /// `base` (scheme and authority) is case-insensitive; `path` runs through
    /// the first param and is exact.
    private static let handlers: [(base: String, path: String)] = [
        "vscode", "vscode-insiders", "windsurf", "devin", "cursor", "kiro", "positron", "antigravity",
        "antigravity-ide",
    ].flatMap { scheme in
        ["/open?", "/openDevContainer?"].map { path in ("\(scheme)://coder.coder-remote", path) }
    } + [
        ("jetbrains://gateway", "/coder?"),
        ("jetbrains://gateway", "/com.coder.toolbox?"),
        // Gateway also handles non-Coder providers, such as `type=ssh`.
        ("jetbrains-gateway://connect", "#type=coder&"),
    ]

    static func isKnownHandler(_ appURL: String) -> Bool {
        handler(for: appURL) != nil
    }

    /// Returns why the link can't get a session token, or nil if it has no
    /// placeholder or its only `url` is `signedInURL` or `dashboardURL`.
    static func blockReason(_ appURL: String, signedInURL: URL, dashboardURL: URL?) -> SessionTokenBlockReason? {
        guard appURL.contains(placeholder) else { return nil }
        // Printable ASCII only: some parsers drop tab, LF and CR, so `ur\tl`
        // could become `url`, and it keeps grapheme comparisons byte-exact.
        guard appURL.unicodeScalars.allSatisfy({ scalar in (0x20 ..< 0x7F).contains(scalar.value) }),
              appURL.components(separatedBy: placeholder).count == 2,
              let handler = handler(for: appURL)
        else { return .untrustedURL }

        let paramsStart = handler.base.count + handler.path.prefix { char in char != "?" && char != "#" }.count + 1
        let params = String(appURL.dropFirst(paramsStart))
        let entries = params.components(separatedBy: "&")
        // The placeholder is replaced raw, so it must be the raw `token` entry,
        // and unique names make it the only `token`. Gateway doesn't decode
        // names, and IDEs decode values twice.
        guard !params.contains("#"),
              entries.contains("token=\(placeholder)"),
              entries.allSatisfy({ entry in !entry.prefix { char in char != "=" }.contains("%") }),
              let decoded = params.removingPercentEncoding,
              !decoded.unicodeScalars.contains("%"),
              let origin = linkOrigin(params),
              linkOrigin(decoded) == origin
        else { return .untrustedURL }

        let trusted = [signedInURL, dashboardURL].compactMap(\.self)
        return trusted.contains { url in sameOrigin(origin, url) }
            ? nil
            : .wrongDeployment(link: origin, signedIn: signedInURL)
    }

    private static func handler(for appURL: String) -> (base: String, path: String)? {
        // Compare UTF-8 with ASCII-only case folding, so a Kelvin sign isn't `k`.
        let bytes = appURL.utf8
        return handlers.first { handler in
            let base = handler.base.utf8
            let folded = bytes.prefix(base.count).map { byte in (65 ... 90).contains(byte) ? byte + 32 : byte }
            return folded.elementsEqual(base) && bytes.dropFirst(base.count).starts(with: handler.path.utf8)
        }
    }

    /// Returns the `url` param if every name is unique and `url` is a bare
    /// http(s) origin. Matched raw, since parsing normalizes `/.` and drops an
    /// empty `?`.
    private static func linkOrigin(_ query: String) -> String? {
        let params = parseQuery(query)
        guard Set(params.map(\.name)).count == params.count,
              let url = params.first(where: { param in param.name == "url" })?.value,
              url.range(of: #"^https?://[^/\\?#@\s]+/?\z"#, options: [.regularExpression, .caseInsensitive]) != nil
        else { return nil }
        return url
    }

    /// Parsed like `URLSearchParams`, split on scalars since `&` followed by a
    /// combining mark is one `Character`.
    private static func parseQuery(_ query: String) -> [(name: String, value: String)] {
        query.unicodeScalars.split(separator: "&").map { entry in
            let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map { part in
                let plain = String(part).replacingOccurrences(of: "+", with: " ", options: .literal)
                return plain.removingPercentEncoding ?? plain
            }
            return (parts[0], parts.count > 1 ? parts[1] : "")
        }
    }

    private static func sameOrigin(_ origin: String, _ url: URL) -> Bool {
        guard let lhs = URLComponents(string: origin),
              let rhs = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return false }
        let port = { (components: URLComponents) in
            components.port ?? (components.scheme?.lowercased() == "https" ? 443 : 80)
        }
        return lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && port(lhs) == port(rhs)
    }
}
