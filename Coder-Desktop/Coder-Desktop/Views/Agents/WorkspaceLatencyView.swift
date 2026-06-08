import SwiftUI

/// A compact workspace-latency chip mirroring the Coder Desktop menu bar: a status-colored dot
/// plus the round-trip latency, with the same rich peer-to-peer / DERP breakdown on hover. Reads
/// the live ping data from the VPN tunnel state, so it's only meaningful with Coder Connect up;
/// it shows nothing when the workspace has no connected agent.
struct WorkspaceLatencyView<VPN: VPNService>: View {
    @EnvironmentObject var vpn: VPN
    let workspaceID: UUID

    private var agent: Agent? {
        vpn.menuState.agents.values.first { $0.wsID == workspaceID }
    }

    var body: some View {
        if let agent {
            HStack(spacing: 4) {
                Circle().fill(agent.status.color).frame(width: 7, height: 7)
                if let ping = agent.lastPing {
                    Text(ping.latency.prettyPrintMs).font(.caption).foregroundStyle(.secondary)
                }
            }
            .help(agent.statusString)
            .accessibilityLabel(
                "Workspace latency: \(agent.lastPing?.latency.prettyPrintMs ?? agent.status.description)"
            )
        }
    }
}
