import CoderSDK
import os
import SwiftUI

/// WorkspaceGroupView renders one workspace's row in the tray using native
/// macOS containers (`DisclosureGroup` for the workspace and `GroupBox` for
/// each sub-agent) so the visual treatment matches the rest of the system.
///
/// Single-agent and offline workspaces stay flat — drilling in adds nothing.
/// Multi-agent workspaces use `DisclosureGroup`: the system chevron handles
/// expansion, and the disclosure content lists each top-level agent inline
/// with apps. Each sub-agent (devcontainer) is wrapped in its own `GroupBox`
/// labelled "Container" with a cube glyph, mirroring the dashboard's compact
/// devcontainer treatment. Parent apps are hidden by default when any child
/// has apps; a per-row toggle reveals them on demand.
struct WorkspaceGroupView: View {
    @EnvironmentObject var state: AppState
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "VPNMenu")

    let group: WorkspaceGroup
    let baseAccessURL: URL
    @Binding var expandedItem: UUID?
    @Binding var userInteracted: Bool
    /// Callback fired for each agent we resolve from the HTTP API, so the VPN
    /// service can update the agent's parentID. WorkspaceGroupView is non-
    /// generic and can't carry the VPN service as an environment object.
    var setAgentParentID: (UUID, UUID?) -> Void = { _, _ in }

    @State private var appsByAgent: [UUID: [WorkspaceApp]] = [:]
    @State private var portsByAgent: [UUID: [WorkspaceAgentListeningPort]] = [:]
    @State private var loadingApps: Bool = false
    @State private var hasLoadedApps: Bool = false
    /// Parents whose apps the user explicitly chose to reveal (overrides the
    /// default "hide parent apps when a child has apps" behavior).
    @State private var revealedParents: Set<UUID> = []

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { expandedItem == group.id },
            set: { expand in
                userInteracted = true
                withAnimation(.snappy(duration: Theme.Animation.collapsibleDuration)) {
                    expandedItem = expand ? group.id : nil
                }
            }
        )
    }

    var body: some View {
        if group.agents.count <= 1 {
            // Flat row for single-agent or offline workspaces.
            let item: VPNMenuItem = group.agents.first.map { .agent($0) }
                ?? .offlineWorkspace(group.workspace)
            MenuItemView(
                item: item,
                baseAccessURL: baseAccessURL,
                expandedItem: $expandedItem,
                userInteracted: $userInteracted,
                displayLabel: group.workspace.name
            )
        } else {
            DisclosureGroup(isExpanded: isExpanded) {
                expandedContent
            } label: {
                WorkspaceDisclosureLabel(
                    name: group.workspace.name,
                    plainName: "\(group.workspace.name).\(state.hostnameSuffix)",
                    wsURL: baseAccessURL.appending(path: "@me").appending(path: group.workspace.name)
                )
            }
            .padding(.horizontal, Theme.Size.trayPadding)
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        Group {
            if loadingApps, !hasLoadedApps {
                CircularProgressView(value: nil, strokeWidth: 3, diameter: 15)
                    .padding(.top, 5)
            } else {
                ForEach(group.topLevelAgents) { parent in
                    AgentDetailRow(
                        agent: parent,
                        apps: appsToShow(for: parent),
                        ports: portsByAgent[parent.id] ?? [],
                        appsToggle: appsToggle(for: parent)
                    )
                    // Each sub-agent gets its own GroupBox so multiple
                    // devcontainers under the same parent stay distinct.
                    ForEach(group.children(of: parent.id)) { child in
                        GroupBox {
                            AgentDetailRow(
                                agent: child,
                                apps: appsByAgent[child.id] ?? [],
                                ports: portsByAgent[child.id] ?? []
                            )
                        } label: {
                            Label("Container", systemImage: "cube")
                                .font(.caption)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.task(id: group.id) { await loadApps() }
    }

    /// Hide a parent agent's apps when any of its direct children have apps —
    /// the child apps are the relevant ones in that case (matches the web UI).
    /// The user can override per-parent via the row's apps toggle.
    private func appsToShow(for agent: Agent) -> [WorkspaceApp] {
        let myApps = appsByAgent[agent.id] ?? []
        guard hasHiddenParentApps(for: agent) else { return myApps }
        return revealedParents.contains(agent.id) ? myApps : []
    }

    /// True when this agent has its own apps but they're being hidden because
    /// a child has apps. Used to gate the show/hide toggle in the row.
    private func hasHiddenParentApps(for agent: Agent) -> Bool {
        let myApps = appsByAgent[agent.id] ?? []
        guard !myApps.isEmpty else { return false }
        let children = group.children(of: agent.id)
        return children.contains { !(appsByAgent[$0.id] ?? []).isEmpty }
    }

    private func appsToggle(for agent: Agent) -> AgentDetailRow.AppsToggle? {
        guard hasHiddenParentApps(for: agent) else { return nil }
        let isShown = revealedParents.contains(agent.id)
        return AgentDetailRow.AppsToggle(isShown: isShown) {
            if isShown {
                revealedParents.remove(agent.id)
            } else {
                revealedParents.insert(agent.id)
            }
        }
    }

    /// Fetch every agent's data so we can render the tree with apps. Devcontainer
    /// sub-agents aren't in the workspace endpoint's `resources` (they're
    /// spawned at runtime, outside the Terraform graph), so for any agent we
    /// don't see in the workspace response we fall back to a per-agent fetch
    /// which always knows about sub-agents.
    private func loadApps() async {
        guard let client = state.client,
              let baseAccessURL = state.baseAccessURL,
              let sessionToken = state.sessionToken
        else { return }
        loadingApps = true
        defer { loadingApps = false }
        let workspace: CoderSDK.Workspace
        do {
            workspace = try await retry(floor: .milliseconds(100), ceil: .seconds(10)) {
                do {
                    return try await client.workspace(group.id)
                } catch {
                    logger.error("Failed to load workspace \(group.workspace.name): \(error.localizedDescription)")
                    throw error
                }
            }
        } catch { return } // Task cancelled
        let sdkAgents = workspace.latest_build.resources.compactMap(\.agents).flatMap(\.self)
        var result: [UUID: [WorkspaceApp]] = [:]
        var seenIDs: Set<UUID> = []
        for sdkAgent in sdkAgents {
            seenIDs.insert(sdkAgent.id)
            guard let agent = group.agents.first(where: { $0.id == sdkAgent.id }) else { continue }
            result[agent.id] = agentToApps(logger, sdkAgent, agent.primaryHost, baseAccessURL, sessionToken)
            setAgentParentID(agent.id, sdkAgent.parent_id)
        }
        // Fall back to per-agent fetches for anything we know about from the
        // VPN proto but didn't see in the workspace response (sub-agents).
        for agent in group.agents where !seenIDs.contains(agent.id) {
            do {
                let sdkAgent = try await client.workspaceAgent(agent.id)
                result[agent.id] = agentToApps(logger, sdkAgent, agent.primaryHost, baseAccessURL, sessionToken)
                setAgentParentID(agent.id, sdkAgent.parent_id)
            } catch {
                logger.error("Failed to load agent \(agent.name): \(error.localizedDescription)")
            }
        }
        appsByAgent = result
        hasLoadedApps = true
        await loadPorts(client: client)
    }

    /// Fetch listening ports per agent in parallel. The endpoint is per-agent
    /// (no batch), and only Linux agents return ports — others return [].
    private func loadPorts(client: Client) async {
        await withTaskGroup(of: (UUID, [WorkspaceAgentListeningPort]).self) { gp in
            for agent in group.agents {
                gp.addTask {
                    do {
                        let res = try await client.workspaceAgentListeningPorts(agent.id)
                        return (agent.id, res.ports)
                    } catch {
                        return (agent.id, [])
                    }
                }
            }
            var result: [UUID: [WorkspaceAgentListeningPort]] = [:]
            for await (id, ports) in gp where !ports.isEmpty {
                result[id] = ports
            }
            portsByAgent = result
        }
    }
}

/// Label slot for the DisclosureGroup: workspace name + trailing globe button.
/// The Button absorbs taps so opening the workspace page doesn't also toggle
/// the disclosure.
private struct WorkspaceDisclosureLabel: View {
    @Environment(\.openURL) private var openURL

    let name: String
    let plainName: String
    let wsURL: URL

    var body: some View {
        HStack {
            Text(name)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(plainName)
            Spacer()
            Button {
                openURL(wsURL)
            } label: {
                Image(systemName: "globe")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 12))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Open in browser")
        }
        .contentShape(Rectangle())
    }
}
