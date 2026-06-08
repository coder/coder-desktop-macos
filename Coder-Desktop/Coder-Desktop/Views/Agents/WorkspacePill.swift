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

    private var workspace: CoderSDK.Workspace? {
        agents.workspaces.first { $0.id == workspaceID }
    }

    private var agentID: UUID? {
        for resource in workspace?.latest_build.resources ?? [] {
            if let agent = resource.agents?.first { return agent.id }
        }
        return nil
    }

    private var sshHost: String? {
        guard let name = workspace?.name else { return nil }
        return "\(name).\(state.hostnameSuffix)"
    }

    private var status: String { workspace?.latest_build.status ?? "" }

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
                    switch displayApp {
                    case .vscode:
                        app = vscodeDisplayApp(hostname: host, baseIconURL: base, path: dir)
                    case .vscode_insiders:
                        app = vscodeInsidersDisplayApp(hostname: host, baseIconURL: base, path: dir)
                    default:
                        app = nil // drop web_terminal / port-forward / ssh helpers
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

    var body: some View {
        if let workspace {
            Menu {
                ForEach(entries) { entry in
                    Button { NSWorkspace.shared.open(entry.openURL) } label: {
                        appLabel(entry)
                    }
                }
                if !ports.isEmpty, let host = sshHost {
                    Menu("Ports (\(ports.count))") {
                        ForEach(ports) { port in
                            Button {
                                if let url = URL(string: "http://\(host):\(port.port)") { NSWorkspace.shared.open(url) }
                            } label: {
                                Text(verbatim: "\(port.port)  \(port.process_name)")
                            }
                        }
                    }
                }
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
            .help(status.isEmpty ? workspace.name : "Workspace \(status)")
            .task(id: workspaceID) {
                agents.loadWorkspaceAppIcons(entries.compactMap(\.iconURL))
                if let agentID { ports = await agents.listeningPorts(agentID: agentID) }
            }
        }
    }

    @ViewBuilder
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
