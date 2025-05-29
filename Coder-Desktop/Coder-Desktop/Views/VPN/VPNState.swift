import SwiftUI

struct VPNState<VPN: VPNService>: View {
    @EnvironmentObject var vpn: VPN
    @EnvironmentObject var state: AppState

    let inspection = Inspection<Self>()

    var body: some View {
        Group {
            switch (vpn.state, state.hasSession) {
            case (.failed(.systemExtensionError(.needsUserApproval)), _):
                VStack {
                    Text("Awaiting System Extension approval")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.Size.trayInset)
                        .padding(.vertical, Theme.Size.trayPadding)
                        .frame(maxWidth: .infinity)
                    Button {
                        openSystemExtensionSettings()
                    } label: {
                        Text("Approve in System Settings")
                    }
                }
            case (_, false):
                Text("Sign in to use Coder Desktop")
                    .font(.body)
                    .foregroundColor(.secondary)
            case (.failed(.networkExtensionError(.unconfigured)), _):
                VStack {
                    Text("The system VPN requires reconfiguration")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.Size.trayInset)
                        .padding(.vertical, Theme.Size.trayPadding)
                        .frame(maxWidth: .infinity)
                    Button {
                        state.reconfigure()
                    } label: {
                        Text("Reconfigure VPN")
                    }
                }.onAppear {
                    // Show the prompt onAppear, so the user doesn't have to
                    // open the menu bar an extra time
                    state.reconfigure()
                }
            case (.disabled, _):
                Text("Enable Coder Connect to see workspaces")
                    .font(.body)
                    .foregroundStyle(.secondary)
            case (.connecting, _), (.disconnecting, _):
                HStack {
                    Spacer()
                    VPNProgressView(state: vpn.state, progress: vpn.progress)
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
