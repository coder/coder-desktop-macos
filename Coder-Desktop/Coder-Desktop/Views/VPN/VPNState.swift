import ServiceManagement
import SwiftUI

struct VPNState<VPN: VPNService>: View {
    @EnvironmentObject var vpn: VPN
    @EnvironmentObject var state: AppState

    let inspection = Inspection<Self>()

    var body: some View {
        Group {
            switch (vpn.state, state.hasSession) {
            case (.failed(.systemExtensionError(.needsUserApproval)), _):
                ApprovalRequiredView<VPN>(
                    message: "Awaiting System Extension approval",
                    action: openSystemExtensionSettings
                )
            case (_, false):
                Text("Sign in to use Coder Desktop")
                    .font(.body)
                    .foregroundColor(.secondary)
            case (.failed(.networkExtensionError(.unconfigured)), _):
                VStack {
                    Text("The system VPN requires reconfiguration")
                        .foregroundColor(.secondary)
                        .vpnStateMessage()
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
            case (.failed(.helperError(.requiresApproval)), _):
                ApprovalRequiredView<VPN>(
                    message: "Awaiting Background Item approval",
                    action: SMAppService.openSystemSettingsLoginItems
                )
            case (.failed(.helperError(.installing)), _):
                HelperProgressView()
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
                    .vpnStateMessage()
            case (.connected, true):
                EmptyView()
            }
        }
        .onReceive(inspection.notice) { inspection.visit(self, $0) } // viewInspector
    }
}

struct HelperProgressView: View {
    var body: some View {
        HStack {
            Spacer()
            VStack {
                CircularProgressView(value: nil)
                Text("Installing Helper...")
                    .multilineTextAlignment(.center)
            }
            .padding()
            .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

struct ApprovalRequiredView<VPN: VPNService>: View {
    @EnvironmentObject var vpn: VPN
    let message: String
    let action: () -> Void

    var body: some View {
        VStack {
            Text(message)
                .foregroundColor(.secondary)
                .vpnStateMessage()
            Button {
                action()
            } label: {
                Text("Approve in System Settings")
            }
        }
    }
}

struct VPNStateMessageTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Size.trayInset)
            .padding(.vertical, Theme.Size.trayPadding)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    func vpnStateMessage() -> some View {
        modifier(VPNStateMessageTextModifier())
    }
}
