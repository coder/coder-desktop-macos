import SwiftUI

struct Agents<VPN: VPNService>: View {
    @EnvironmentObject var vpn: VPN
    @EnvironmentObject var state: AppState
    @AppStorage(Defaults.agentsEnabled) private var agentsEnabled = false
    @State private var viewAll = false
    @State private var expandedItem: VPNMenuItem.ID?
    @State private var hasToggledExpansion: Bool = false
    /// Workspaces created by an Agents chat, shown with an "Agent" badge like the web UI.
    @State private var agentWorkspaceIDs: Set<UUID> = []
    private let defaultVisibleRows = 5

    let inspection = Inspection<Self>()

    var body: some View {
        Group {
            // Agents List
            if vpn.state == .connected {
                let items = vpn.menuState.sorted
                let visibleItems = viewAll ? items[...] : items.prefix(defaultVisibleRows)
                ScrollView(showsIndicators: false) {
                    ForEach(visibleItems, id: \.id) { agent in
                        MenuItemView(
                            item: agent,
                            baseAccessURL: state.baseAccessURL!,
                            expandedItem: $expandedItem,
                            userInteracted: $hasToggledExpansion,
                            isAgentWorkspace: agentWorkspaceIDs.contains(agent.workspaceID)
                        )
                        .padding(.horizontal, Theme.Size.trayMargin)
                    }.onChange(of: visibleItems) {
                        // If no workspaces are online, we should expand the first one to come online
                        if visibleItems.filter({ $0.status != .off }).isEmpty {
                            hasToggledExpansion = false
                            return
                        }
                        if hasToggledExpansion {
                            return
                        }
                        withAnimation(.snappy(duration: Theme.Animation.collapsibleDuration)) {
                            expandedItem = visibleItems.first?.id
                        }
                        hasToggledExpansion = true
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 400)
                .task(id: Set(items.map(\.workspaceID))) {
                    await loadAgentWorkspaces(Set(items.map(\.workspaceID)))
                }
                if items.count == 0 {
                    Text("No workspaces!")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, Theme.Size.trayInset)
                        .padding(.top, 2)
                }
                // Only show the toggle if there are more items to show
                if items.count > defaultVisibleRows {
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

    /// Asks the server which of the listed workspaces were created by an Agents chat
    /// (the web UI's "Agent" badge). Best-effort: failures just leave rows unbadged.
    private func loadAgentWorkspaces(_ ids: Set<UUID>) async {
        guard agentsEnabled, let client = state.client, !ids.isEmpty else {
            agentWorkspaceIDs = []
            return
        }
        // The endpoint rejects more than 25 IDs per request.
        let idList = Array(ids)
        var badged: Set<UUID> = []
        for start in stride(from: 0, to: idList.count, by: 25) {
            let chunk = Array(idList[start ..< min(start + 25, idList.count)])
            let chats = await (try? client.chatsByWorkspace(workspaceIDs: chunk)) ?? [:]
            badged.formUnion(chats.keys.compactMap { UUID(uuidString: $0) })
        }
        agentWorkspaceIDs = badged
    }
}
