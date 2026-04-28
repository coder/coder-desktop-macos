import SwiftUI

struct Agents<VPN: VPNService>: View {
    @EnvironmentObject var vpn: VPN
    @EnvironmentObject var state: AppState
    @State private var viewAll = false
    @State private var expandedItem: UUID?
    @State private var hasToggledExpansion: Bool = false
    @State private var enrichedWorkspaces: Set<UUID> = []

    let inspection = Inspection<Self>()

    var body: some View {
        Group {
            if vpn.state == .connected {
                let groups = vpn.menuState.grouped
                let visibleGroups = viewAll
                    ? Array(groups)
                    : Array(groups.prefix(Theme.defaultVisibleAgents))
                ScrollView(showsIndicators: false) {
                    ForEach(visibleGroups, id: \.id) { group in
                        WorkspaceGroupView(
                            group: group,
                            baseAccessURL: state.baseAccessURL!,
                            expandedItem: $expandedItem,
                            userInteracted: $hasToggledExpansion
                        )
                        .padding(.horizontal, Theme.Size.trayMargin)
                    }.onChange(of: visibleGroups) {
                        // If no workspaces are online, expand the first one to come online.
                        if visibleGroups.allSatisfy({ $0.status == .off }) {
                            hasToggledExpansion = false
                            return
                        }
                        if hasToggledExpansion {
                            return
                        }
                        withAnimation(.snappy(duration: Theme.Animation.collapsibleDuration)) {
                            expandedItem = visibleGroups.first?.defaultExpandID
                        }
                        hasToggledExpansion = true
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 400)
                .task(id: Set(groups.map(\.id))) {
                    await enrichParents(groups: groups)
                }
                if groups.isEmpty {
                    Text("No workspaces!")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, Theme.Size.trayInset)
                        .padding(.top, 2)
                }
                if groups.count > Theme.defaultVisibleAgents {
                    Toggle(isOn: $viewAll) {
                        Text(viewAll ? "Show less" : "Show all")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, Theme.Size.trayInset)
                            .padding(.top, 2)
                    }.toggleStyle(.button).buttonStyle(.plain)
                }
            }
        }.onReceive(inspection.notice) { inspection.visit(self, $0) } // ViewInspector
    }

    /// Backfill agent.parent_id from the HTTP API. The VPN proto doesn't carry
    /// it, so without this children would never nest under their parent in the
    /// tray. Best-effort: failures are silent and retried whenever the set of
    /// workspace IDs changes.
    private func enrichParents(groups: [WorkspaceGroup]) async {
        guard let client = state.client else { return }
        for group in groups where !enrichedWorkspaces.contains(group.id) {
            do {
                let workspace = try await client.workspace(group.id)
                let agents = workspace.latest_build.resources.compactMap(\.agents).flatMap(\.self)
                for agent in agents {
                    vpn.setAgentParentID(agentID: agent.id, parentID: agent.parent_id)
                }
                enrichedWorkspaces.insert(group.id)
            } catch {
                continue
            }
        }
    }
}

private extension WorkspaceGroup {
    /// For the auto-expand-first behavior: single-agent groups expand the
    /// agent's app section (existing UX); multi-agent groups expand the
    /// workspace itself to reveal nested agents.
    var defaultExpandID: UUID {
        if agents.count == 1, let only = agents.first {
            return only.id
        }
        return id
    }
}
