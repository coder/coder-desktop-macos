import AppKit
import CoderSDK
import SwiftUI

// Shared data model used by WorkspacePill and WorkspaceSidebarSection.
struct AppEntry: Identifiable {
    let id: String
    let name: String
    let openURL: URL
    let iconURL: URL?
}

/// Builds the app list (display apps + workspace apps) from all agents in a workspace.
@MainActor
func workspaceAppEntries(workspace: CoderSDK.Workspace, state: AppState, sshHost: String?) -> [AppEntry] {
    guard let base = state.baseAccessURL else { return [] }
    let token = state.client?.token ?? ""
    let host = sshHost ?? workspace.name
    return (workspace.latest_build.resources ?? []).flatMap { resource in
        (resource.agents ?? []).flatMap { agent in
            agent.display_apps.compactMap { displayAppEntry($0, agent: agent, host: host, base: base) }
                + agent.apps.compactMap { agentAppEntry($0, token: token, base: base) }
        }
    }
}

private func displayAppEntry(_ displayApp: DisplayApp, agent: WorkspaceAgent, host: String, base: URL) -> AppEntry? {
    let dir = agent.expanded_directory
    let app: Coder_Desktop.WorkspaceApp? = switch displayApp {
    case .vscode: vscodeDisplayApp(hostname: host, baseIconURL: base, path: dir)
    case .vscode_insiders: vscodeInsidersDisplayApp(hostname: host, baseIconURL: base, path: dir)
    default: nil
    }
    return app.map { AppEntry(id: $0.slug, name: $0.displayName, openURL: $0.url, iconURL: $0.icon) }
}

private func agentAppEntry(_ app: CoderSDK.WorkspaceApp, token: String, base: URL) -> AppEntry? {
    guard let raw = app.url else { return nil }
    let urlStr = raw.absoluteString.replacingOccurrences(of: "$SESSION_TOKEN", with: token)
    guard let openURL = URL(string: urlStr) else { return nil }
    return AppEntry(
        id: app.slug,
        name: app.display_name ?? app.slug,
        openURL: openURL,
        iconURL: resolvedWorkspaceIconURL(app.icon, base: base)
    )
}

/// Resolves a relative workspace app icon URL to an absolute URL using the server base.
func resolvedWorkspaceIconURL(_ icon: URL?, base: URL) -> URL? {
    guard let icon else { return nil }
    guard var components = URLComponents(url: icon, resolvingAgainstBaseURL: false) else { return icon }
    if components.host == nil {
        components.scheme = base.scheme
        components.host = base.host(percentEncoded: false)
        components.port = base.port
    }
    return components.url
}

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

    private var sshHost: String? {
        guard let name = workspace?.name else { return nil }
        return "\(name).\(state.hostnameSuffix)"
    }

    private var status: String { workspace?.latest_build.status ?? "" }
    private var isStarting: Bool { ["starting", "pending"].contains(status) }

    private var dashboardURL: URL? {
        guard let base = state.baseAccessURL, let name = workspace?.name else { return nil }
        return base.appending(path: "@me/\(name)")
    }

    private var entries: [AppEntry] {
        guard let workspace else { return [] }
        return workspaceAppEntries(workspace: workspace, state: state, sshHost: sshHost)
    }

    private var privatePorts: [WorkspaceAgentListeningPort] {
        let shared = Set(shares.map(\.port))
        return ports.filter { !shared.contains($0.port) }
    }

    var body: some View {
        // Attached = running (full pill) or mid-start (dimmed, disabled — so the pill doesn't
        // silently vanish during a 30–120s rebuild). Stopped workspaces show nothing: no apps,
        // ports, or SSH to offer (matches the web, which drops the attachment when shut down).
        if let workspace, status == "running" || isStarting {
            let e = entries
            Menu {
                ForEach(e) { entry in
                    Button { NSWorkspace.shared.open(entry.openURL) } label: { appLabel(entry) }
                }
                portsMenu
                Divider()
                if let host = sshHost {
                    Button { copyToPasteboard("ssh \(host)") } label: {
                        Label("Copy SSH command", systemImage: "terminal")
                    }
                }
                if let url = dashboardURL {
                    Button { NSWorkspace.shared.open(url) } label: {
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
                agents.loadWorkspaceAppIcons(e.compactMap(\.iconURL))
                await reloadPorts()
            }
        }
    }

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
            if let url = dashboardURL {
                Button { NSWorkspace.shared.open(url) } label: {
                    Label("Manage sharing", systemImage: "arrow.up.right.square")
                }
            }
        }
    }

    @ViewBuilder
    private func portRow(_ title: String, port: Int, proto: String) -> some View {
        if let url = portURL(port, proto: proto) {
            Button { NSWorkspace.shared.open(url) } label: { Text(verbatim: title) }
        } else {
            Text(verbatim: title)
        }
    }

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
        if let a = agent {
            ports = await agents.listeningPorts(agentID: a.id)
            shares = await agents.portShares(workspaceID: workspaceID).filter { $0.agent_name == a.name }
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
}
