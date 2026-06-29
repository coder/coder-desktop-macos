import CoderSDK
import SwiftUI

/// Persistent right-panel section for the session's attached workspace: apps (click to open),
/// ports (listening + shared), SSH copy, and a dashboard link.
struct WorkspaceSidebarSection<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    @EnvironmentObject var state: AppState
    let workspaceID: UUID
    /// When set, port rows open in the caller's browser panel instead of the system browser.
    var onOpenPort: ((URL) -> Void)?

    @State private var isExpanded = true
    @State private var portsExpanded = false
    @State private var ports: [WorkspaceAgentListeningPort] = []
    @State private var shares: [WorkspaceAgentPortShare] = []
    @State private var appHost = ""
    @State private var portsLoaded = false

    private var workspace: CoderSDK.Workspace? {
        agents.workspaces.first { $0.id == workspaceID }
    }

    private var agent: WorkspaceAgent? {
        for resource in workspace?.latest_build.resources ?? [] {
            if let a = resource.agents?.first { return a }
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
        if let workspace, status == "running" || isStarting {
            let e = entries
            VStack(spacing: 0) {
                sectionHeader(workspace)
                if isExpanded {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(e) { entry in appRow(entry) }
                            portsHeader
                            if portsExpanded { portsContent }
                        }
                    }
                    .frame(maxHeight: 220)
                    Divider()
                    actionRow
                }
            }
            .opacity(isStarting ? 0.7 : 1)
            .disabled(isStarting)
            .task(id: workspaceID) {
                agents.loadWorkspaceAppIcons(e.compactMap(\.iconURL))
                await reloadPorts()
            }
        }
    }

    private func sectionHeader(_ workspace: CoderSDK.Workspace) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                Image(systemName: "display").font(.caption2).foregroundStyle(.secondary)
                Text(workspace.name).font(.caption).fontWeight(.medium).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, Theme.Size.trayInset)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(status.isEmpty ? workspace.name : "Workspace \(status)")
        .accessibilityLabel("Workspace \(workspace.name)\(status.isEmpty ? "" : ", \(status)")")
    }

    private func appRow(_ entry: AppEntry) -> some View {
        Button { NSWorkspace.shared.open(entry.openURL) } label: {
            HStack(spacing: 8) {
                if let icon = agents.workspaceAppIcon(entry.iconURL) {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 14, height: 14)
                } else {
                    Image(systemName: "app.dashed").font(.caption).foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                }
                Text(entry.name).font(.caption).lineLimit(1)
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Theme.Size.trayInset)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(entry.name)")
    }

    private var portsHeader: some View {
        Button {
            Task { await reloadPorts() }
            withAnimation(.easeOut(duration: 0.12)) { portsExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: portsExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                Image(systemName: "network").font(.caption2).foregroundStyle(.secondary)
                Text(portsLoaded ? "Ports (\(ports.count))" : "Ports").font(.caption)
                Spacer()
            }
            .padding(.horizontal, Theme.Size.trayInset)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ports")
    }

    @ViewBuilder
    private var portsContent: some View {
        if portsLoaded, privatePorts.isEmpty, shares.isEmpty {
            Text("No open ports detected.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Size.trayInset + 14)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        ForEach(privatePorts) { port in
            portRow("\(port.port)  \(port.process_name)", port: port.port, proto: "http")
        }
        if !shares.isEmpty {
            Text("Shared").font(.caption2).foregroundStyle(.tertiary)
                .padding(.horizontal, Theme.Size.trayInset + 14)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(shares) { share in
                portRow(
                    "\(share.port)  \(share.share_level.capitalized)",
                    port: share.port, proto: share.protocol
                )
            }
        }
        if let url = dashboardURL {
            Button { NSWorkspace.shared.open(url) } label: {
                Label("Manage sharing", systemImage: "arrow.up.right.square")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Size.trayInset + 14)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func portRow(_ title: String, port: Int, proto: String) -> some View {
        if let url = portURL(port, proto: proto) {
            Button {
                if let onOpenPort { onOpenPort(url) } else { NSWorkspace.shared.open(url) }
            } label: {
                Text(verbatim: title).font(.caption)
                    .padding(.horizontal, Theme.Size.trayInset + 14)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Text(verbatim: title).font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Size.trayInset + 14)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            if let host = sshHost {
                Button { copyToPasteboard("ssh \(host)") } label: {
                    Label("SSH", systemImage: "terminal").font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Copy SSH command: ssh \(host)")
                .accessibilityLabel("Copy SSH command")
            }
            Spacer()
            if let url = dashboardURL {
                Button { NSWorkspace.shared.open(url) } label: {
                    HStack(spacing: 3) {
                        Text("View").font(.caption)
                        Image(systemName: "arrow.up.right.square").font(.caption2)
                    }
                }
                .buttonStyle(.borderless)
                .help("Open workspace in browser")
                .accessibilityLabel("Open workspace in browser")
            }
        }
        .padding(.horizontal, Theme.Size.trayInset)
        .padding(.vertical, 5)
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
}
