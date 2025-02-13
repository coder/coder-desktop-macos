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
                    .foregroundStyle(.gray)
            case (_, false):
                Text("Sign in to use CoderVPN")
                    .font(.body)
                    .foregroundColor(.gray)
            case (.disabled, _):
                Text("Enable CoderVPN to see workspaces")
                    .font(.body)
                    .foregroundStyle(.gray)
            case (.connecting, _), (.disconnecting, _):
                HStack {
                    Spacer()
                    ProgressView(
                        vpn.state == .connecting ? "Starting CoderVPN..." : "Stopping CoderVPN..."
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
            default:
                EmptyView()
            }
        }
        .onReceive(inspection.notice) { inspection.visit(self, $0) } // viewInspector
    }
}
