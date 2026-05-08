import SwiftUI

struct Agents<VPN: VPNService>: View {
    @EnvironmentObject var vpn: VPN
    @EnvironmentObject var state: AppState
    @State private var viewAll = false
    @State private var expandedItem: UUID?
    @State private var hasToggledExpansion: Bool = false

    let inspection = Inspection<Self>()

    var body: some View {
        Group {
            if vpn.state == .connected {
                let groups = vpn.menuState.grouped
                let visibleGroups = viewAll
                    ? Array(groups)
                    : Array(groups.prefix(Theme.defaultVisibleAgents))
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(visibleGroups.enumerated()), id: \.element.id) { index, group in
                            if index > 0 {
                                Divider().padding(.horizontal, Theme.Size.trayMargin)
                            }
                            WorkspaceGroupView(
                                group: group,
                                baseAccessURL: state.baseAccessURL!,
                                expandedItem: $expandedItem,
                                userInteracted: $hasToggledExpansion,
                                setAgentParentID: { agentID, parentID in
                                    vpn.setAgentParentID(agentID: agentID, parentID: parentID)
                                }
                            )
                            .padding(.horizontal, Theme.Size.trayMargin)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 400)
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
}
