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
                let items = vpn.menuState.sorted
                let visibleItems = viewAll ? items[...] : items.prefix(defaultVisibleRows)
                ForEach(visibleItems, id: \.id) { agent in
                    MenuItemView(item: agent, baseAccessURL: session.baseAccessURL!)
                        .padding(.horizontal, Theme.Size.trayMargin)
                }
                if items.count == 0 {
                    Text("No workspaces!")
                        .font(.body)
                        .foregroundColor(.gray)
                        .padding(.horizontal, Theme.Size.trayInset)
                        .padding(.top, 2)
                }
                // Only show the toggle if there are more items to show
                if items.count > defaultVisibleRows {
                    Toggle(isOn: $viewAll) {
                        Text(viewAll ? "Show less" : "Show all")
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
