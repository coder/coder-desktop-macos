import SwiftUI

struct Agents<VPN: VPNService, S: Session>: View {
    @EnvironmentObject var vpn: VPN
    @EnvironmentObject var session: S
    @State private var viewAll = false
    private let defaultVisibleRows = 5

    let inspection = Inspection<Self>()

    var body: some View {
        Group {
            // Agents List
            if vpn.state == .connected {
                let sortedAgents = vpn.agents.values.sorted()
                let visibleData = viewAll ? sortedAgents[...] : sortedAgents.prefix(defaultVisibleRows)
                ForEach(visibleData, id: \.id) { agent in
                    AgentRowView(agent: agent, baseAccessURL: session.baseAccessURL!)
                        .padding(.horizontal, Theme.Size.trayMargin)
                }
                if vpn.agents.count > defaultVisibleRows {
                    Toggle(isOn: $viewAll) {
                        Text(viewAll ? "Show Less" : "Show All")
                            .font(.headline)
                            .foregroundColor(.gray)
                            .padding(.horizontal, Theme.Size.trayInset)
                            .padding(.top, 2)
                    }.toggleStyle(.button).buttonStyle(.plain)
                }
            }
        }.onReceive(inspection.notice) { inspection.visit(self, $0) } // ViewInspector
    }
}
