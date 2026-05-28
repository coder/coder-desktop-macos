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
    /// Per-agent override for the apps section. When present, takes precedence
    /// over the default (parents collapsed, children expanded).
    @State private var appsOverride: [UUID: Bool] = [:]

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
        // Always render through DisclosureGroup so the chevron, indent, and
        // hover treatment match across single-agent, multi-agent, and offline
        // workspaces. The label and expanded content vary per case.
        DisclosureGroup(isExpanded: isExpanded) {
            expandedContent
        } label: {
            WorkspaceDisclosureLabel(
                name: group.workspace.name,
                plainName: "\(group.workspace.name).\(state.hostnameSuffix)",
                wsURL: baseAccessURL.appending(path: "@me").appending(path: group.workspace.name),
                singleAgent: group.agents.count == 1 ? group.agents.first : nil,
                aggregateStatus: group.status,
                aggregateStatusString: group.agents.count == 1
                    ? (group.agents.first?.statusString ?? group.status.description)
                    : group.status.description
            )
        }
        .padding(.horizontal, Theme.Size.trayPadding)
    }

    @ViewBuilder
    private var expandedContent: some View {
        Group {
            if loadingApps, !hasLoadedApps {
                CircularProgressView(value: nil, strokeWidth: 3, diameter: 15)
                    .padding(.top, 5)
            } else if group.agents.isEmpty {
                Text("Workspace is offline.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Size.trayInset)
                    .padding(.top, 4)
            } else if group.agents.count == 1, let only = group.agents.first {
                let apps = appsByAgent[only.id] ?? []
                if apps.isEmpty {
                    Text("No apps available.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.Size.trayInset)
                        .padding(.top, 4)
                } else {
                    MenuItemCollapsibleView(apps: apps)
                }
            } else {
                ForEach(group.topLevelAgents) { parent in
                    AgentDetailRow(
                        agent: parent,
                        apps: appsToShow(for: parent, isChild: false),
                        ports: portsByAgent[parent.id] ?? [],
                        appsToggle: appsToggle(for: parent, isChild: false)
                    )
                    // Each sub-agent gets its own GroupBox so multiple
                    // devcontainers under the same parent stay distinct. The
                    // cube glyph rides on the same row as the agent (no
                    // dedicated header line) — same compactness as the prior
                    // dashed-box treatment, just in stock SwiftUI.
                    ForEach(group.children(of: parent.id)) { child in
                        GroupBox {
                            AgentDetailRow(
                                agent: child,
                                apps: appsToShow(for: child, isChild: true),
                                ports: portsByAgent[child.id] ?? [],
                                appsToggle: appsToggle(for: child, isChild: true),
                                leadingIcon: "cube",
                                leadingIconHelp: "Container"
                            )
                        }
                    }
                }
            }
        }.task(id: group.id) { await loadApps() }
    }

    /// Default visibility per role: parent agents start collapsed (apps
    /// hidden), sub-agents start expanded (apps visible). The `appsOverride`
    /// map flips the default once the user clicks the row's toggle.
    private func appsAreShown(for agentID: UUID, isChild: Bool) -> Bool {
        appsOverride[agentID] ?? isChild
    }

    private func appsToShow(for agent: Agent, isChild: Bool) -> [WorkspaceApp] {
        let apps = appsByAgent[agent.id] ?? []
        return appsAreShown(for: agent.id, isChild: isChild) ? apps : []
    }

    /// Toggle is offered on every agent that has apps — both parent and child.
    /// If the agent has no apps there's nothing to show, so we return nil.
    private func appsToggle(for agent: Agent, isChild: Bool) -> AgentDetailRow.AppsToggle? {
        let apps = appsByAgent[agent.id] ?? []
        guard !apps.isEmpty else { return nil }
        let isShown = appsAreShown(for: agent.id, isChild: isChild)
        return AgentDetailRow.AppsToggle(isShown: isShown) {
            appsOverride[agent.id] = !isShown
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

/// Label slot for the DisclosureGroup. Layout is identical for every case so
/// the system chevron lines up; only the trailing controls shift:
///   - single-agent: name + latency + (status, copy, globe) — agent's status
///   - multi-agent : name + (status, globe) — workspace's aggregate status
///   - offline    : name + (status[off], globe)
///
/// The status dot lives on the trailing side for every row so an unconnected
/// multi-agent workspace doesn't look indistinguishable from a connected one.
/// Buttons inside use `.borderless` so taps don't toggle the disclosure.
private struct WorkspaceDisclosureLabel: View {
    @Environment(\.openURL) private var openURL

    let name: String
    let plainName: String
    let wsURL: URL
    let singleAgent: Agent?
    let aggregateStatus: AgentStatus
    let aggregateStatusString: String

    @State private var copyTick: Int = 0

    var body: some View {
        HStack {
            Text(name)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(plainName)
            if let latency = singleAgent?.lastPing?.latency {
                Text(formatLatency(latency))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Trailing icons in [copy?] [status dot] [globe] order so the
            // status dot stays the 2nd-from-right icon in every workspace row
            // (multi-agent rows have no copy, but the dot still aligns).
            if singleAgent != nil {
                Button(action: copyToClipboard) {
                    Image(systemName: "doc.on.doc.fill")
                        .symbolRenderingMode(.hierarchical)
                        .symbolEffect(.bounce, value: copyTick)
                        .font(.system(size: 9))
                        .padding(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Copy hostname")
            }
            StatusDot(color: aggregateStatus.color)
                .help(aggregateStatusString)
                .padding(.trailing, 3)
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

    private func copyToClipboard() {
        guard let host = singleAgent?.primaryHost else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(host, forType: .string)
        copyTick &+= 1
    }

    private func formatLatency(_ seconds: TimeInterval) -> String {
        "\(Int((seconds * 1000).rounded()))ms"
    }
}
