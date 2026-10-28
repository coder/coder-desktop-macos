@testable import Coder_Desktop
import Foundation
import Testing

struct SessionTokenLinkTests {
    let deployment = URL(string: "https://coder.example.com/")!

    /// A link with `url` set to `origin` and the placeholder as `token`.
    static func link(_ prefix: String, origin: String = "https://coder.example.com", extra: String = "") -> String {
        "\(prefix)url=\(origin)&token=\(SessionTokenLink.placeholder)\(extra)"
    }

    func trusted(_ url: String) -> Bool {
        SessionTokenLink.isDestinationTrusted(url, deploymentURL: deployment)
    }

    @Test(arguments: [
        "vscode://coder.coder-remote/open?owner=a&",
        "cursor://coder.coder-remote/openDevContainer?",
        "VSCode://Coder.Coder-Remote/open?",
        "jetbrains://gateway/coder?",
        "jetbrains://gateway/com.coder.toolbox?",
        "jetbrains-gateway://connect#type=coder&",
    ])
    func trustedHandler(prefix: String) {
        #expect(trusted(Self.link(prefix)))
    }

    @Test(arguments: [
        "https://coder.example.com/",
        "https://CODER.example.com",
        "https://coder.example.com:443",
        "https%3A%2F%2Fcoder.example.com",
    ])
    func trustedOrigin(origin: String) {
        #expect(trusted(Self.link("vscode://coder.coder-remote/open?", origin: origin)))
    }

    @Test(arguments: [
        "vscode://other.ext/open?",
        "coder://open?",
        "vscode:coder.coder-remote/open?",
        "vscode://x@coder.coder-remote/open?",
        "vscode://coder.coder-remote/open/../open?",
        "vscode://coder.coder-remote/open#",
        "jetbrains-gateway://connect?",
        "jetbrains-gateway://connect#type=ssh&",
        "\u{212A}iro://coder.coder-remote/open?",
    ])
    func untrustedHandler(prefix: String) {
        #expect(!trusted(Self.link(prefix)))
    }

    @Test(arguments: [
        "https://other.example",
        "https://coder.example.com:1",
        "http://coder.example.com",
        "https%3A%2F%2Fother.example",
        "not-a-url",
        "https://coder.example.com/@victim/ws.main/apps/x/",
        "https://user@coder.example.com",
        "https://other.example%252Fx@coder.example.com/",
        "https://coder.example.com/.",
        "https://coder.example.com?",
        "https://coder.example.com%0A",
    ])
    func untrustedOrigin(origin: String) {
        #expect(!trusted(Self.link("vscode://coder.coder-remote/open?", origin: origin)))
    }

    @Test(arguments: [
        "&url=https://other.example",
        "&t=$SESSION_TOKEN",
        "#url=https://other.example",
        "&type=ssh",
        "%FF",
        "&x=%26url%3Dhttps%253A%252F%252Fother.example",
        "&x=%252526url%25253Dhttps%25253A%25252F%25252Fother.example",
        "&x=%26url=%CC%81https://other.example",
        "&ur\tl=https://other.example",
        "&%75rl=https://other.example",
    ])
    func untrustedExtraParams(extra: String) {
        #expect(!trusted(Self.link("jetbrains-gateway://connect#type=coder&", extra: extra)))
    }

    @Test(arguments: [
        "vscode://coder.coder-remote/open?token=$SESSION_TOKEN",
        "vscode://coder.coder-remote/open?url=https://coder.example.com#token=$SESSION_TOKEN",
        "vscode://coder.coder-remote/open?x=1#&url=https://coder.example.com&token=$SESSION_TOKEN",
        "jetbrains://gateway/coder?url=https://coder.example.com&token=x&ide_download_link=https://other.example/$SESSION_TOKEN",
        "jetbrains-gateway://connect#type=coder&url=https://coder.example.com&token=%24SESSION_TOKEN&x=$SESSION_TOKEN",
    ])
    func untrustedTokenPlacement(url: String) {
        #expect(!trusted(url))
    }

    @Test
    func substitute() {
        let substitute = { (url: String, isSubAgentApp: Bool) in
            SessionTokenLink.substitute(url, deploymentURL: deployment, token: "secret", isSubAgentApp: isSubAgentApp)
        }
        let url = Self.link("vscode://coder.coder-remote/open?")
        #expect(substitute(url, false)?.hasSuffix("&token=secret") == true)
        #expect(substitute(url, true)?.hasSuffix("&token=") == true)
        #expect(substitute(Self.link("vscode://other.ext/open?"), false) == nil)
        #expect(substitute("someapp://anything?x=1", false) == "someapp://anything?x=1")
    }

    @Test(arguments: [
        ("vscode://coder.coder-remote/open?owner=a", true),
        ("jetbrains-gateway://connect#type=coder&workspace=b", true),
        ("jetbrains-gateway://connect#type=ssh&host=other.example", false),
        ("someapp://anything?x=1", false),
    ])
    func isKnownHandler(url: String, expected: Bool) {
        #expect(SessionTokenLink.isKnownHandler(url) == expected)
    }
}
