import CoderSDK
import os
import SwiftUI

/// WorkspaceGroupView renders one workspace's row in the tray.
///
/// Single-agent and offline workspaces render as a flat row (status dot,
/// copy, browser inline) since the workspace and the agent are effectively
/// the same thing — drilling in adds no information.
///
/// Multi-agent workspaces render as a collapsible header that, when
/// expanded, lists every top-level agent with its apps inline. Sub-agents
/// (devcontainer agents) are wrapped in a dashed "Container" box right
/// under their parent so the hierarchy is visible without indentation
/// gymnastics — the same shape the dashboard uses. Parent apps are hidden
/// when any child has apps of its own (also matches the dashboard).
struct WorkspaceGroupView: View {
    @EnvironmentObject var state: AppState
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "VPNMenu")

    let group: WorkspaceGroup
    let baseAccessURL: URL
    @Binding var expandedItem: UUID?
    @Binding var userInteracted: Bool
    /// Callback fired for each agent we resolve from the HTTP API, so the
    /// VPN service can update the agent's parentID. Routed through a closure
    /// because WorkspaceGroupView is non-generic and can't carry the VPN
    /// service as an environment object directly.
    var setAgentParentID: (UUID, UUID?) -> Void = { _, _ in }

    @State private var appsByAgent: [UUID: [WorkspaceApp]] = [:]
    @State private var portsByAgent: [UUID: [WorkspaceAgentListeningPort]] = [:]
    @State private var loadingApps: Bool = false
    @State private var hasLoadedApps: Bool = false
    /// Parents whose apps the user explicitly chose to reveal (overrides the
    /// default "hide parent apps when a child has apps" behavior).
    @State private var revealedParents: Set<UUID> = []

    private var isExpanded: Bool { expandedItem == group.id }

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
            VStack(spacing: 0) {
                WorkspaceHeaderRow(
                    group: group,
                    baseAccessURL: baseAccessURL,
                    isExpanded: isExpanded,
                    onToggle: toggleGroupExpansion
                )
                if isExpanded {
                    expandedContent
                }
            }
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
                    // Wrap each sub-agent in its own dashed box so multiple
                    // devcontainers under the same parent stay visually
                    // distinct. The cube glyph lives inline on the agent row
                    // (via leadingIcon) instead of a separate header line.
                    ForEach(group.children(of: parent.id)) { child in
                        SubAgentContainer {
                            AgentDetailRow(
                                agent: child,
                                apps: appsByAgent[child.id] ?? [],
                                ports: portsByAgent[child.id] ?? [],
                                leadingIcon: "cube",
                                leadingIconHelp: "Container"
                            )
                        }
                    }
                }
            }
        }.task(id: group.id) { await loadApps() }
    }

    private func toggleGroupExpansion() {
        userInteracted = true
        withAnimation(.snappy(duration: Theme.Animation.collapsibleDuration)) {
            expandedItem = expandedItem == group.id ? nil : group.id
        }
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
    /// Stored in @State so the row can decide to render a ports button.
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

/// Subtle dashed-border box that wraps a sub-agent's row + apps. The cube
/// glyph that signals "container" is rendered inline at the start of the
/// agent row (via AgentDetailRow.leadingIcon) so we don't need a dedicated
/// header line — saves vertical space, matches the dashboard's compact
/// devcontainer treatment.
struct SubAgentContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius)
                    .strokeBorder(
                        Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1, dash: [3])
                    )
            )
            .padding(.horizontal, Theme.Size.trayPadding)
            .padding(.vertical, 2)
    }
}

struct WorkspaceHeaderRow: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openURL) private var openURL

    let group: WorkspaceGroup
    let baseAccessURL: URL
    let isExpanded: Bool
    let onToggle: () -> Void

    @State private var nameIsSelected: Bool = false

    private var plainName: String {
        "\(group.workspace.name).\(state.hostnameSuffix)"
    }

    private var styledName: AttributedString {
        // Display only the workspace name; the row already represents the
        // workspace in the menu hierarchy. Copy/tooltip retain the full FQDN.
        var name = AttributedString(group.workspace.name)
        name.foregroundColor = .primary
        return name
    }

    private var wsURL: URL {
        // TODO: CoderVPN currently only supports owned workspaces.
        baseAccessURL.appending(path: "@me").appending(path: group.workspace.name)
    }

    var body: some View {
        HStack(spacing: 3) {
            Button(action: onToggle) {
                HStack(spacing: Theme.Size.trayPadding) {
                    AnimatedChevron(isExpanded: isExpanded, color: .secondary)
                    Text(styledName).lineLimit(1).truncationMode(.tail)
                    Spacer()
                }
                .padding(.horizontal, Theme.Size.trayPadding)
                .frame(minHeight: 22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(nameIsSelected ? .white : .primary)
                .background(nameIsSelected ? Color.accentColor.opacity(0.8) : .clear)
                .clipShape(.rect(cornerRadius: Theme.Size.rectCornerRadius))
                .onHover { hovering in nameIsSelected = hovering }
                .help(plainName)
            }.buttonStyle(.plain).padding(.trailing, 3)
            StatusDot(color: group.status.color)
                .padding(.trailing, 3)
                .padding(.top, 1)
                .help(group.status.description)
            MenuItemIconButton(systemName: "globe", action: { openURL(wsURL) })
                .contentShape(Rectangle())
                .font(.system(size: 12))
                .padding(.trailing, Theme.Size.trayMargin)
                .help("Open in browser")
        }
    }
}
