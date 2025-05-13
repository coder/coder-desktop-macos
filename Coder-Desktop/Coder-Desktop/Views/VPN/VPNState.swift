import SwiftUI

struct VPNState<VPN: VPNService>: View {
    @EnvironmentObject var vpn: VPN
    @EnvironmentObject var state: AppState

    let inspection = Inspection<Self>()

    var body: some View {
        Group {
            switch (vpn.state, state.hasSession) {
            case (.failed(.systemExtensionError(.needsUserApproval)), _):
                Text("Awaiting System Extension approval")
                    .font(.body)
                    .foregroundStyle(.secondary)
            case (_, false):
                Text("Sign in to use Coder Desktop")
                    .font(.body)
                    .foregroundColor(.secondary)
            case (.failed(.networkExtensionError(.unconfigured)), _):
                Text("The system VPN requires reconfiguration.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            case (.disabled, _):
                Text("Enable Coder Connect to see workspaces")
                    .font(.body)
                    .foregroundStyle(.secondary)
            case (.connecting, _), (.disconnecting, _):
                HStack {
                    Spacer()
                    ProgressView(
                        vpn.state == .connecting ? "Starting Coder Connect..." : "Stopping Coder Connect..."
                    ).padding()
                    Spacer()
                }
            case let (.failed(vpnErr), _):
                Text("\(vpnErr.description)")
                    .font(.headline)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Size.trayInset)
                    .padding(.vertical, Theme.Size.trayPadding)
                    .frame(maxWidth: .infinity)
            case (.connected, true):
                EmptyView()
            }
        }
        .onReceive(inspection.notice) { inspection.visit(self, $0) } // viewInspector
    }
}
