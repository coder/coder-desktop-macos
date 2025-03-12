import SwiftUI
import VPNLib

struct InvalidAgentsButton<VPN: VPNService>: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var vpn: VPN
    var msg: String {
        "\(vpn.menuState.invalidAgents.count) invalid \(vpn.menuState.invalidAgents.count > 1 ? "agents" : "agent").."
    }

    var body: some View {
        Button {
            showAlert()
        } label: {
            ButtonRowView(highlightColor: .red) { Text(msg) }
        }.buttonStyle(.plain)
    }

    // `.alert` from SwiftUI doesn't play nice when the calling view is in the
    // menu bar.
    private func showAlert() {
        let formattedAgents = vpn.menuState.invalidAgents.map { agent in
            let agent_id = if let agent_id = UUID(uuidData: agent.id) {
                agent_id.uuidString
            } else {
                "Invalid ID: \(agent.id.base64EncodedString())"
            }
            let wsID = if let wsID = UUID(uuidData: agent.workspaceID) {
                wsID.uuidString
            } else {
                "Invalid ID: \(agent.workspaceID.base64EncodedString())"
            }
            let lastHandshake = agent.hasLastHandshake ? "\(agent.lastHandshake)" : "Never"
            return """
            Agent Name: \(agent.name)
            ID: \(agent_id)
            Workspace ID: \(wsID)
            Last Handshake: \(lastHandshake)
            FQDNs: \(agent.fqdn)
            Addresses: \(agent.ipAddrs)
            """
        }.joined(separator: "\n\n")

        let alert = NSAlert()
        alert.messageText = "Invalid Agents"
        alert.informativeText = """
        Coder Desktop received invalid agents from the VPN. This should
        never happen. Please open an issue on \(About.repo).

        \(formattedAgents)
        """
        alert.alertStyle = .warning
        dismiss()
        alert.runModal()
    }
}
