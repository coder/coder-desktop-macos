@testable import Coder_Desktop
import CoderSDK
import os
import Testing

@MainActor
@Suite
struct WorkspaceAppTests {
    let logger = Logger(subsystem: "com.coder.Coder-Desktop-Tests", category: "WorkspaceAppTests")
    let baseAccessURL = URL(string: "https://coder.example.com")!
    let sessionToken = "test-session-token"
    let host = "test-workspace.coder.test"

    @Test
    func testCreateWorkspaceApp_Success() throws {
        let sdkApp = CoderSDK.WorkspaceApp(
            id: UUID(),
            url: URL(string: "https://localhost:3000/app")!,
            external: true,
            slug: "test-app",
            display_name: "Test App",
            command: nil,
            icon: URL(string: "/icon/test-app.svg")!,
            subdomain: false,
            subdomain_name: nil
        )

        let workspaceApp = try WorkspaceApp(
            sdkApp,
            iconBaseURL: baseAccessURL,
            sessionToken: sessionToken,
            newAppHost: host
        )

        #expect(workspaceApp.slug == "test-app")
        #expect(workspaceApp.displayName == "Test App")
        #expect(workspaceApp.url.absoluteString == "https://test-workspace.coder.test:3000/app")
        #expect(workspaceApp.icon?.absoluteString == "https://coder.example.com/icon/test-app.svg")
    }

    @Test
    func testCreateWorkspaceApp_SessionTokenReplacement() throws {
        let sdkApp = CoderSDK.WorkspaceApp(
            id: UUID(),
            url: URL(string: "https://localhost:3000/app?token=$SESSION_TOKEN")!,
            external: true,
            slug: "token-app",
            display_name: "Token App",
            command: nil,
            icon: URL(string: "/icon/test-app.svg")!,
            subdomain: false,
            subdomain_name: nil
        )

        let workspaceApp = try WorkspaceApp(
            sdkApp,
            iconBaseURL: baseAccessURL,
            sessionToken: sessionToken,
            newAppHost: host
        )

        #expect(
            workspaceApp.url.absoluteString == "https://test-workspace.coder.test:3000/app?token=test-session-token"
        )
    }

    @Test
    func testCreateWorkspaceApp_MissingURL() throws {
        let sdkApp = CoderSDK.WorkspaceApp(
            id: UUID(),
            url: nil,
            external: true,
            slug: "no-url-app",
            display_name: "No URL App",
            command: nil,
            icon: nil,
            subdomain: false,
            subdomain_name: nil
        )

        #expect(throws: WorkspaceAppError.missingURL) {
            try WorkspaceApp(
                sdkApp,
                iconBaseURL: baseAccessURL,
                sessionToken: sessionToken,
                newAppHost: host
            )
        }
    }

    @Test
    func testCreateWorkspaceApp_CommandApp() throws {
        let sdkApp = CoderSDK.WorkspaceApp(
            id: UUID(),
            url: URL(string: "https://localhost:3000/app")!,
            external: true,
            slug: "command-app",
            display_name: "Command App",
            command: "echo 'hello'",
            icon: nil,
            subdomain: false,
            subdomain_name: nil
        )

        #expect(throws: WorkspaceAppError.isCommandApp) {
            try WorkspaceApp(
                sdkApp,
                iconBaseURL: baseAccessURL,
                sessionToken: sessionToken,
                newAppHost: host
            )
        }
    }

    @Test
    func testDisplayApps_VSCode() throws {
        let agent = createMockAgent(displayApps: [.vscode, .web_terminal, .ssh_helper, .port_forwarding_helper])

        let apps = agentToApps(logger, agent, host, baseAccessURL, sessionToken)

        #expect(apps.count == 1)
        #expect(apps[0].slug == "-vscode")
        #expect(apps[0].displayName == "VS Code Desktop")
        #expect(apps[0].url.absoluteString == "vscode://vscode-remote/ssh-remote+test-workspace.coder.test/home/user")
        #expect(apps[0].icon?.absoluteString == "https://coder.example.com/icon/code.svg")
    }

    @Test
    func testDisplayApps_VSCodeInsiders() throws {
        let agent = createMockAgent(
            displayApps: [
                .vscode_insiders,
                .web_terminal,
                .ssh_helper,
                .port_forwarding_helper,
            ]
        )

        let apps = agentToApps(logger, agent, host, baseAccessURL, sessionToken)

        #expect(apps.count == 1)
        #expect(apps[0].slug == "-vscode-insiders")
        #expect(apps[0].displayName == "VS Code Insiders Desktop")
        #expect(apps[0].icon?.absoluteString == "https://coder.example.com/icon/code.svg")
        #expect(
            apps[0].url.absoluteString == """
            vscode-insiders://vscode-remote/ssh-remote+test-workspace.coder.test/home/user
            """
        )
    }

    @Test
    func testAgentToApps_MultipleApps() throws {
        let sdkApp1 = CoderSDK.WorkspaceApp(
            id: UUID(),
            url: URL(string: "https://localhost:3000/app1")!,
            external: true,
            slug: "app1",
            display_name: "App 1",
            command: nil,
            icon: URL(string: "/icon/app1.svg")!,
            subdomain: false,
            subdomain_name: nil
        )

        let sdkApp2 = CoderSDK.WorkspaceApp(
            id: UUID(),
            url: URL(string: "https://localhost:3000/app2")!,
            external: true,
            slug: "app2",
            display_name: "App 2",
            command: nil,
            icon: URL(string: "/icon/app2.svg")!,
            subdomain: false,
            subdomain_name: nil
        )

        // Command app; skipped
        let sdkApp3 = CoderSDK.WorkspaceApp(
            id: UUID(),
            url: URL(string: "https://localhost:3000/app3")!,
            external: true,
            slug: "app3",
            display_name: "App 3",
            command: "echo 'skip me'",
            icon: nil,
            subdomain: false,
            subdomain_name: nil
        )

        // Web app skipped
        let sdkApp4 = CoderSDK.WorkspaceApp(
            id: UUID(),
            url: URL(string: "https://localhost:3000/app4")!,
            external: false,
            slug: "app4",
            display_name: "App 4",
            command: nil,
            icon: URL(string: "/icon/app4.svg")!,
            subdomain: false, subdomain_name: nil
        )

        let agent = createMockAgent(apps: [sdkApp1, sdkApp2, sdkApp3, sdkApp4], displayApps: [.vscode])
        let apps = agentToApps(logger, agent, host, baseAccessURL, sessionToken)

        #expect(apps.count == 3)
        let appSlugs = apps.map(\.slug)
        #expect(appSlugs.contains("app1"))
        #expect(appSlugs.contains("app2"))
        #expect(appSlugs.contains("-vscode"))
    }

    private func createMockAgent(
        apps: [CoderSDK.WorkspaceApp] = [],
        displayApps: [DisplayApp] = []
    ) -> CoderSDK.WorkspaceAgent {
        CoderSDK.WorkspaceAgent(
            id: UUID(),
            expanded_directory: "/home/user",
            apps: apps,
            display_apps: displayApps
        )
    }
}
