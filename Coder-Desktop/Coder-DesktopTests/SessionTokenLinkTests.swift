@testable import Coder_Desktop
import Foundation
import Testing

struct SessionTokenLinkTests {
    static let origin = "https://coder.example.com"
    static let token = SessionTokenLink.placeholder
    let deployment = URL(string: "https://coder.example.com/")!

    @Test(arguments: [
        "vscode://coder.coder-remote/open?owner=a&workspace=b&url=\(origin)&token=\(token)",
        "cursor://coder.coder-remote/open?url=\(origin)/&token=\(token)",
        "jetbrains://gateway/coder?&workspace=b&url=\(origin)&token=\(token)&ide_product_code=GO",
        "jetbrains-gateway://connect#type=coder&workspace=b&url=\(origin)&token=\(token)",
        "cursor://coder.coder-remote/openDevContainer?url=\(origin)&token=\(token)",
        "jetbrains://gateway/com.coder.toolbox?url=\(origin)&token=\(token)",
        "VSCode://Coder.Coder-Remote/open?url=\(origin)&token=\(token)",
        "vscode://coder.coder-remote/open?url=https://CODER.example.com&token=\(token)",
        "vscode://coder.coder-remote/open?url=https://coder.example.com:443&token=\(token)",
        "vscode://coder.coder-remote/open?url=https%3A%2F%2Fcoder.example.com&token=\(token)",
        "vscode://coder.coder-remote/open?folder=/home/a%20b&url=\(origin)&token=\(token)",
    ])
    func trusted(url: String) {
        #expect(SessionTokenLink.isDestinationTrusted(url, deploymentURL: deployment))
    }

    @Test(arguments: [
        "vscode://coder.coder-remote/open?url=https://other.example&token=\(token)",
        "vscode://coder.coder-remote/open?url=https://coder.example.com:1&token=\(token)",
        "vscode://coder.coder-remote/open?url=http://coder.example.com&token=\(token)",
        "vscode://coder.coder-remote/open?url=https%3A%2F%2Fother.example&token=\(token)",
        "vscode://coder.coder-remote/open?token=\(token)",
        "vscode://coder.coder-remote/open?url=not-a-url&token=\(token)",
        "vscode://coder.coder-remote/open?url=\(origin)&url=https://other.example&token=\(token)",
        "jetbrains-gateway://connect?url=https://other.example#url=\(origin)&token=\(token)",
        "jetbrains://gateway/coder?url=\(origin)&token=x&ide_download_link=https://other.example/\(token)",
        "vscode://coder.coder-remote/open?url=\(origin)&token=\(token)&t=\(token)",
        "vscode://coder.coder-remote/open?url=\(origin)#token=\(token)",
        "vscode://coder.coder-remote/open?url=\(origin)&token=\(token)#url=https://other.example",
        "vscode://other.ext/open?url=\(origin)&token=\(token)",
        "coder://open?url=\(origin)&token=\(token)",
        "vscode://coder.coder-remote/open?url=\(origin)/@victim/ws.main/apps/x/&token=\(token)",
        "vscode://coder.coder-remote/open?url=https://other.example%252Fx@coder.example.com/&token=\(token)",
        "vscode://coder.coder-remote/open?owner=x%26url%3Dhttps%253A%252F%252Fother.example&url=\(origin)&token=\(token)",
        "vscode://coder.coder-remote/open?x=%252526url%25253Dhttps%25253A%25252F%25252Fother.example&url=\(origin)"
            + "&token=\(token)",
        "vscode:coder.coder-remote/open?url=\(origin)&token=\(token)",
        "vscode://x@coder.coder-remote/open?url=\(origin)&token=\(token)",
        "vscode://coder.coder-remote/open/../open?url=\(origin)&token=\(token)",
        "vscode://coder.coder-remote/open#url=\(origin)&token=\(token)",
        "jetbrains-gateway://connect?url=\(origin)&token=\(token)",
        "jetbrains-gateway://connect#type=coder&url=\(origin)&token=%24SESSION_TOKEN"
            + "&ide_download_link=https://other.example/\(token)",
        "jetbrains-gateway://connect#type=coder&%75rl=\(origin)&token=\(token)",
        "jetbrains-gateway://connect#type=ssh&host=other.example&url=\(origin)&token=\(token)",
        "jetbrains-gateway://connect#type=coder&url=\(origin)&token=\(token)&type=ssh",
        "vscode://coder.coder-remote/open?x=1#&url=\(origin)&token=\(token)",
        "\u{212A}iro://coder.coder-remote/open?url=\(origin)&token=\(token)",
        "jetbrains-gateway://connect#type=coder&url=\(origin)&ur\tl=https://other.example&token=\(token)",
        "jetbrains-gateway://connect#type=coder&url=\(origin)&ur\nl=https://other.example&token=\(token)",
        "jetbrains-gateway://connect#type=coder&url=\(origin)&ur\rl=https://other.example&token=\(token)",
        "vscode://coder.coder-remote/open?url=\(origin)/.&token=\(token)",
        "vscode://coder.coder-remote/open?url=\(origin)?&token=\(token)",
        "vscode://coder.coder-remote/open?url=\(origin)%0A&token=\(token)",
        "vscode://coder.coder-remote/open?url=\(origin)&token=\(token)%FF",
        "vscode://coder.coder-remote/open?x=%25%CC%81&url=\(origin)&token=\(token)",
        "vscode://coder.coder-remote/open?url=\(origin)&token=\(token)&x=%26url=%CC%81https://other.example",
    ])
    func untrusted(url: String) {
        #expect(!SessionTokenLink.isDestinationTrusted(url, deploymentURL: deployment))
        #expect(
            SessionTokenLink.substitute(url, deploymentURL: deployment, token: "secret", isSubAgentApp: false) == nil
        )
    }

    @Test
    func substitute() {
        let url = "vscode://coder.coder-remote/open?url=\(Self.origin)&token=\(Self.token)"
        #expect(
            SessionTokenLink.substitute(url, deploymentURL: deployment, token: "secret", isSubAgentApp: false)
                == "vscode://coder.coder-remote/open?url=\(Self.origin)&token=secret"
        )
        #expect(
            SessionTokenLink.substitute(url, deploymentURL: deployment, token: "secret", isSubAgentApp: true)
                == "vscode://coder.coder-remote/open?url=\(Self.origin)&token="
        )
    }

    @Test
    func substituteNoPlaceholder() {
        let url = "someapp://anything?x=1"
        #expect(
            SessionTokenLink.substitute(url, deploymentURL: deployment, token: "secret", isSubAgentApp: false) == url
        )
    }

    @Test(arguments: [
        ("vscode://coder.coder-remote/open?owner=a&workspace=b", true),
        ("JetBrains://Gateway/coder?workspace=b", true),
        ("jetbrains-gateway://connect#type=coder&workspace=b", true),
        ("jetbrains-gateway://connect#type=ssh&host=other.example", false),
        ("vscode://other.ext/open?x=1", false),
        ("\u{212A}iro://coder.coder-remote/open?x=1", false),
        ("someapp://anything?x=1", false),
    ])
    func knownHandler(url: String, expected: Bool) {
        #expect(SessionTokenLink.isKnownHandler(url) == expected)
    }

    @Test(arguments: [
        ("https://coder.example.com", true),
        ("https://coder.example.com/", true),
        ("http://localhost:3000", true),
        ("https://coder.example.com/x", false),
        ("https://user@coder.example.com", false),
        ("https://coder.example.com?", false),
        ("https://coder.example.com#", false),
        ("https://coder.example.com/.", false),
        ("https://coder.example.com\n", false),
        ("https://coder example.com", false),
        ("coder.example.com", false),
    ])
    func bareOrigin(url: String, expected: Bool) {
        #expect(SessionTokenLink.isBareOrigin(url) == expected)
    }
}
