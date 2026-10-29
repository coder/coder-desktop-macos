@testable import Coder_Desktop
import Foundation
import Testing

struct SessionTokenLinkTests {
    static let signedIn = URL(string: "https://coder.example.com/")!
    static let dashboard = URL(string: "https://dashboard.example/")!

    struct LinkCase: CustomStringConvertible {
        let description: String
        let url: String
        let expected: SessionTokenBlockReason?
    }

    /// A link with `url` set to `origin` and the placeholder as `token`.
    static func link(_ prefix: String, origin: String = "https://coder.example.com", extra: String = "") -> String {
        "\(prefix)url=\(origin)&token=\(SessionTokenLink.placeholder)\(extra)"
    }

    static func trusted(_ description: String, _ url: String) -> LinkCase {
        LinkCase(description: description, url: url, expected: nil)
    }

    static func untrusted(_ description: String, _ url: String) -> LinkCase {
        LinkCase(description: description, url: url, expected: .untrustedURL)
    }

    static func wrongDeployment(_ description: String, origin: String) -> LinkCase {
        LinkCase(
            description: description,
            url: link("vscode://coder.coder-remote/open?", origin: origin),
            expected: .wrongDeployment(link: origin, signedIn: signedIn)
        )
    }

    static let vscode = "vscode://coder.coder-remote/open?"
    static let gateway = "jetbrains-gateway://connect#type=coder&"

    @Test("Block reasons", arguments: [
        trusted("no placeholder", "someapp://anything?x=1"),
        trusted("VS Code", link("vscode://coder.coder-remote/open?owner=a&")),
        trusted("dev container handler", link("cursor://coder.coder-remote/openDevContainer?")),
        trusted("uppercase scheme and authority", link("VSCode://Coder.Coder-Remote/open?")),
        trusted("Gateway plugin", link("jetbrains://gateway/coder?")),
        trusted("Toolbox", link("jetbrains://gateway/com.coder.toolbox?")),
        trusted("Gateway fragment", link(gateway)),
        trusted("trailing slash", link(vscode, origin: "https://coder.example.com/")),
        trusted("uppercase host", link(vscode, origin: "https://CODER.example.com")),
        trusted("default port", link(vscode, origin: "https://coder.example.com:443")),
        trusted("encoded url value", link(vscode, origin: "https%3A%2F%2Fcoder.example.com")),
        trusted("dashboard URL", link(vscode, origin: "https://dashboard.example")),

        untrusted("unknown extension", link("vscode://other.ext/open?")),
        untrusted("unknown scheme", link("coder://open?")),
        untrusted("opaque handler", link("vscode:coder.coder-remote/open?")),
        untrusted("userinfo in handler", link("vscode://x@coder.coder-remote/open?")),
        untrusted("dot segments in handler", link("vscode://coder.coder-remote/open/../open?")),
        untrusted("VS Code params in fragment", link("vscode://coder.coder-remote/open#")),
        untrusted("Gateway params in query", link("jetbrains-gateway://connect?")),
        untrusted("non-Coder Gateway provider", link("jetbrains-gateway://connect#type=ssh&")),
        untrusted("tab in a param name", link(gateway, extra: "&ur\tl=https://other.example")),
        untrusted("second placeholder", link(gateway, extra: "&x=$SESSION_TOKEN")),
        untrusted("params after a fragment", link("\(vscode)x=1#&")),
        untrusted(
            "placeholder outside the raw token entry",
            "\(vscode)url=https://coder.example.com&token=%24SESSION_TOKEN&y=$SESSION_TOKEN"
        ),
        untrusted("encoded url name", "\(vscode)%75rl=https://coder.example.com&token=$SESSION_TOKEN"),
        untrusted("invalid percent encoding", link(gateway, extra: "&x=%FF")),
        untrusted("double-encoded url param", link(gateway, extra: "&x=%2526url%253Dhttps://other.example")),
        untrusted("duplicate url", link(gateway, extra: "&url=https://other.example")),
        untrusted("duplicate Gateway type", link(gateway, extra: "&type=ssh")),
        untrusted("url hidden by a combining mark", link(gateway, extra: "&x=%26url=%CC%81https://other.example")),
        untrusted("url smuggled in an encoded value", link(gateway, extra: "&x=a%26url%3Dhttps://other.example")),
        untrusted("no url", "\(vscode)token=$SESSION_TOKEN"),
        untrusted("url isn't a URL", link(vscode, origin: "not-a-url")),
        untrusted("url has a path", link(vscode, origin: "https://coder.example.com/@victim/ws.main/apps/x/")),
        untrusted("url has userinfo", link(vscode, origin: "https://user@coder.example.com")),
        untrusted("url has a dot segment", link(vscode, origin: "https://coder.example.com/.")),
        untrusted("url has an empty query", link(vscode, origin: "https://coder.example.com?")),

        wrongDeployment("another host", origin: "https://other.example"),
        wrongDeployment("another port", origin: "https://coder.example.com:1"),
        wrongDeployment("http instead of https", origin: "http://coder.example.com"),
    ])
    func blockReason(_ testCase: LinkCase) {
        #expect(
            SessionTokenLink.blockReason(testCase.url, signedInURL: Self.signedIn, dashboardURL: Self.dashboard)
                == testCase.expected
        )
    }

    @Test(arguments: [
        ("vscode://coder.coder-remote/open?owner=a", true),
        ("jetbrains-gateway://connect#type=coder&workspace=b", true),
        ("jetbrains-gateway://connect#type=ssh&host=other.example", false),
        ("\u{212A}iro://coder.coder-remote/open?", false),
        ("someapp://anything?x=1", false),
    ])
    func isKnownHandler(url: String, expected: Bool) {
        #expect(SessionTokenLink.isKnownHandler(url) == expected)
    }
}
