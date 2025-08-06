import SwiftUI

struct VPNState<VPN: VPNService>: View {
    @EnvironmentObject var vpn: VPN
    @EnvironmentObject var state: AppState

    let inspection = Inspection<Self>()

    var body: some View {
        Group {
            switch (vpn.state, state.hasSession) {
            case (.failed(.systemExtensionError(.needsUserApproval)), _):
                ApprovalRequiredView(
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
                    .vpnStateMessage()
            case (.connected, true):
                EmptyView()
            }
        }
        .onReceive(inspection.notice) { inspection.visit(self, $0) } // viewInspector
    }
}

struct ApprovalRequiredView: View {
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
