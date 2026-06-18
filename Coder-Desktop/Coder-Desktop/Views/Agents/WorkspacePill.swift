import AppKit
import CoderSDK
import SwiftUI

/// The composer's workspace pill (shown when a chat has an attached workspace). Mirrors the
/// web: workspace name + status, with a menu of ALL the workspace's apps (with their real
/// icons), listening ports, a Copy SSH command, and a link to open it in the dashboard.
struct WorkspacePill<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    @EnvironmentObject var state: AppState
    let workspaceID: UUID

    @State private var ports: [WorkspaceAgentListeningPort] = []
    @State private var shares: [WorkspaceAgentPortShare] = []
    @State private var appHost = ""
    @State private var portsLoaded = false

    private var workspace: CoderSDK.Workspace? {
        agents.workspaces.first { $0.id == workspaceID }
    }

    private var agent: WorkspaceAgent? {
        for resource in workspace?.latest_build.resources ?? [] {
            if let agent = resource.agents?.first { return agent }
        }
        return nil
    }

    private var agentID: UUID? {
        agent?.id
    }

    private var sshHost: String? {
        guard let name = workspace?.name else { return nil }
        return "\(name).\(state.hostnameSuffix)"
    }

    private var status: String {
        workspace?.latest_build.status ?? ""
    }

    private var dashboardURL: URL? {
        // Dashboard URLs are `/@owner/workspace-name` — never `/@me/<uuid>` (which doesn't resolve).
        guard let base = state.baseAccessURL, let name = workspace?.name else { return nil }
        return base.appending(path: "@me/\(name)")
    }

    /// All workspace apps with a resolvable URL — the VS Code display apps first (the web
    /// terminal is intentionally dropped), then the agent's web/native apps. Each with its
    /// icon URL.
    private var entries: [AppEntry] {
        guard let base = state.baseAccessURL else { return [] }
        let token = state.client?.token ?? ""
        let host = sshHost ?? workspace?.name ?? ""
        var result: [AppEntry] = []
        for resource in workspace?.latest_build.resources ?? [] {
            for agent in resource.agents ?? [] {
                for displayApp in agent.display_apps {
                    let app: WorkspaceApp?
                    let dir = agent.expanded_directory
                    app = switch displayApp {
                    case .vscode:
                        vscodeDisplayApp(hostname: host, baseIconURL: base, path: dir)
                    case .vscode_insiders:
                        vscodeInsidersDisplayApp(hostname: host, baseIconURL: base, path: dir)
                    default:
                        nil // drop web_terminal / port-forward / ssh helpers
                    }
                    if let app {
                        result.append(AppEntry(
                            id: app.slug, name: app.displayName, openURL: app.url, iconURL: app.icon
                        ))
                    }
                }
                for app in agent.apps {
                    guard let raw = app.url else { continue }
                    let urlString = raw.absoluteString.replacingOccurrences(of: "$SESSION_TOKEN", with: token)
                    guard let openURL = URL(string: urlString) else { continue }
                    result.append(AppEntry(
                        id: app.slug,
                        name: app.display_name ?? app.slug,
                        openURL: openURL,
                        iconURL: Self.resolvedIcon(app.icon, base: base)
                    ))
                }
            }
        }
        return result
    }

    private var isStarting: Bool {
        ["starting", "pending"].contains(status)
    }

    var body: some View {
        // Attached = running (full pill) or mid-start (dimmed, disabled — so the pill doesn't
        // silently vanish during a 30–120s rebuild). Stopped workspaces show nothing: no apps,
        // ports, or SSH to offer (matches the web, which drops the attachment when shut down).
        if let workspace, status == "running" || isStarting {
            Menu {
                ForEach(entries) { entry in
                    Button { NSWorkspace.shared.open(entry.openURL) } label: {
                        appLabel(entry)
                    }
                }
                portsMenu
                Divider()
                if let host = sshHost {
                    Button { copyToPasteboard("ssh \(host)") } label: {
                        Label("Copy SSH command", systemImage: "terminal")
                    }
                }
                if let dashboardURL {
                    Button { NSWorkspace.shared.open(dashboardURL) } label: {
                        Label("View workspace", systemImage: "arrow.up.right.square")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "display").font(.caption2)
                    Text(workspace.name).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(isStarting ? 0.5 : 1)
            .disabled(isStarting)
            .help(status.isEmpty ? workspace.name : "Workspace \(status)")
            .accessibilityLabel("Workspace \(workspace.name)\(status.isEmpty ? "" : ", \(status)")")
            .task(id: workspaceID) {
                agents.loadWorkspaceAppIcons(entries.compactMap(\.iconURL))
                await reloadPorts()
            }
        }
    }

    /// The Ports submenu, mirroring the web's: always present, listening + shared sections,
    /// an empty state, and a "Manage sharing" link. Refreshes when the submenu opens.
    private var portsMenu: some View {
        Menu(portsLoaded ? "Ports (\(ports.count))" : "Ports") {
            Section("Listening Ports") {
                if portsLoaded, privatePorts.isEmpty, shares.isEmpty {
                    Text("No open ports detected.")
                }
                ForEach(privatePorts) { port in
                    portRow("\(port.port)  \(port.process_name)", port: port.port, proto: "http")
                }
            }
            .onAppear { Task { await reloadPorts() } }
            if !shares.isEmpty {
                Section("Shared Ports") {
                    ForEach(shares) { share in
                        portRow(
                            "\(share.port)  \(share.share_level.capitalized)",
                            port: share.port, proto: share.protocol
                        )
                    }
                }
            }
            Divider()
            if let dashboardURL {
                Button { NSWorkspace.shared.open(dashboardURL) } label: {
                    Label("Manage sharing", systemImage: "arrow.up.right.square")
                }
            }
        }
    }

    /// Listening ports not explicitly shared (shared ones bubble to their own section).
    private var privatePorts: [WorkspaceAgentListeningPort] {
        let sharedNumbers = Set(shares.map(\.port))
        return ports.filter { !sharedNumbers.contains($0.port) }
    }

    @ViewBuilder
    private func portRow(_ title: String, port: Int, proto: String) -> some View {
        if let url = portURL(port, proto: proto) {
            Button { NSWorkspace.shared.open(url) } label: { Text(verbatim: title) }
        } else {
            Text(verbatim: title)
        }
    }

    /// Direct over the Coder Connect tunnel (`{proto}://{workspace}.{suffix}:{port}`) — the
    /// native advantage, no proxy hop. Falls back to the web's coderd port-forward proxy URL
    /// (`{port}--{agent}--{workspace}--{owner}.{appHost}`) when no tunnel host is available.
    private func portURL(_ port: Int, proto: String) -> URL? {
        if let host = sshHost {
            return URL(string: "\(proto)://\(host):\(port)")
        }
        guard !appHost.isEmpty, let agentName = agent?.name, let workspace,
              let owner = workspace.owner_name, let scheme = state.baseAccessURL?.scheme
        else { return nil }
        let suffix = proto == "https" ? "s" : ""
        let subdomain = "\(port)\(suffix)--\(agentName)--\(workspace.name)--\(owner)"
        return URL(string: "\(scheme)://\(appHost.replacingOccurrences(of: "*", with: subdomain))")
    }

    private func reloadPorts() async {
        if appHost.isEmpty { appHost = await agents.appHost() ?? "" }
        if let agentID { ports = await agents.listeningPorts(agentID: agentID) }
        if let agentName = agent?.name {
            shares = await agents.portShares(workspaceID: workspaceID).filter { $0.agent_name == agentName }
        }
        portsLoaded = true
    }

    private func appLabel(_ entry: AppEntry) -> some View {
        Label {
            Text(entry.name)
        } icon: {
            if let icon = agents.workspaceAppIcon(entry.iconURL) {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            } else {
                Image(systemName: "app.dashed")
            }
        }
    }

    /// Resolves a possibly-relative app icon URL against the deployment base.
    private static func resolvedIcon(_ icon: URL?, base: URL) -> URL? {
        guard let icon else { return nil }
        guard var components = URLComponents(url: icon, resolvingAgainstBaseURL: false) else { return icon }
        if components.host == nil {
            components.scheme = base.scheme
            components.host = base.host(percentEncoded: false)
            components.port = base.port
        }
        return components.url
    }
}

private struct AppEntry: Identifiable {
    let id: String
    let name: String
    let openURL: URL
    let iconURL: URL?
}
