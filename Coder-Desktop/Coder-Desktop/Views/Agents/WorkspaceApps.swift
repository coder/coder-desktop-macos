import CoderSDK
import SwiftUI

/// Everything both workspace surfaces need to know about one workspace: its agent, apps,
/// listening ports, and how to reach them. The composer pill and the sidebar section derived
/// all of this identically; this is that logic, once.
///
/// A struct rather than an observable: the derived values read straight through to the
/// service's published state, so each view's own `@State` still drives its refreshes.
/// `@MainActor` because it reads `AppState`, which is main-actor isolated.
@MainActor
struct WorkspaceApps {
    let workspaceID: UUID
    let workspaces: [CoderSDK.Workspace]
    let state: AppState
    /// Ports and shares are fetched per-view (they need an async load); pass what you hold.
    var ports: [WorkspaceAgentListeningPort] = []
    var shares: [WorkspaceAgentPortShare] = []
    var appHost = ""

    var workspace: CoderSDK.Workspace? {
        workspaces.first { $0.id == workspaceID }
    }

    var agent: WorkspaceAgent? {
        for resource in workspace?.latest_build.resources ?? [] {
            if let agent = resource.agents?.first { return agent }
        }
        return nil
    }

    var sshHost: String? {
        guard let name = workspace?.name else { return nil }
        return "\(name).\(state.hostnameSuffix)"
    }

    var status: String { workspace?.latest_build.status ?? "" }

    /// Mid-start workspaces still show their surface (dimmed) so it doesn't vanish during a
    /// 30–120s rebuild.
    var isStarting: Bool { ["starting", "pending"].contains(status) }

    /// Whether the workspace is reachable enough to show apps and ports at all.
    var isAvailable: Bool { status == "running" || isStarting }

    var dashboardURL: URL? {
        guard let base = state.baseAccessURL, let name = workspace?.name else { return nil }
        return base.appending(path: "@me/\(name)")
    }

    var entries: [AppEntry] {
        guard let workspace else { return [] }
        return workspaceAppEntries(workspace: workspace, state: state, sshHost: sshHost)
    }

    /// Listening ports the user hasn't shared — the ones only they can reach.
    var privatePorts: [WorkspaceAgentListeningPort] {
        let shared = Set(shares.map(\.port))
        return ports.filter { !shared.contains($0.port) }
    }

    /// A URL for a listening port: direct over Coder Connect when the tunnel is up, else
    /// through the deployment's wildcard app host.
    func portURL(_ port: Int, proto: String) -> URL? {
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
}
